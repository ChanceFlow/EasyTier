//! Instance runtime event callback bridge.
//!
//! The rest of this crate is pull based: callers start/stop instances and then
//! poll `list_instance` / `collect_network_infos`. The Tauri client used to get
//! state transitions pushed because it linked the `easytier` crate directly and
//! called `subscribe_native_instance_event`. This module exposes the same push
//! channel over the C ABI so non-Rust hosts (the Flutter client) can react to
//! DHCP address changes, peer churn and proxy CIDR updates without polling.
//!
//! Lifecycle:
//! - `set_instance_event_callback` installs (or replaces) the process-wide
//!   callback and subscribes to every instance that is already running.
//! - Instances started afterwards (`run_network_instance`, or a managed remote
//!   config-server run) subscribe when they are registered in the manager.
//! - Instances removed through `delete_network_instance`, `retain_network_instance`,
//!   a config-server delete, or a stopped config-server client are unsubscribed
//!   and their forwarding task is aborted.
//! - `clear_instance_event_callback` unsubscribes everything.
//!
//! Threading: each instance has one forwarding task on the shared FFI tokio
//! runtime. The callback is invoked from that runtime worker, so it must return
//! promptly and must not call back into blocking FFI APIs (those use
//! `Runtime::block_on` and would panic if re-entered from their own runtime).
//!
//! Payload ownership: because `dart:ffi`'s `NativeCallable.listener` delivers
//! callbacks asynchronously, the JSON string cannot be borrowed for the
//! duration of the call. The string is allocated by this library and its
//! ownership is transferred to the callback; the callee must release it with
//! `free_string` once it has copied the contents. Failing to release it leaks
//! the string.

use std::{
    collections::HashMap,
    ffi::{CString, c_char, c_int, c_void},
    sync::Mutex,
};

use easytier::{
    common::global_ctx::GlobalCtxEvent,
    instance::factory::subscribe_native_instance_event,
};
use tokio::task::JoinHandle;
use uuid::Uuid;

use crate::{error::set_error_msg, state::ffi_context, types::InstanceEventCallback};

/// One registered callback plus its opaque user data.
struct DeliveryTarget {
    callback: unsafe extern "C" fn(*const c_char, *mut c_void),
    /// Stored as `usize` so the slot can move between runtime threads.
    user_data: usize,
}

// # Safety
// The pointed-to function and `user_data` are owned by the FFI caller, which
// must keep them valid until `clear_instance_event_callback` returns (or a new
// callback replaces them). This mirrors `ConfigServerEventCallback` in
// `types.rs`; the values are only ever forwarded back to that same caller.
unsafe impl Send for DeliveryTarget {}
unsafe impl Sync for DeliveryTarget {}

#[derive(Default)]
struct EventSubscriptions {
    target: Option<DeliveryTarget>,
    /// One forwarding task per running instance, keyed by instance id.
    tasks: HashMap<Uuid, JoinHandle<()>>,
}

static EVENT_SUBSCRIPTIONS: once_cell::sync::Lazy<Mutex<EventSubscriptions>> =
    once_cell::sync::Lazy::new(|| Mutex::new(EventSubscriptions::default()));

/// Install or replace the instance event callback.
///
/// Passing a `None` callback is equivalent to clearing; `user_data` is then
/// ignored. Returns `0` on success and `-1` if the internal subscription table
/// is poisoned, in which case `get_error_msg` describes the failure.
pub(crate) fn set_instance_event_callback(
    callback: InstanceEventCallback,
    user_data: *mut c_void,
) -> c_int {
    let target = callback.map(|callback| DeliveryTarget {
        callback,
        user_data: user_data as usize,
    });
    match EVENT_SUBSCRIPTIONS.lock() {
        Ok(mut guard) => {
            // Replacing the callback restarts the subscriptions so every task
            // delivers to the callback that is current at install time.
            for (_, task) in guard.tasks.drain() {
                task.abort();
            }
            guard.target = target;
        }
        Err(err) => {
            set_error_msg(&format!("failed to lock instance event subscriptions: {err}"));
            return -1;
        }
    }

    resubscribe_running_instances();
    0
}

