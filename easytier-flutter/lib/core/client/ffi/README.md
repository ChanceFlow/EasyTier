# `easytier-ffi` Dart bridge

Thin `dart:ffi` transport for `easytier-contrib/easytier-ffi`. No packages are
added: string/allocator helpers are implemented on top of `dart:ffi` plus libc
`malloc`/`free`.

| File | Purpose |
| --- | --- |
| `native_library.dart` | Locates and opens the native library, `EasytierFfi.load({String? overridePath})`. |
| `ffi_bindings.dart` | Typedefs for every used C symbol, the `KeyValuePair` struct, C-string helpers, error/version readers. |
| `ffi_core_client.dart` | `FfiCoreClient implements CoreClient` (init/run/stop/delete/save/get/list/collect/validate/version/events) plus `setTunFd`. |
| `../../../tool/build_native.sh` | Builds the cdylib and stages it for desktop, documents the Android build. |

## Added C symbols

Additive only — no existing export changed.

```c
// Push a JSON event per instance state transition. `callback` may be NULL to
// clear, and `user_data` is forwarded unchanged.
int set_instance_event_callback(
    void (*callback)(const char *json, void *user_data),
    void *user_data);
int clear_instance_event_callback(void);

// Copies the linked EasyTier core version ("2.7.0"). Free with free_string().
void get_version(const char **out_version);
```

Event JSON:

```json
{"instance_name":"office-mesh","instance_id":"<uuid>","event":"dhcp_ip_changed","detail":"{\"old\":null,\"new\":\"10.144.0.17/24\"}"}
```

Stable `event` values: `tun_device_ready`, `tun_device_error`, `peer_added`,
`peer_removed`, `peer_conn_added`, `peer_conn_removed`, `listener_added`,
`listener_add_failed`, `listener_accept_failed`, `connection_accepted`,
`connection_error`, `listener_port_mapping_established`, `connecting`,
`connect_error`, `vpn_portal_*`, `dhcp_ip_changed`, `dhcp_ip_conflicted`,
`public_ipv6_changed`, `public_ipv6_routes_updated`, `port_forward_added`,
`proxy_cidrs_updated`, `udp_broadcast_relay_*`, `credential_changed`,
`event_lagged`. Anything else is dropped until it gets a mapping.

### Payload ownership differs from the config-server callback

The config-server callback borrows its string for the duration of the call.
The **instance event** callback transfers ownership: the callee must copy the
JSON and call `free_string(ptr)`. This is required because `dart:ffi`'s
`NativeCallable.listener` dispatches the callback asynchronously to the Dart
isolate, long after the native call returns; a borrowed pointer would dangle.
`FfiCoreClient._handleNativeEvent` always frees the pointer in a `finally`
block.

Events are delivered on a tokio runtime worker. The Dart callback only copies
the string and enqueues a Dart event, so it returns immediately; do not call
blocking FFI functions (`run_network_instance`, `delete_network_instance`,
`collect_network_infos`, `call_json_rpc`) from inside a native callback — those
use `Runtime::block_on` and would panic if re-entered from the runtime.

## Library discovery

`EasytierFfi.load()` tries, in order:

1. explicit `overridePath` argument,
2. `EASYTIER_FFI_LIB` environment variable,
3. next to the running executable,
4. `<cwd>/build/native/<name>` (what `tool/build_native.sh` populates for `flutter run`),
5. the bare soname through the platform loader,
6. `DynamicLibrary.process()` on iOS (static link).

| Platform | File name | How the app ships it |
| --- | --- | --- |
| Linux | `libeasytier_ffi.so` | next to the executable or in the bundle's lib dir |
| macOS | `libeasytier_ffi.dylib` | `.app/Contents/Frameworks/` |
| Windows | `easytier_ffi.dll` | next to the `.exe` |
| Android | `libeasytier_ffi.so` | `android/app/src/main/jniLibs/<abi>/` |
| iOS | static lib | linked into the runner, resolved via the process image |

Failure to load raises `EasytierFfiLoadException` listing every attempted path
and the reason it failed. A library missing any bound symbol is reported the
same way instead of failing later inside a call.

## Building the native library

```bash
# desktop (debug), then artifacts land in easytier-flutter/build/native/
easytier-flutter/tool/build_native.sh

# Android, all four ABIs into jniLibs/
export ANDROID_NDK_HOME=/path/to/ndk
easytier-flutter/tool/build_native.sh --android
```

Rust prerequisites in this repository: `protoc` (or `PROTOC=...`) for
`easytier-proto`, and the linker configured in `.cargo/config.toml`
(`-fuse-ld=mold`) must exist.

## Wiring `set_tun_fd` after `VpnService.establish()`

`easytier-ffi` can only attach the TUN descriptor after the Android host has
established the VPN. The flow is:

```kotlin
// MainActivity / VpnService host, after Builder.establish() returns a ParcelFileDescriptor
val fd = vpnInterface.fileDescriptor
channel.invokeMethod("tunFdReady", mapOf("fd" to fd))
vpnInterface.detachFd() // keep the descriptor alive across the channel
```

```dart
// Dart host side (e.g. in the Android VPN bootstrap, after the MethodChannel call)
final client = FfiCoreClient(configDirectory: filesDirFromHost);
await client.init();
final instanceId = await client.runInstance(config);
await client.setTunFd(instanceId, fd);
```

Notes:

* The descriptor must stay open until the core has attached it; call
  `setTunFd` immediately after `runInstance` returns and before traffic is
  expected. `detachFd()` transfers ownership, which is what the core expects
  (`set_tun_fd` takes ownership of the fd).
* Only one instance can own the Android TUN interface. When switching networks,
  stop the previous instance first (same constraint as the Tauri client).
* The core config must keep `no_tun = false` and cannot use `use_smoltcp` for a
  real TUN device.

## Configuration persistence

`easytier-ffi` has no config-file host (its process management uses a static
config control), so `FfiCoreClient` persists configs itself as JSON:

* desktop: `$XDG_CONFIG_HOME/easytier` (or `~/.config/easytier`,
  `%APPDATA%\EasyTier`, `~/Library/Application Support/EasyTier`),
* override via `EASYTIER_FLUTTER_CONFIG_DIR` or
  `FfiCoreClient(configDirectory: ...)`,
* Android/iOS cannot discover the sandbox directory from `dart:io` alone: the
  host **must** pass `configDirectory` (Android `context.filesDir`, iOS
  Application Support). The temporary-directory fallback keeps the app running
  but does not survive a restart.

The instance UUID is written into the generated TOML as `instance_id`, so
`NetworkInstance.id` is stable across restarts and identical to the id returned
by `list_instance`.

## Remaining work before a real device/desktop run

* Cross-compile and package the shared library for each target (see above); no
  `.so`/`.dll`/`.dylib` is committed.
* Android: wire the `VpnService` MethodChannel to `setTunFd` and grant the
  `BIND_VPN_SERVICE`/notification permissions (owned by the Android task).
* Desktop: TUN creation needs root or `CAP_NET_ADMIN` (the Tauri client's
  privilege helper is not ported here).
* `run_network_instance`/`delete_network_instance` are executed on a short-lived
  worker isolate because they call `Runtime::block_on`; a persistent worker would
  avoid reopening the library on each start.
* Config-server (remote managed config) and the data-plane API are not exposed
  through `CoreClient` yet; only the local instance API is wired.
* ACL rules are a best-effort mapping onto `acl.acl_v1` chains with
  `default_action = Allow`; validate against the core ACL UI before relying on
  deny rules for security.
