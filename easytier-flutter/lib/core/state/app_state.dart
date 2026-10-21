import 'dart:async';

import 'package:flutter/material.dart';

import '../client/core_client.dart';
import '../i18n/i18n.dart';
import 'log_bus.dart';
import '../models/models.dart';
import '../ui/et_shell.dart';
import '../vpn/vpn_controller.dart';
import '../vpn/vpn_service.dart';

/// App-wide state. One notifier owns the selected instance, the live status and
/// the event feed; screens read it through [AppScope] and call its methods.
///
/// Built on `ChangeNotifier` (Flutter SDK only): the app has exactly one global
/// store, and a state-management dependency would not pay for itself.
///
/// When a [VpnController] is supplied (Android), connect() orchestrates the two
/// halves of a tunnel in the only order that works:
///   core instance starts → address known → `VpnService.establish()` → fd is
///   borrowed by the core.
/// Losing the system VPN slot (`onRevoke`) tears down the core instance too, so
/// the UI can never keep claiming "connected" while nothing carries traffic.
class AppState extends ChangeNotifier {
  AppState({
    required this.client,
    this.pollInterval = const Duration(seconds: 1),
    VpnController? vpn,
  }) : vpnController = vpn {
    final controller = vpnController;
    if (controller != null) _wireVpn(controller);
  }

  final CoreClient client;

  /// Status polling cadence; `null` disables polling (widget tests / goldens).
  final Duration? pollInterval;

  /// Android data plane, or `null` on platforms without a VpnService.
  final VpnController? vpnController;

  final List<NetworkEvent> events = [];

  List<NetworkInstance> instances = const [];
  String? activeId;
  InstanceStatus status = InstanceStatus.stopped;
  EtDestination destination = EtDestination.home;
  ThemeMode themeMode = ThemeMode.system;
  Locale locale = const Locale('en');
  String configServerUrl = '';
  String logLevel = 'info';

  bool initialized = false;
  bool busy = false;
  String? lastError;
  int _unseenEvents = 0;

  /// Client-side lifecycle log shown in Settings → Client logs.
  final LogBus logs = LogBus();
  bool _polling = false;
  bool _selfStopping = false;
  Timer? _pollTimer;
  StreamSubscription<NetworkEvent>? _eventSub;
  StreamSubscription<VpnTileAction>? _vpnTileSub;

  NetworkInstance? get active {
    for (final instance in instances) {
      if (instance.id == activeId) return instance;
    }
    return null;
  }

  NetworkConfig? get activeConfig => active?.config;

  bool get connected => status.phase.isUp;

  /// Events arrived since the Activity tab was last visited; drives the shell
  /// badge and is cleared when the user opens Activity (commercial behaviour).
  int get unseenEvents => _unseenEvents;

  Future<void> bootstrap() async {
    _log(LogLevel.info, 'app', 'Client starting');
    await client.init();
    _eventSub = client.events.listen(_onEvent);
    instances = await client.listInstances();
    if (instances.isNotEmpty) {
      activeId ??= instances.first.id;
      await refresh();
    }
    initialized = true;
    _log(
      LogLevel.info,
      'app',
      'Ready · ${instances.length} network${instances.length == 1 ? '' : 's'} configured',
    );
    notifyListeners();
    final interval = pollInterval;
    if (interval != null) {
      _pollTimer ??= Timer.periodic(interval, (_) => refresh());
    }
  }

  Future<void> refresh() async {
    final id = activeId;
    if (id == null || _polling) return;
    _polling = true;
    try {
      status = await client.collectStatus(id);
      notifyListeners();
      final vpn = vpnController;
      if (vpn != null && status.phase.isUp) {
        // Fire-and-forget: a notification hiccup must never break status refresh.
        unawaited(
          vpn.updateNotification(
            rxBps: status.rxBps,
            txBps: status.txBps,
            connected: true,
          ),
        );
      }
    } catch (error) {
      lastError = error.toString();
      if (lastError != _lastRefreshError) {
        _lastRefreshError = lastError;
        _log(LogLevel.warn, 'status', 'Status refresh failed: $error');
      }
    } finally {
      _polling = false;
    }
  }

  String? _lastRefreshError;

  /// Writes a client log line, gated by the Settings → Log level preference.
  void _log(LogLevel level, String source, String message) {
    final enabled = switch (logLevel) {
      'off' => false,
      'error' => level.index >= LogLevel.error.index,
      'warn' => level.index >= LogLevel.warn.index,
      'info' => level.index >= LogLevel.info.index,
      _ => true, // debug, trace
    };
    if (!enabled) return;
    logs.add(level, source, message);
  }