/// Remove the callback and stop every forwarding task.
pub(crate) fn clear_instance_event_callback() -> c_int {
    match EVENT_SUBSCRIPTIONS.lock() {
        Ok(mut guard) => {
            for (_, task) in guard.tasks.drain() {
                task.abort();
            }
            guard.target = None;
            0
        }
        Err(err) => {
            set_error_msg(&format!("failed to lock instance event subscriptions: {err}"));
            -1
        }
    }
}

/// Start forwarding events for one newly started instance.
///
/// Does nothing when no callback is installed or when the instance's runtime
/// host does not expose an event bus (for example a non-native instance).
pub(crate) fn subscribe_instance_events(instance_id: Uuid) {
    // Snapshot the target without touching the manager while holding the lock.
    let target = match EVENT_SUBSCRIPTIONS.lock() {
        Ok(guard) => guard.target.as_ref().map(|target| DeliveryTarget {
            callback: target.callback,
            user_data: target.user_data,
        }),
        Err(_) => None,
    };
    let Some(target) = target else {
        return;
    };

    let Some(instance) = ffi_context().manager.instance(instance_id) else {
        return;
    };
    let instance_name = instance.instance_name().to_owned();
    let Some(events) = subscribe_native_instance_event(&instance) else {
        return;
    };
    let task = ffi_context()
        .runtime
        .spawn(forward_instance_events(instance_id, instance_name, events, target));

    match EVENT_SUBSCRIPTIONS.lock() {
        Ok(mut guard) => {
            if guard.target.is_none() {
                // The callback was cleared while we were subscribing.
                task.abort();
                return;
            }
            if let Some(previous) = guard.tasks.insert(instance_id, task) {
                previous.abort();
            }
        }
        Err(_) => task.abort(),
    }
}

/// Stop forwarding events for several removed instances at once.
pub(crate) fn unsubscribe_instances(instance_ids: &[Uuid]) {
    if instance_ids.is_empty() {
        return;
    }
    if let Ok(mut guard) = EVENT_SUBSCRIPTIONS.lock() {
        for instance_id in instance_ids {
            if let Some(task) = guard.tasks.remove(instance_id) {
                task.abort();
            }
        }
    }
}

fn resubscribe_running_instances() {
    let subscribed = match EVENT_SUBSCRIPTIONS.lock() {
        Ok(guard) => guard.target.is_some(),
        Err(_) => false,
    };
    if !subscribed {
        return;
    }
    for instance_id in ffi_context().manager.instance_ids() {
        subscribe_instance_events(instance_id);
    }
}

async fn forward_instance_events(
    instance_id: Uuid,
    instance_name: String,
    mut events: easytier::common::global_ctx::EventBusSubscriber,
    target: DeliveryTarget,
) {
    loop {
        match events.recv().await {
            Ok(event) => {
                if let Some((name, detail)) = event_payload(&event) {
                    emit_event(&target, instance_id, &instance_name, name, detail);
                }
            }
            Err(tokio::sync::broadcast::error::RecvError::Closed) => return,
            Err(tokio::sync::broadcast::error::RecvError::Lagged(skipped)) => {
                emit_event(
                    &target,
                    instance_id,
                    &instance_name,
                    "event_lagged",
                    Some(format!("{skipped} events skipped")),
                );
            }
        }
    }
}

