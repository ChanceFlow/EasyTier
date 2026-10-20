import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android VPN data-plane seam for the EasyTier Flutter client.
///
/// On Android the TUN descriptor can only come from `android.net.VpnService`,
/// which lives in the native app module
/// (`android/app/src/main/kotlin/com/kkrainbow/easytier_flutter/`). This file is
/// the Dart end of that MethodChannel/EventChannel pair:
///
///   set of commands           `com.kkrainbow.easytier/vpn`
///   push events (fd, revoke)  `com.kkrainbow.easytier/vpn/events`
///
/// The fd flow is:
///
///   VpnService.establish()
///     -> ParcelFileDescriptor.detachFd()
///     -> MethodChannel `start` result ({fd, ...})   (or `started` event when
///                                                    the tunnel was started
///                                                    from the tile)
///     -> [VpnTunnel.fd]
///     -> `VpnController.tunFds` / `TunFdSink`
///     -> the Rust bridge's `set_tun_fd(instanceName, fd)`.
///
/// This file deliberately knows nothing about the FFI client: the controller
/// depends on the tiny `TunFdSink` seam in `vpn_controller.dart` instead.
///
/// Platform support: Android only for now. Desktop returns
/// [UnsupportedVpnService]; screens should treat "no VPN service" as "the core
/// manages its own TUN" (desktop does not need a VpnService).

/// Why a tunnel went down.
///
/// Android's `VpnService` does not tell the app why it stopped, so the native
/// side reports which callback it came through. The distinction matters:
/// [revoked] means another VPN app took the process-wide VPN slot and the Rust
/// instance keeps running, so the UI must be forced out of "connected" instead
/// of lying about a tunnel that carries no traffic.
enum VpnStopReason {
  /// Notification "Disconnect" action or an in-app stop.
  user('user'),

  /// The system took the VPN slot away (`VpnService.onRevoke`).
  revoked('revoked'),

  /// The foreground service was destroyed by the system.
  destroy('destroy'),

  /// A newer [VpnService.start] replaced this tunnel (one TUN per app).
  superseded('superseded'),

  /// `establish()` failed or the service could not start.
  error('error');

  const VpnStopReason(this.wireName);

  /// Value used on the platform channel.
  final String wireName;

  /// Decodes the native `reason`; unknown values map to [error] so a future
  /// native reason can never be mistaken for a healthy tunnel.
  static VpnStopReason fromWire(Object? raw) {
    for (final reason in values) {
      if (reason.wireName == raw) return reason;
    }
    return VpnStopReason.error;
  }

  /// True when the tunnel was taken away rather than stopped by the user.
  bool get isExternal => this == revoked || this == error;
}

/// Quick-settings tile actions drained from the pending-action slot.
enum VpnTileAction {
  start('start'),
  stop('stop');

  const VpnTileAction(this.wireName);

  final String wireName;

  static VpnTileAction? fromWire(Object? raw) {
    for (final action in values) {
      if (action.wireName == raw) return action;
    }
    return null;
  }
}

/// Parameters for one TUN. The UI/core computes them from the network config:
/// the virtual IP/DHCP lease, the routed CIDRs (proxy CIDRs, exit node), DNS and
/// MTU. The native side adds the tunnel address, routes and DNS servers to
/// Android's VPN builder - nothing else can program routes on Android without
/// root.
class VpnRequest {
  const VpnRequest({
    required this.ipv4Cidr,
    this.ipv6Cidr = 'fd00::1/128',
    this.routes = const <String>[],
    this.dns = const <String>[],
    this.mtu = 1300,
    this.session = 'EasyTier',
    this.disallowedApplications = const <String>[],
  });

  /// Tunnel address in CIDR notation, e.g. `10.144.0.2/24`.
  final String ipv4Cidr;

  /// Optional IPv6 tunnel address (the Tauri client always added
  /// `fd00::1/128`); pass null to leave IPv6 alone.
  final String? ipv6Cidr;

  /// CIDRs routed into the tunnel, e.g. the virtual subnet plus proxy CIDRs.
  final List<String> routes;

  /// DNS servers pushed to the system resolver for the tunnel.
  final List<String> dns;

  /// Tunnel MTU. 1300 matches the Tauri client's mobile tunnel and the older
  /// android-jni integration.
  final int mtu;

