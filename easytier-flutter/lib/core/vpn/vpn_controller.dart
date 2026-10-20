import 'dart:async';

import 'vpn_service.dart';

/// The seam between the VPN data plane and the Rust bridge.
///
/// The FFI client is deliberately not imported here: whoever wires the app
/// supplies a tiny adapter so this package stays testable without Rust, e.g.
///
/// ```dart
/// controller.sink = CallbackTunFdSink((fd) => client.setTunFd(fd));
/// ```
abstract interface class TunFdSink {
  /// Hands a raw TUN fd to the core instance that should own the data plane.
  Future<void> setTunFd(int fd);
}

/// Function-object adapter for [TunFdSink].
class CallbackTunFdSink implements TunFdSink {
  const CallbackTunFdSink(this._onTunFd);

  final Future<void> Function(int fd) _onTunFd;

  @override
  Future<void> setTunFd(int fd) => _onTunFd(fd);
}

/// Turns the [VpnService] event stream into the two signals the core bridge
/// needs: "here is the TUN fd" and "the tunnel went away".
///
/// Responsibilities:
///  * run the consent -> start sequence and remember the live [tunnel];
///  * deliver the fd exactly once per tunnel (via [sink] or [tunFds]);
///  * clear the tunnel on every teardown and report the reason through
///    [onVpnStopped], so a system [VpnStopReason.revoked] can force the UI out
///    of "connected";
///  * forward quick-settings tile taps on [tileActions] (the controller cannot
///    build a [VpnRequest] by itself - the UI owns the network config).
///
/// Wiring (done by the app shell, not here):
///
/// ```dart
/// final vpn = VpnController(service: createPlatformVpnService());
/// vpn.sink = CallbackTunFdSink((fd) => client.setTunFd(fd));
/// vpn.onVpnStopped = (reason) async {
///   if (reason == VpnStopReason.revoked) await appState.forceDisconnect();
/// };
/// ```
class VpnController {
  VpnController({
    required this.service,
    this.sink,
    this.onVpnStopped,
  }) {
    _eventSubscription = service.events.listen(_onEvent);
  }

  final VpnService service;

  /// Invoked once per teardown, after [tunnel] has been cleared.
  ///
  /// [VpnStopReason.revoked] is the important one: another VPN app took the
  /// process-wide VPN slot, Android killed the TUN, and the Rust instance keeps
  /// running - without this callback the UI would keep showing "connected"
  /// while nothing carries traffic. A [VpnStopReason.superseded] teardown is
  /// caused by the controller/shell starting a replacement tunnel, so ignore it
  /// if your disconnect handler would otherwise stop the instance currently
  /// being connected.
  Future<void> Function(VpnStopReason reason)? onVpnStopped;

  late final StreamSubscription<VpnEvent> _eventSubscription;

  final StreamController<int> _tunFds = StreamController<int>.broadcast();
  final StreamController<VpnStopReason> _stops =
      StreamController<VpnStopReason>.broadcast();
  final StreamController<VpnTileAction> _tileActions =
      StreamController<VpnTileAction>.broadcast();

  /// The core-bridge adapter. Wire either this or [tunFds], not both: both
  /// deliver the same fd for the same tunnel.
  TunFdSink? sink;

  VpnTunnel? _tunnel;
  int? _lastDeliveredFd;
  VpnStopReason? _lastStopReason;
  String? _lastError;
  Future<VpnTunnel?>? _inFlightConnect;
  bool _disposed = false;

  /// The stream form of the fd handoff. Wire *either* this or [sink], not both:
  /// both deliver the same fd for the same tunnel.
  ///
  /// ```dart
  /// controller.tunFds.listen((fd) => client.setTunFd(fd));
  /// ```
  Stream<int> get tunFds => _tunFds.stream;

  /// Every teardown reason, in order (mirrors [onVpnStopped]).
  Stream<VpnStopReason> get stops => _stops.stream;

  /// Quick-settings tile taps: the UI should start/stop the tunnel in response.
  Stream<VpnTileAction> get tileActions => _tileActions.stream;

  /// The live tunnel, or null when the data plane is down.
  VpnTunnel? get tunnel => _tunnel;

  bool get isConnected => _tunnel != null;

  /// Raw fd of the live tunnel (debug/tests only; never close it from Dart).
  int? get tunFd => _tunnel?.fd;

  /// Reason of the most recent teardown; cleared when a new tunnel attaches.
  VpnStopReason? get lastStopReason => _lastStopReason;

  /// Last VPN error, human-readable for logs.
  String? get lastError => _lastError;

  /// Requests VPN consent (system dialog when needed).
  Future<bool> prepare() async {
    try {
      return await service.prepare();
    } on VpnException catch (error) {
      _lastError = error.toString();
      return false;
    }
  }