fn emit_event(
    target: &DeliveryTarget,
    instance_id: Uuid,
    instance_name: &str,
    event: &str,
    detail: Option<String>,
) {
    let payload = serde_json::json!({
        "instance_name": instance_name,
        "instance_id": instance_id.to_string(),
        "event": event,
        "detail": detail,
    })
    .to_string();
    // The string is handed over to the callback (see the module docs); it is
    // released by the callee through `free_string`.
    let Ok(payload) = CString::new(payload) else {
        return;
    };
    unsafe {
        (target.callback)(payload.into_raw(), target.user_data as *mut c_void);
    }
}

/// Map a runtime event to the stable `(event_name, detail)` wire format.
///
/// Event names are part of the ABI; new `GlobalCtxEvent` variants are ignored
/// until they get an explicit mapping here. `None` means "do not deliver".
pub(crate) fn event_payload(event: &GlobalCtxEvent) -> Option<(&'static str, Option<String>)> {
    use GlobalCtxEvent::*;

    let payload = match event {
        TunDeviceReady(device) => ("tun_device_ready", Some(device.clone())),
        TunDeviceError(error) => ("tun_device_error", Some(error.clone())),
        PeerAdded(peer_id) => ("peer_added", Some(peer_id.to_string())),
        PeerRemoved(peer_id) => ("peer_removed", Some(peer_id.to_string())),
        PeerConnAdded(conn_info) => (
            "peer_conn_added",
            Some(format!("{}:{}", conn_info.my_peer_id, conn_info.peer_id)),
        ),
        PeerConnRemoved(conn_info) => (
            "peer_conn_removed",
            Some(format!("{}:{}", conn_info.my_peer_id, conn_info.peer_id)),
        ),
        ListenerAdded(url) => ("listener_added", Some(url.to_string())),
        ListenerAddFailed(url, error) => {
            ("listener_add_failed", Some(format!("{url}: {error}")))
        }
        ListenerAcceptFailed(url, error) => {
            ("listener_accept_failed", Some(format!("{url}: {error}")))
        }
        ConnectionAccepted(local, remote) => {
            ("connection_accepted", Some(format!("{local} <- {remote}")))
        }
        ConnectionError(local, remote, error) => {
            ("connection_error", Some(format!("{local} <- {remote}: {error}")))
        }
        ListenerPortMappingEstablished {
            local_listener,
            mapped_listener,
            backend,
        } => (
            "listener_port_mapping_established",
            Some(format!("{local_listener} -> {mapped_listener} via {backend}")),
        ),
        Connecting(url) => ("connecting", Some(url.to_string())),
        ConnectError(dst, ip_version, error) => {
            ("connect_error", Some(format!("{dst} ({ip_version}): {error}")))
        }
        VpnPortalStarted(portal) => ("vpn_portal_started", Some(portal.clone())),
        VpnPortalClientConnected(portal, client) => {
            ("vpn_portal_client_connected", Some(format!("{portal}: {client}")))
        }
        VpnPortalClientDisconnected(portal, client) => (
            "vpn_portal_client_disconnected",
            Some(format!("{portal}: {client}")),
        ),
        DhcpIpv4Changed(old, new) => (
            "dhcp_ip_changed",
            Some(
                serde_json::json!({
                    "old": old.map(|ip| ip.to_string()),
                    "new": new.map(|ip| ip.to_string()),
                })
                .to_string(),
            ),
        ),
        DhcpIpv4Conflicted(ip) => ("dhcp_ip_conflicted", Some(ip.map(|ip| ip.to_string()).unwrap_or_default())),
        PublicIpv6Changed(old, new) => (
            "public_ipv6_changed",
            Some(
                serde_json::json!({
                    "old": old.map(|ip| ip.to_string()),
                    "new": new.map(|ip| ip.to_string()),
                })
                .to_string(),
            ),
        ),
        PublicIpv6RoutesUpdated(added, removed) => (
            "public_ipv6_routes_updated",
            Some(
                serde_json::json!({
                    "added": added.iter().map(|cidr| cidr.to_string()).collect::<Vec<_>>(),
                    "removed": removed.iter().map(|cidr| cidr.to_string()).collect::<Vec<_>>(),
                })
                .to_string(),
            ),
        ),
        PortForwardAdded(config) => (
            "port_forward_added",
            serde_json::to_string(config).ok(),
        ),
        ProxyCidrsUpdated(added, removed) => (
            "proxy_cidrs_updated",
            Some(
                serde_json::json!({
                    "added": added.iter().map(|cidr| cidr.to_string()).collect::<Vec<_>>(),
                    "removed": removed.iter().map(|cidr| cidr.to_string()).collect::<Vec<_>>(),
                })
                .to_string(),
            ),
        ),
        UdpBroadcastRelayStartResult {
            capture_backend,
            error,
        } => match error {
            Some(error) => (
                "udp_broadcast_relay_start_failed",
                Some(format!(
                    "{}: {error}",
                    capture_backend.clone().unwrap_or_default()
                )),
            ),
            None => (
                "udp_broadcast_relay_started",
                capture_backend.clone(),
            ),
        },
        CredentialChanged => ("credential_changed", None),
        _ => return None,
    };
    Some(payload)
}