  /// `VpnService.Builder.setSession` label shown in the system VPN list.
  final String session;

  /// Extra packages excluded from the tunnel. This app's own package is always
  /// excluded natively (peer/RPC sockets must not loop back into the TUN).
  final List<String> disallowedApplications;

  Map<String, Object?> toMap() => <String, Object?>{
    'ipv4Cidr': ipv4Cidr,
    'ipv6Cidr': ipv6Cidr,
    'routes': routes,
    'dns': dns,
    'mtu': mtu,
    'session': session,
    'disallowedApplications': disallowedApplications,
  };

  @override
  String toString() =>
      'VpnRequest(ipv4: $ipv4Cidr, routes: $routes, dns: $dns, mtu: $mtu)';
}

/// One established Android TUN.
///
/// The native side is the owner of the descriptor (it closes it on teardown);
/// the Rust core only borrows it. [fd] is therefore only meaningful while the
/// tunnel is up, and must never be closed from Dart.
class VpnTunnel {
  const VpnTunnel({
    required this.fd,
    required this.ipv4Cidr,
    this.ipv6Cidr,
    this.routes = const <String>[],
    this.dns = const <String>[],
    this.mtu = 0,
    this.session = 'EasyTier',
  });

  /// Raw TUN file descriptor produced by `ParcelFileDescriptor.detachFd()`.
  final int fd;

  final String ipv4Cidr;
  final String? ipv6Cidr;
  final List<String> routes;
  final List<String> dns;
  final int mtu;
  final String session;

  static VpnTunnel fromMap(Map<Object?, Object?> map) {
    final fd = map['fd'];
    if (fd is! int) {
      throw const VpnException(
        'bad_tunnel',
        'the native start result did not carry a TUN fd',
      );
    }
    return VpnTunnel(
      fd: fd,
      ipv4Cidr: map['ipv4Cidr'] as String? ?? '',
      ipv6Cidr: map['ipv6Cidr'] as String?,
      routes: _stringList(map['routes']),
      dns: _stringList(map['dns']),
      mtu: map['mtu'] as int? ?? 0,
      session: map['session'] as String? ?? 'EasyTier',
    );
  }

  @override
  String toString() => 'VpnTunnel(fd: $fd, ipv4: $ipv4Cidr, mtu: $mtu)';
}

/// Snapshot of the native VPN state, used to reconcile after the Flutter engine
/// restarted while the foreground service kept running.
class VpnStatus {
  const VpnStatus({
    required this.running,
    this.ipv4Cidr,
    this.ipv6Cidr,
    this.routes = const <String>[],
    this.dns = const <String>[],
    this.mtu = 0,
    this.lastError,
  });

  final bool running;
  final String? ipv4Cidr;
  final String? ipv6Cidr;
  final List<String> routes;
  final List<String> dns;
  final int mtu;

  /// Last native `establish()`/start failure, if any.
  final String? lastError;

  static VpnStatus fromMap(Map<Object?, Object?> map) => VpnStatus(
    running: map['running'] == true,
    ipv4Cidr: map['ipv4Cidr'] as String?,
    ipv6Cidr: map['ipv6Cidr'] as String?,
    routes: _stringList(map['routes']),
    dns: _stringList(map['dns']),
    mtu: map['mtu'] as int? ?? 0,
    lastError: map['lastError'] as String?,
  );

  @override
  String toString() => 'VpnStatus(running: $running, ipv4: $ipv4Cidr)';
}

/// Whether the ongoing notification can actually be seen by the user.
class VpnNotificationStatus {
  const VpnNotificationStatus({required this.granted, required this.enabled});

  /// POST_NOTIFICATIONS runtime grant (always true below Android 13).
  final bool granted;

  /// The app-wide notification toggle in system settings.
  final bool enabled;

  bool get canShowOngoing => granted && enabled;

  static VpnNotificationStatus fromMap(Map<Object?, Object?> map) =>
      VpnNotificationStatus(
        granted: map['granted'] == true,
        enabled: map['enabled'] == true,
      );
}

/// Failure talking to the native VPN layer.
class VpnException implements Exception {
  const VpnException(this.code, this.message);

  /// Native error code, e.g. `vpn_start_failed`, `bad_args`, `vpn_busy`.
  final String code;
  final String message;

  @override
  String toString() => 'VpnException($code): $message';
}