  Future<void> toggleConnection() async {
    if (busy) return;
    if (status.phase.isUp) return disconnect();
    return connect();
  }

  Future<void> connect() async {
    final instance = active;
    if (instance == null || busy) return;
    busy = true;
    lastError = null;
    _log(
      LogLevel.info,
      'tunnel',
      'Connecting to ${instance.config.networkName} (${instance.config.instanceName})',
    );
    notifyListeners();
    try {
      activeId = await client.runInstance(instance.config);
      await refresh();
      await _attachVpnIfNeeded(instance.config);
      await refresh();
      _log(LogLevel.info, 'tunnel', 'Connected · ${status.peers.length} peers');
    } catch (error) {
      lastError = error.toString();
      _log(LogLevel.error, 'tunnel', 'Connect failed: $error');
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    final id = activeId;
    if (id == null || busy) return;
    busy = true;
    lastError = null;
    _log(LogLevel.info, 'tunnel', 'Disconnecting');
    notifyListeners();
    try {
      final vpn = vpnController;
      if (vpn != null && vpn.isConnected) {
        _selfStopping = true;
        await vpn.disconnect();
        _selfStopping = false;
      }
      await client.stopInstance(id);
      await refresh();
      _log(LogLevel.info, 'tunnel', 'Disconnected');
    } catch (error) {
      lastError = error.toString();
      _log(LogLevel.error, 'tunnel', 'Disconnect failed: $error');
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> selectInstance(String id) async {
    if (activeId == id) return;
    activeId = id;
    status = InstanceStatus.stopped;
    _log(LogLevel.debug, 'profiles', 'Switched active profile to $id');
    notifyListeners();
    await refresh();
  }

  Future<String?> validateConfig(NetworkConfig config) => client.validateConfig(config);

  Future<bool> saveConfig(NetworkConfig config) async {
    busy = true;
    lastError = null;
    notifyListeners();
    try {
      await client.saveConfig(config);
      // Match by name first; a rename lands on the active record instead of
      // silently creating a second network.
      var index = instances.indexWhere((i) => i.config.instanceName == config.instanceName);
      if (index < 0 && activeId != null) {
        index = instances.indexWhere((i) => i.id == activeId);
      }
      if (index >= 0) {
        final updated = List<NetworkInstance>.of(instances);
        updated[index] = updated[index].copyWith(config: config);
        instances = updated;
      }
      _log(
        LogLevel.info,
        'config',
        'Saved "${config.networkName}" · ${config.instanceName}',
      );
      return true;
    } catch (error) {
      lastError = error.toString();
      _log(LogLevel.error, 'config', 'Save failed: $error');
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> addInstance() async {
    final index = instances.length + 1;
    final config = NetworkConfig(
      instanceName: 'net-$index',
      hostname: 'device-$index',
      networkName: 'EasyTier Net $index',
    );
    await client.saveConfig(config);
    instances = await client.listInstances();
    final created = instances.where((i) => i.config.instanceName == config.instanceName);
    activeId = created.isEmpty ? activeId : created.first.id;
    _log(LogLevel.info, 'config', 'Created network "${config.networkName}"');
    notifyListeners();
    await refresh();
  }

  Future<void> removeInstance(String id) async {
    _log(LogLevel.info, 'config', 'Deleting network $id');
    await client.deleteInstance(id);
    instances = await client.listInstances();
    if (activeId == id) {
      activeId = instances.isEmpty ? null : instances.first.id;
    }
    status = InstanceStatus.stopped;
    notifyListeners();
    await refresh();
  }

  void setDestination(EtDestination value) {
    if (destination == value) return;
    destination = value;
    if (value == EtDestination.activity && _unseenEvents != 0) {
      _unseenEvents = 0;
    }
    _log(LogLevel.debug, 'ui', 'Destination → ${value.name}');
    notifyListeners();
  }

  void setThemeMode(ThemeMode mode) {
    themeMode = mode;
    _log(LogLevel.debug, 'ui', 'Theme → ${mode.name}');
    notifyListeners();
  }

  void toggleTheme() {
    setThemeMode(themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
  }

  void setLocale(Locale value) {
    locale = value;
    I18n.locale = value;
    notifyListeners();
  }

  void toggleLocale() {
    setLocale(locale.languageCode == 'zh' ? const Locale('en') : const Locale('zh'));
  }

  void setConfigServerUrl(String url) {
    configServerUrl = url.trim();
    notifyListeners();
  }

  void setLogLevel(String level) {
    logLevel = level;
    notifyListeners();
  }

  void clearError() {
    lastError = null;
    notifyListeners();
  }

  // ---- VPN data plane ------------------------------------------------------

  void _wireVpn(VpnController controller) {
    controller.sink = CallbackTunFdSink((fd) async {
      final id = activeId;
      if (id == null) return;
      final transport = client;
      if (transport is TunFdCapable) {
        await (transport as TunFdCapable).setTunFd(id, fd);
      }
    });
    controller.onVpnStopped = _onVpnStopped;
    _vpnTileSub = controller.tileActions.listen((action) {
      if (action == VpnTileAction.start) {
        unawaited(connect());
      } else {
        unawaited(disconnect());
      }
    });
    // Drain a quick-settings tap made while the app was not running.
    unawaited(controller.consumeTileAction());
  }

  /// Starts the Android tunnel after the core instance is up. The virtual IP is
  /// usually a DHCP lease, so wait briefly for the core to report it.
  Future<void> _attachVpnIfNeeded(NetworkConfig config) async {
    final controller = vpnController;
    if (controller == null || controller.service is UnsupportedVpnService) return;
    // Without an FFI transport there is no core to borrow the fd.
    if (client is! TunFdCapable) return;

    final ip = await _waitForVirtualIp();
    if (ip == null) {
      throw StateError(
        'The core did not report a virtual IP; cannot start the Android tunnel.',
      );
    }
    final tunnel = await controller.connect(
      VpnRequest(
        ipv4Cidr: ip,
        routes: <String>[
          ...config.proxyCidrs,
          if (config.enableExitNode) '0.0.0.0/0',
        ],
        mtu: config.mtu ?? 1300,
        session: config.networkName,
      ),
    );
    if (tunnel == null) {
      throw StateError(controller.lastError ?? 'VPN start was declined.');
    }
  }

  Future<String?> _waitForVirtualIp() async {
    for (var attempt = 0; attempt < 10; attempt++) {
      final ip = status.virtualIp;
      if (ip != null && ip.isNotEmpty) return ip;
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await refresh();
    }
    final ip = status.virtualIp;
    return ip == null || ip.isEmpty ? null : ip;
  }

  Future<void> _onVpnStopped(VpnStopReason reason) async {
    if (_selfStopping || reason == VpnStopReason.superseded) return;
    final id = activeId;
    if (reason == VpnStopReason.revoked) {
      lastError = 'The system VPN slot was taken by another app.';
    }
    if (id != null) {
      try {
        await client.stopInstance(id);
      } catch (_) {
        // The instance may already be gone; the UI must still leave "connected".
      }
    }
    status = InstanceStatus(
      instanceId: id ?? status.instanceId,
      phase: ConnectionPhase.stopped,
      error: lastError,
    );
    events.insert(
      0,
      NetworkEvent(
        at: DateTime.now(),
        kind: reason == VpnStopReason.revoked ? EventKind.warning : EventKind.disconnected,
        title: switch (reason) {
          VpnStopReason.user => 'Tunnel stopped',
          VpnStopReason.revoked => 'Tunnel revoked by the system',
          VpnStopReason.destroy => 'Tunnel service destroyed',
          VpnStopReason.superseded => 'Tunnel replaced',
          VpnStopReason.error => 'Tunnel failed',
        },
      ),
    );
    notifyListeners();
  }

  void _onEvent(NetworkEvent event) {
    events.insert(0, event);
    if (events.length > 200) events.removeLast();
    _log(
      event.kind == EventKind.error || event.kind == EventKind.warning
          ? LogLevel.warn
          : LogLevel.info,
      'event',
      '${event.title}${event.detail == null ? '' : ' · ${event.detail}'}',
    );
    if (destination != EtDestination.activity) _unseenEvents++;
    notifyListeners();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _eventSub?.cancel();
    _vpnTileSub?.cancel();
    vpnController?.dispose();
    client.dispose();
    super.dispose();
  }
}

/// Provides [AppState] to the widget tree and rebuilds dependents on change.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing above this widget.');
    return scope!.notifier!;
  }

  /// Read without subscribing to rebuilds (use inside callbacks).
  static AppState read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing above this widget.');
    return scope!.notifier!;
  }
}