#[cfg(test)]
mod tests {
    use std::{
        ffi::CString,
        sync::Mutex,
        time::{Duration, Instant},
    };

    use super::*;

    /// The callback is process-global, so tests that install or clear it must
    /// not run concurrently with each other.
    static CALLBACK_TEST_LOCK: Mutex<()> = Mutex::new(());

    fn test_lock() -> std::sync::MutexGuard<'static, ()> {
        CALLBACK_TEST_LOCK
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    unsafe fn take_last_error() -> Option<String> {
        let mut pointer: *const c_char = std::ptr::null();
        unsafe { crate::get_error_msg(&mut pointer) };
        if pointer.is_null() {
            return None;
        }
        let text = unsafe { std::ffi::CStr::from_ptr(pointer) }
            .to_string_lossy()
            .into_owned();
        crate::free_string(pointer);
        Some(text)
    }

    unsafe extern "C" fn record_event(json: *const c_char, user_data: *mut c_void) {
        let events = unsafe { &*(user_data as *const Mutex<Vec<String>>) };
        let text = unsafe { std::ffi::CStr::from_ptr(json) }
            .to_string_lossy()
            .into_owned();
        // Mirror the Dart ownership contract: the callee releases the payload.
        crate::free_string(json);
        if let Ok(mut guard) = events.lock() {
            guard.push(text);
        }
    }

    fn run_config(config: &str) -> i32 {
        let config = CString::new(config).expect("test config has no NUL");
        unsafe { crate::run_network_instance(config.as_ptr()) }
    }

    fn delete_instance(name: &str) {
        let name = CString::new(name).expect("instance name has no NUL");
        let names = [name.as_ptr()];
        unsafe { crate::delete_network_instance(names.as_ptr(), 1) };
    }

    #[test]
    fn peer_events_use_stable_names() {
        assert_eq!(
            event_payload(&GlobalCtxEvent::PeerAdded(7)),
            Some(("peer_added", Some("7".to_string())))
        );
        assert_eq!(
            event_payload(&GlobalCtxEvent::PeerRemoved(9)),
            Some(("peer_removed", Some("9".to_string())))
        );
        assert_eq!(
            event_payload(&GlobalCtxEvent::CredentialChanged),
            Some(("credential_changed", None))
        );
    }

    #[test]
    fn callback_can_be_installed_replaced_and_cleared() {
        let _guard = test_lock();
        unsafe extern "C" fn first(_: *const c_char, _: *mut c_void) {}
        unsafe extern "C" fn second(_: *const c_char, _: *mut c_void) {}

        // Running instances may be subscribed by the install path; the abort on
        // clear must leave no forwarding task behind for the test process.
        assert_eq!(
            unsafe { crate::set_instance_event_callback(Some(first), std::ptr::null_mut()) },
            0
        );
        assert_eq!(
            unsafe { crate::set_instance_event_callback(Some(second), std::ptr::null_mut()) },
            0
        );
        assert_eq!(crate::clear_instance_event_callback(), 0);
        assert_eq!(crate::clear_instance_event_callback(), 0);
    }