/// Push events from the native VPN layer.
sealed class VpnEvent {
  const VpnEvent();

  /// Decodes a native payload; null for an unknown `type` (forward compatible).
  static VpnEvent? fromMap(Object? raw) {
    if (raw is! Map) return null;
    switch (raw['type']) {
      case 'started':
        return VpnStarted(VpnTunnel.fromMap(raw));
      case 'stopped':
        return VpnStopped(VpnStopReason.fromWire(raw['reason']));
      case 'error':
        return VpnError(raw['message'] as String? ?? 'unknown VPN error');
      case 'tileAction':
        return VpnTileActionEvent(
          VpnTileAction.fromWire(raw['action']) ?? VpnTileAction.start,
        );
      default:
        return null;
    }
  }
}

/// A tunnel became ready. Only emitted for tunnels this Dart caller did not
/// start itself (quick-settings tile), so the fd is delivered exactly once.
final class VpnStarted extends VpnEvent {
  const VpnStarted(this.tunnel);

  final VpnTunnel tunnel;
}

/// A tunnel went down, for any reason. [reason] is the authoritative "why" and
/// [VpnStopReason.revoked] must force the UI out of "connected".
final class VpnStopped extends VpnEvent {
  const VpnStopped(this.reason);

  final VpnStopReason reason;
}

/// The native layer failed (usually during `establish()`); the payload is a
/// human-readable message for logs, not for UI copy.
final class VpnError extends VpnEvent {
  const VpnError(this.message);

  final String message;
}

/// A quick-settings tile tap was handed to Dart.
final class VpnTileActionEvent extends VpnEvent {
  const VpnTileActionEvent(this.action);

  final VpnTileAction action;
}

/// The VPN seam. Two implementations ship here: [MethodChannelVpnService]
/// (Android) and [UnsupportedVpnService] (desktop/no-op). [FakeVpnService] is
/// for tests and design-preview wiring.
abstract class VpnService {
  /// Const so stateless implementations (desktop no-op) can be const too.
  const VpnService();

  /// Requests VPN consent, showing the system dialog if needed. Must be called
  /// from a foreground activity; returns false when the user declined.
  Future<bool> prepare();

  /// Establishes the tunnel and returns its fd.
  ///
  /// Returns null when the VPN consent was withdrawn (native `need_prepare`);
  /// call [prepare] first. Throws [VpnException] for real failures.
  Future<VpnTunnel?> start(VpnRequest request);

  /// Tears the tunnel down. The native side reports the matching
  /// [VpnStopped] event (reason [VpnStopReason.user]).
  Future<void> stop();

  /// Current native state; use this to reconcile after the engine restarted.
  Future<VpnStatus> status();

  /// Push events: tunnel ready (started outside Dart), stopped, error, tile tap.
  Stream<VpnEvent> get events;

  /// Pushes live throughput into the ongoing notification.
  ///
  /// [connected] keeps the rate fields visible on an idle-but-connected tunnel;
  /// pass false while connecting so the copy reads as idle.
  Future<void> updateNotification({
    required int rxBps,
    required int txBps,
    required bool connected,
  }) async {}

  /// Asks for the POST_NOTIFICATIONS runtime permission (Android 13+).
  Future<bool> requestNotificationPermission() async => true;

  /// Whether the ongoing notification is visible.
  Future<VpnNotificationStatus> notificationStatus() async =>
      const VpnNotificationStatus(granted: true, enabled: true);

  /// Opens this app's notification settings page.
  Future<void> openNotificationSettings() async {}

  /// Drains a quick-settings tile tap that happened while Dart was not
  /// listening (the tile persists it and opens the app).
  Future<VpnTileAction?> consumeTileAction() async => null;

  /// Releases channel/stream resources.
  Future<void> dispose() async {}
}

/// Android implementation over the app module's MethodChannel/EventChannel.
class MethodChannelVpnService extends VpnService {
  MethodChannelVpnService({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  }) : _method = methodChannel ?? const MethodChannel(methodChannelName),
       _eventChannel = eventChannel ?? const EventChannel(eventChannelName);

  static const String methodChannelName = 'com.kkrainbow.easytier/vpn';
  static const String eventChannelName = 'com.kkrainbow.easytier/vpn/events';

  final MethodChannel _method;
  final EventChannel _eventChannel;