  /// Consent -> establish -> fd handoff.
  ///
  /// Returns null when consent was declined (or withdrawn); check [lastError].
  /// Concurrent calls are coalesced onto the in-flight attempt.
  Future<VpnTunnel?> connect(VpnRequest request) {
    final inFlight = _inFlightConnect;
    if (inFlight != null) return inFlight;
    final future = _connect(request);
    _inFlightConnect = future;
    return future.whenComplete(() {
      if (identical(_inFlightConnect, future)) _inFlightConnect = null;
    });
  }

  Future<VpnTunnel?> _connect(VpnRequest request) async {
    _lastError = null;
    final granted = await prepare();
    if (!granted) {
      _lastError = 'vpn_permission_denied';
      return null;
    }
    final VpnTunnel? tunnel;
    try {
      tunnel = await service.start(request);
    } on VpnException catch (error) {
      _lastError = error.toString();
      return null;
    }
    if (tunnel == null) {
      // Consent was revoked between prepare() and start().
      _lastError = 'vpn_consent_missing';
      return null;
    }
    await _adopt(tunnel);
    return tunnel;
  }

  /// Asks the native side to tear the tunnel down. The matching [VpnStopped]
  /// event clears [tunnel] and calls [onVpnStopped].
  Future<void> disconnect() async {
    try {
      await service.stop();
    } on VpnException catch (error) {
      _lastError = error.toString();
    }
  }

  /// Pushes live throughput into the ongoing notification.
  Future<void> updateNotification({
    required int rxBps,
    required int txBps,
    required bool connected,
  }) async {
    await service.updateNotification(
      rxBps: rxBps,
      txBps: txBps,
      connected: connected,
    );
  }

  /// Native VPN state, for reconciling after the Flutter engine restarted
  /// while the foreground service kept the tunnel alive.
  Future<VpnStatus> status() async {
    try {
      return await service.status();
    } on VpnException catch (error) {
      _lastError = error.toString();
      return const VpnStatus(running: false);
    }
  }

  /// Reconciles the in-memory tunnel with the native side.
  ///
  /// Call once on app attach: a foreground service outlives the activity, so
  /// the process may still own a live TUN while this controller (fresh engine)
  /// has no tunnel. The reverse also happens - the TUN was revoked while the
  /// engine was detached and the [VpnStopped] event was dropped - in which case
  /// this clears the stale tunnel and fires [onVpnStopped].
  Future<VpnStatus> refresh() async {
    final nativeStatus = await status();
    if (!nativeStatus.running && _tunnel != null) {
      await _handleStopped(VpnStopReason.destroy);
    }
    return nativeStatus;
  }

  /// Whether the ongoing notification can be seen (Android 13+ permission).
  Future<VpnNotificationStatus> notificationStatus() =>
      service.notificationStatus();

  /// Drains a tile tap that was persisted while Dart was not listening, and
  /// forwards it on [tileActions] like a live tap.
  Future<VpnTileAction?> consumeTileAction() async {
    final action = await service.consumeTileAction();
    if (action != null) _emitTileAction(action);
    return action;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _eventSubscription.cancel();
    await _tunFds.close();
    await _stops.close();
    await _tileActions.close();
    await service.dispose();
  }

  void _onEvent(VpnEvent event) {
    switch (event) {
      case VpnStarted(:final tunnel):
        // Started outside this caller (quick-settings tile): adopt the fd.
        unawaited(_adopt(tunnel));
      case VpnStopped(:final reason):
        unawaited(_handleStopped(reason));
      case VpnError(:final message):
        _lastError = message;
      case VpnTileActionEvent(:final action):
        _emitTileAction(action);
    }
  }

  Future<void> _adopt(VpnTunnel tunnel) async {
    _tunnel = tunnel;
    _lastStopReason = null;
    await _deliverFd(tunnel.fd);
  }

  /// Delivers the fd once per tunnel to the core bridge.
  Future<void> _deliverFd(int fd) async {
    if (fd == _lastDeliveredFd) return;
    _lastDeliveredFd = fd;

    final target = sink;
    if (target != null) {
      try {
        await target.setTunFd(fd);
      } catch (error) {
        // Keep the tunnel: the native fd is still valid, and the caller can
        // retry the core attach based on [lastError].
        _lastError = 'setTunFd($fd) failed: $error';
      }
    }

    if (!_disposed && !_tunFds.isClosed && _lastDeliveredFd == fd) {
      _tunFds.add(fd);
    }
  }

  Future<void> _handleStopped(VpnStopReason reason) async {
    _tunnel = null;
    _lastDeliveredFd = null;
    _lastStopReason = reason;
    if (!_disposed && !_stops.isClosed) _stops.add(reason);

    final callback = onVpnStopped;
    if (callback != null) {
      try {
        await callback(reason);
      } catch (error) {
        _lastError = 'onVpnStopped failed: $error';
      }
    }
  }

  void _emitTileAction(VpnTileAction action) {
    if (!_disposed && !_tileActions.isClosed) _tileActions.add(action);
  }
}