    #[test]
    fn event_callback_pushes_json_events_for_running_instances() {
        let _guard = test_lock();
        let events = Mutex::new(Vec::<String>::new());
        let user_data = (&events as *const Mutex<Vec<String>>) as *mut c_void;
        assert_eq!(
            unsafe { crate::set_instance_event_callback(Some(record_event), user_data) },
            0
        );

        let suffix = Uuid::new_v4();
        let network_name = format!("evt-net-{suffix}");
        let name_a = format!("evt-a-{suffix}");
        let name_b = format!("evt-b-{suffix}");

        // Reserve a loopback port for A's listener, then let the core bind it.
        let port = {
            let listener = std::net::TcpListener::bind("127.0.0.1:0").expect("free port");
            listener.local_addr().expect("local addr").port()
        };

        let config_a = format!(
            r#"
instance_name = "{name_a}"
hostname = "evt-a"
dhcp = false
ipv4 = "10.200.0.1/24"
listeners = ["tcp://127.0.0.1:{port}"]

[network_identity]
network_name = "{network_name}"
network_secret = "event-secret"

[flags]
no_tun = true
bind_device = false
"#
        );
        let config_b = format!(
            r#"
instance_name = "{name_b}"
hostname = "evt-b"
dhcp = false
ipv4 = "10.200.0.2/24"
listeners = []

[[peer]]
uri = "tcp://127.0.0.1:{port}"

[network_identity]
network_name = "{network_name}"
network_secret = "event-secret"

[flags]
no_tun = true
bind_device = false
"#
        );

        assert_eq!(
            run_config(&config_a),
            0,
            "starting A failed: {:?}",
            unsafe { take_last_error() }
        );
        assert_eq!(
            run_config(&config_b),
            0,
            "starting B failed: {:?}",
            unsafe { take_last_error() }
        );

        // A subscribes before B starts, so A's accept/peer events must arrive
        // through the callback even though B's own startup events may race the
        // subscription installed right after its start.
        let deadline = Instant::now() + Duration::from_secs(15);
        let mut observed = Vec::new();
        loop {
            if let Ok(mut guard) = events.lock() {
                observed.append(&mut guard);
            }
            if observed
                .iter()
                .any(|event| event.contains(name_a.as_str()) || event.contains(name_b.as_str()))
            {
                break;
            }
            if Instant::now() >= deadline {
                break;
            }
            std::thread::sleep(Duration::from_millis(100));
        }

        delete_instance(&name_a);
        delete_instance(&name_b);
        assert_eq!(crate::clear_instance_event_callback(), 0);

        assert!(
            !observed.is_empty(),
            "no instance events were delivered within 15s"
        );
        let mut matched_peer_event = false;
        for event in &observed {
            let parsed: serde_json::Value =
                serde_json::from_str(event).expect("event payload is JSON");
            assert!(parsed.get("instance_name").is_some(), "missing instance_name: {event}");
            assert!(parsed.get("instance_id").is_some(), "missing instance_id: {event}");
            assert!(parsed.get("event").is_some(), "missing event name: {event}");
            let name = parsed["instance_name"].as_str().unwrap_or_default();
            let event_name = parsed["event"].as_str().unwrap_or_default();
            if (name == name_a || name == name_b)
                && matches!(
                    event_name,
                    "peer_added"
                        | "connection_accepted"
                        | "peer_conn_added"
                        | "connecting"
                        | "listener_added"
                        | "connect_error"
                )
            {
                matched_peer_event = true;
            }
        }
        assert!(
            matched_peer_event,
            "expected a peer/listener event, got: {:?}",
            observed
        );
    }
}