  Stream<VpnEvent>? _events;
  StreamController<VpnEvent>? _controller;
  StreamSubscription<dynamic>? _subscription;

  @override
  Stream<VpnEvent> get events {
    final existing = _events;
    if (existing != null) return existing;

    final controller = StreamController<VpnEvent>.broadcast();
    _controller = controller;
    _subscription = _eventChannel.receiveBroadcastStream().listen(
      (dynamic raw) {
        final event = VpnEvent.fromMap(raw);
        if (event != null && !controller.isClosed) controller.add(event);
      },
      onError: (Object error) {
        if (!controller.isClosed) {
          controller.add(VpnError('VPN event channel error: $error'));
        }
      },
    );
    return _events = controller.stream;
  }

  @override
  Future<bool> prepare() async {
    try {
      return await _method.invokeMethod<bool>('prepare') ?? false;
    } on PlatformException catch (error) {
      throw VpnException(
        error.code,
        error.message ?? 'the VPN consent request failed',
      );
    } on MissingPluginException {
      throw const VpnException(
        'not_supported',
        'the Android VPN data plane is not available in this build',
      );
    }
  }

  @override
  Future<VpnTunnel?> start(VpnRequest request) async {
    try {
      final result = await _method.invokeMethod<Map<Object?, Object?>>(
        'start',
        request.toMap(),
      );
      return result == null ? null : VpnTunnel.fromMap(result);
    } on PlatformException catch (error) {
      // Consent missing: same `need_prepare` contract as the Tauri client.
      if (error.code == 'need_prepare') return null;
      throw VpnException(error.code, error.message ?? 'the VPN start failed');
    } on MissingPluginException {
      throw const VpnException(
        'not_supported',
        'the Android VPN data plane is not available in this build',
      );
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _method.invokeMethod<void>('stop');
    } on PlatformException catch (error) {
      throw VpnException(error.code, error.message ?? 'the VPN stop failed');
    } on MissingPluginException {
      throw const VpnException(
        'not_supported',
        'the Android VPN data plane is not available in this build',
      );
    }
  }

  @override
  Future<VpnStatus> status() async {
    try {
      final result = await _method.invokeMethod<Map<Object?, Object?>>(
        'status',
      );
      return result == null
          ? const VpnStatus(running: false)
          : VpnStatus.fromMap(result);
    } on PlatformException catch (error) {
      throw VpnException(error.code, error.message ?? 'the VPN status failed');
    } on MissingPluginException {
      return const VpnStatus(running: false);
    }
  }

  @override
  Future<void> updateNotification({
    required int rxBps,
    required int txBps,
    required bool connected,
  }) async {
    try {
      await _method.invokeMethod<void>('updateNotification', <String, Object?>{
        'rxBps': rxBps,
        'txBps': txBps,
        'connected': connected,
      });
    } on PlatformException {
      // Best effort: a notification update must never fail the tunnel.
    } on MissingPluginException {
      // Same.
    }
  }

  @override
  Future<bool> requestNotificationPermission() async {
    try {
      return await _method.invokeMethod<bool>('requestPermission') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<VpnNotificationStatus> notificationStatus() async {
    try {
      final result = await _method.invokeMethod<Map<Object?, Object?>>(
        'notificationStatus',
      );
      return result == null
          ? const VpnNotificationStatus(granted: true, enabled: true)
          : VpnNotificationStatus.fromMap(result);
    } on PlatformException {
      return const VpnNotificationStatus(granted: true, enabled: true);
    } on MissingPluginException {
      return const VpnNotificationStatus(granted: true, enabled: true);
    }
  }

  @override
  Future<void> openNotificationSettings() async {
    try {
      await _method.invokeMethod<void>('openNotificationSettings');
    } on PlatformException {
      // Nothing useful to do if the settings intent cannot be opened.
    } on MissingPluginException {
      // Same.
    }
  }

  @override
  Future<VpnTileAction?> consumeTileAction() async {
    try {
      final action = await _method.invokeMethod<String>('consumeTileAction');
      return VpnTileAction.fromWire(action);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<void> dispose() async {
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    final controller = _controller;
    _controller = null;
    _events = null;
    await controller?.close();
  }
}

/// No-op implementation for platforms without a VpnService (desktop): the core
/// owns its own TUN there, so screens should show tunnel UI as "unsupported".
class UnsupportedVpnService extends VpnService {
  const UnsupportedVpnService();

  @override
  Future<bool> prepare() async => false;

  @override
  Future<VpnTunnel?> start(VpnRequest request) async => null;

  @override
  Future<void> stop() async {}

  @override
  Future<VpnStatus> status() async => const VpnStatus(running: false);

  @override
  Stream<VpnEvent> get events => Stream<VpnEvent>.empty();
}

/// In-memory [VpnService] for tests and design previews.
///
/// It mirrors the native contract: [start] returns the tunnel (no [VpnStarted]
/// event, exactly like the MethodChannel path), [stop] emits
/// [VpnStopReason.user], and tests can simulate a revoke, a notification
/// disconnect, a tile start or a native error.
class FakeVpnService extends VpnService {
  FakeVpnService({this.consentGranted = true, int firstFd = 42})
    : _nextFd = firstFd;

  /// When false, [prepare] declines and [start] returns null.
  bool consentGranted;

  int _nextFd;

  int prepareCalls = 0;
  int startCalls = 0;
  int stopCalls = 0;
  int notificationUpdates = 0;

  VpnRequest? lastRequest;
  VpnTunnel? currentTunnel;
  final List<VpnEvent> emitted = <VpnEvent>[];

  final StreamController<VpnEvent> _events =
      StreamController<VpnEvent>.broadcast();

  @override
  Stream<VpnEvent> get events => _events.stream;

  @override
  Future<bool> prepare() async {
    prepareCalls++;
    return consentGranted;
  }

  @override
  Future<VpnTunnel?> start(VpnRequest request) async {
    startCalls++;
    if (!consentGranted) return null;
    lastRequest = request;
    final tunnel = VpnTunnel(
      fd: _nextFd++,
      ipv4Cidr: request.ipv4Cidr,
      ipv6Cidr: request.ipv6Cidr,
      routes: request.routes,
      dns: request.dns,
      mtu: request.mtu,
      session: request.session,
    );
    currentTunnel = tunnel;
    return tunnel;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    currentTunnel = null;
    emitStopped(VpnStopReason.user);
  }

  @override
  Future<VpnStatus> status() async => VpnStatus(
    running: currentTunnel != null,
    ipv4Cidr: currentTunnel?.ipv4Cidr,
    ipv6Cidr: currentTunnel?.ipv6Cidr,
    routes: currentTunnel?.routes ?? const <String>[],
    dns: currentTunnel?.dns ?? const <String>[],
    mtu: currentTunnel?.mtu ?? 0,
  );

  @override
  Future<void> updateNotification({
    required int rxBps,
    required int txBps,
    required bool connected,
  }) async {
    notificationUpdates++;
  }

  /// Simulates a tunnel started outside this Dart caller (quick-settings tile).
  void emitStartedFromRequest(VpnRequest request) {
    currentTunnel = VpnTunnel(
      fd: _nextFd++,
      ipv4Cidr: request.ipv4Cidr,
      ipv6Cidr: request.ipv6Cidr,
      routes: request.routes,
      dns: request.dns,
      mtu: request.mtu,
      session: request.session,
    );
    _emit(VpnStarted(currentTunnel!));
  }

  /// Simulates `onRevoke` (another VPN app took the slot), a notification
  /// "Disconnect" tap, or the service being destroyed.
  void emitStopped(VpnStopReason reason) {
    currentTunnel = null;
    _emit(VpnStopped(reason));
  }

  void emitError(String message) => _emit(VpnError(message));

  void emitTileAction(VpnTileAction action) =>
      _emit(VpnTileActionEvent(action));

  void _emit(VpnEvent event) {
    emitted.add(event);
    if (!_events.isClosed) _events.add(event);
  }

  @override
  Future<void> dispose() async {
    await _events.close();
  }
}

/// Picks the VPN implementation for the current platform.
///
/// Android is the only platform with a VpnService data plane today; everywhere
/// else the core creates its own TUN, so the seam is a no-op.
VpnService createPlatformVpnService() {
  if (kIsWeb) return const UnsupportedVpnService();
  if (defaultTargetPlatform == TargetPlatform.android) {
    return MethodChannelVpnService();
  }
  return const UnsupportedVpnService();
}

List<String> _stringList(Object? raw) {
  if (raw is! List) return const <String>[];
  return raw.whereType<String>().toList(growable: false);
}
