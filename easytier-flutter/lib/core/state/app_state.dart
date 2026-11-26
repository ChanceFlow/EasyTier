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
    this.virtualIpPollInterval = const Duration(milliseconds: 250),
    this.staticVirtualIpTimeout = const Duration(seconds: 8),
    this.dhcpVirtualIpTimeout = const Duration(seconds: 25),
    VpnController? vpn,
  }) : vpnController = vpn {
    final controller = vpnController;
    if (controller != null) _wireVpn(controller);
  }

  final CoreClient client;

  /// Status polling cadence; `null` disables polling (widget tests / goldens).
  final Duration? pollInterval;

  /// Cadence while waiting for the core to report its virtual IP after start.
  final Duration virtualIpPollInterval;

  /// Maximum wait for static IP startup before failing Android VPN attach.
  final Duration staticVirtualIpTimeout;

  /// Maximum wait for DHCP lease assignment before failing Android VPN attach.
  final Duration dhcpVirtualIpTimeout;

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
  bool _reconcilingVpn = false;
  bool _disposed = false;
  int _connectGeneration = 0;
  String? _vpnInstanceId;
  String? _pendingVpnInstanceId;
  VpnRequest? _activeVpnRequest;
  Completer<void>? _virtualIpSignal;
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
    if (_disposed || id == null || _polling) return;
    _polling = true;
    try {
      final collected = await client.collectStatus(id);
      if (_disposed || activeId != id) return;
      status = collected;
      _notify();
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
        await _reconcileVpnIfNeeded(id);
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

  void _notify() {
    if (!_disposed) notifyListeners();
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
    final generation = ++_connectGeneration;
    final config = instance.config;
    busy = true;
    lastError = null;
    _log(
      LogLevel.info,
      'tunnel',
      'Connecting to ${config.networkName} (${config.instanceName})',
    );
    notifyListeners();
    String? startedId;
    try {
      final needsVpn = _needsAndroidVpn(config);
      if (needsVpn) {
        final granted = await vpnController!.prepare();
        if (!granted) {
          throw StateError(
            vpnController!.lastError ?? 'VPN permission was declined.',
          );
        }
        if (generation != _connectGeneration) return;
      }

      final previousVpnId = _vpnInstanceId;
      if (previousVpnId != null && previousVpnId != instance.id) {
        final vpn = vpnController;
        if (vpn != null && vpn.isConnected) {
          _selfStopping = true;
          try {
            await vpn.disconnect();
          } finally {
            _selfStopping = false;
          }
        }
        try {
          await client.stopInstance(previousVpnId);
        } catch (_) {}
        _vpnInstanceId = null;
        _activeVpnRequest = null;
      }

      startedId = await client.runInstance(config);
      if (generation != _connectGeneration) {
        try {
          await client.stopInstance(startedId);
        } catch (_) {}
        return;
      }
      activeId = startedId;
      await refresh();
      await _attachVpnIfNeeded(startedId, config, generation: generation);
      if (generation != _connectGeneration) return;
      await refresh();
      _log(LogLevel.info, 'tunnel', 'Connected · ${status.peers.length} peers');
    } catch (error) {
      final message = error.toString();
      lastError = message;
      _log(LogLevel.error, 'tunnel', 'Connect failed: $message');
      await _cleanupFailedConnect(startedId);
      if (generation == _connectGeneration) {
        status = InstanceStatus(
          instanceId: startedId ?? activeId ?? '',
          phase: ConnectionPhase.error,
          error: message,
        );
      }
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> disconnect() async {
    final id = activeId;
    if (id == null || busy) return;
    _connectGeneration++;
    _completeVirtualIpSignal();
    busy = true;
    lastError = null;
    _log(LogLevel.info, 'tunnel', 'Disconnecting');
    notifyListeners();
    try {
      final vpn = vpnController;
      if (vpn != null && vpn.isConnected) {
        _selfStopping = true;
        try {
          await vpn.disconnect();
        } finally {
          _selfStopping = false;
        }
      }
      _vpnInstanceId = null;
      _pendingVpnInstanceId = null;
      _activeVpnRequest = null;
      await client.stopInstance(id);
      await refresh();
      _log(LogLevel.info, 'tunnel', 'Disconnected');
    } catch (error) {
      lastError = error.toString();
      _log(LogLevel.error, 'tunnel', 'Disconnect failed: $error');
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> selectInstance(String id) async {
    if (activeId == id) return;
    _connectGeneration++;
    _completeVirtualIpSignal();
    activeId = id;
    lastError = null;
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
      _notify();
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

  bool _needsAndroidVpn(NetworkConfig config) {
    final controller = vpnController;
    if (controller == null || controller.service is UnsupportedVpnService) {
      return false;
    }
    if (client is! TunFdCapable) return false;
    return !config.noTun;
  }

  void _wireVpn(VpnController controller) {
    controller.sink = CallbackTunFdSink((fd) async {
      final id = _pendingVpnInstanceId ?? _vpnInstanceId ?? activeId;
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

  /// Starts the Android tunnel after the core instance is up. Static configs
  /// report a virtual IP as soon as the core is ready; DHCP configs wait for a
  /// peer lease before the Android TUN can be established.
  Future<void> _attachVpnIfNeeded(
    String instanceId,
    NetworkConfig config, {
    required int generation,
  }) async {
    final controller = vpnController;
    if (controller == null || !_needsAndroidVpn(config)) return;

    final readyStatus = await _waitForVirtualIp(
      instanceId: instanceId,
      config: config,
      generation: generation,
    );
    if (generation != _connectGeneration) return;
    if (readyStatus == null) {
      throw StateError(
        status.error ??
            (config.dhcp
                ? 'Timed out waiting for a DHCP virtual IP from peers.'
                : 'The core did not report a virtual IP; cannot start the Android tunnel.'),
      );
    }

    final request = buildVpnRequest(config, readyStatus);
    _pendingVpnInstanceId = instanceId;
    try {
      final tunnel = await controller.connect(request);
      if (tunnel == null) {
        throw StateError(controller.lastError ?? 'VPN start was declined.');
      }
      if (controller.lastError != null) {
        throw StateError(controller.lastError!);
      }
      _vpnInstanceId = instanceId;
      _activeVpnRequest = request;
    } finally {
      if (_pendingVpnInstanceId == instanceId) {
        _pendingVpnInstanceId = null;
      }
    }
  }

  Future<InstanceStatus?> _waitForVirtualIp({
    required String instanceId,
    required NetworkConfig config,
    required int generation,
  }) async {
    final timeout = config.dhcp
        ? dhcpVirtualIpTimeout
        : staticVirtualIpTimeout;
    final deadline = DateTime.now().add(timeout);
    final startupGraceDeadline = DateTime.now().add(const Duration(seconds: 3));

    while (true) {
      if (generation != _connectGeneration || activeId != instanceId) {
        return null;
      }
      final current = status;
      final ip = current.virtualIp;
      if (ip != null && ip.isNotEmpty) {
        return current;
      }
      if (current.error != null && current.error!.isNotEmpty) {
        return null;
      }
      if (current.phase == ConnectionPhase.error) {
        return null;
      }
      final now = DateTime.now();
      if (current.phase == ConnectionPhase.stopped &&
          now.isAfter(startupGraceDeadline)) {
        return null;
      }
      if (!now.isBefore(deadline)) {
        return null;
      }

      final signal = _virtualIpSignal ??= Completer<void>();
      final remaining = deadline.difference(now);
      final wait = remaining < virtualIpPollInterval
          ? remaining
          : virtualIpPollInterval;
      await Future.any<void>(<Future<void>>[
        Future<void>.delayed(wait),
        signal.future,
      ]);
      if (generation != _connectGeneration || activeId != instanceId) {
        return null;
      }
      await refresh();
    }
  }

  Future<void> _cleanupFailedConnect(String? startedId) async {
    final controller = vpnController;
    if (controller != null && controller.isConnected) {
      _selfStopping = true;
      try {
        await controller.disconnect();
      } catch (_) {
      } finally {
        _selfStopping = false;
      }
    }
    _vpnInstanceId = null;
    _pendingVpnInstanceId = null;
    _activeVpnRequest = null;
    if (startedId != null) {
      try {
        await client.stopInstance(startedId);
      } catch (_) {}
    }
  }

  Future<void> _reconcileVpnIfNeeded(String instanceId) async {
    final controller = vpnController;
    final config = activeConfig;
    if (controller == null ||
        config == null ||
        config.noTun ||
        busy ||
        _reconcilingVpn ||
        !controller.isConnected ||
        _vpnInstanceId != instanceId ||
        status.virtualIp == null ||
        status.virtualIp!.isEmpty) {
      return;
    }

    final desired = buildVpnRequest(config, status);
    final current = _activeVpnRequest;
    if (current != null && _vpnRequestEquals(current, desired)) {
      return;
    }

    _reconcilingVpn = true;
    _pendingVpnInstanceId = instanceId;
    try {
      final tunnel = await controller.connect(desired);
      if (tunnel != null && controller.lastError == null) {
        _activeVpnRequest = desired;
      }
    } catch (error) {
      _log(LogLevel.warn, 'tunnel', 'Failed to update VPN routes: $error');
    } finally {
      if (_pendingVpnInstanceId == instanceId) {
        _pendingVpnInstanceId = null;
      }
      _reconcilingVpn = false;
    }
  }

  static VpnRequest buildVpnRequest(
    NetworkConfig config,
    InstanceStatus status,
  ) {
    final rawIp = status.virtualIp?.trim() ?? '';
    final slash = rawIp.indexOf('/');
    final ip = slash < 0 ? rawIp : rawIp.substring(0, slash).trim();
    final embeddedPrefix = slash < 0
        ? null
        : int.tryParse(rawIp.substring(slash + 1).trim());
    final prefix =
        embeddedPrefix ??
        status.virtualIpPrefixLength ??
        (config.dhcp ? 24 : config.networkLength);
    final ipv4Cidr = '$ip/$prefix';

    final routes = <String>{};
    if (prefix > 0 && prefix < 32) {
      final subnet = _maskedIpv4Cidr(ip, prefix);
      if (subnet != null) routes.add(subnet);
    }
    for (final cidr in status.remoteProxyCidrs) {
      final normalized = _normalizeIpv4Cidr(cidr);
      if (normalized != null) routes.add(normalized);
    }
    if (config.enableMagicDns) {
      routes.add('100.100.100.101/32');
    }
    final sortedRoutes = routes.toList()..sort();

    return VpnRequest(
      ipv4Cidr: ipv4Cidr,
      ipv6Cidr: config.disableIpv6 ? null : 'fd00::1/128',
      routes: sortedRoutes,
      dns: config.enableMagicDns
          ? const <String>['100.100.100.101']
          : const <String>[],
      mtu: config.mtu ?? 1300,
      session: config.networkName,
    );
  }

  static bool _vpnRequestEquals(VpnRequest a, VpnRequest b) {
    if (a.ipv4Cidr != b.ipv4Cidr ||
        a.ipv6Cidr != b.ipv6Cidr ||
        a.mtu != b.mtu ||
        a.session != b.session ||
        a.routes.length != b.routes.length ||
        a.dns.length != b.dns.length) {
      return false;
    }
    for (var i = 0; i < a.routes.length; i++) {
      if (a.routes[i] != b.routes[i]) return false;
    }
    for (var i = 0; i < a.dns.length; i++) {
      if (a.dns[i] != b.dns[i]) return false;
    }
    return true;
  }

  static String? _maskedIpv4Cidr(String ip, int prefix) =>
      _normalizeIpv4Cidr('$ip/$prefix');

  static String? _normalizeIpv4Cidr(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed.contains(':')) return null;
    final slash = trimmed.indexOf('/');
    final address = (slash < 0 ? trimmed : trimmed.substring(0, slash)).trim();
    final prefix = slash < 0
        ? 32
        : int.tryParse(trimmed.substring(slash + 1).trim());
    if (prefix == null || prefix < 0 || prefix > 32) return null;
    final parts = address.split('.');
    if (parts.length != 4) return null;
    var ipInt = 0;
    for (final part in parts) {
      final octet = int.tryParse(part);
      if (octet == null || octet < 0 || octet > 255) return null;
      ipInt = (ipInt << 8) | octet;
    }
    final mask = prefix == 0 ? 0 : (0xffffffff << (32 - prefix)) & 0xffffffff;
    final network = ipInt & mask;
    final maskedIp =
        '${(network >> 24) & 0xff}.${(network >> 16) & 0xff}.'
        '${(network >> 8) & 0xff}.${network & 0xff}';
    return '$maskedIp/$prefix';
  }

  void _completeVirtualIpSignal() {
    final signal = _virtualIpSignal;
    _virtualIpSignal = null;
    if (signal != null && !signal.isCompleted) {
      signal.complete();
    }
  }

  Future<void> _onVpnStopped(VpnStopReason reason) async {
    if (_selfStopping || reason == VpnStopReason.superseded) return;
    final id = _vpnInstanceId ?? activeId;
    _vpnInstanceId = null;
    _pendingVpnInstanceId = null;
    _activeVpnRequest = null;
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
    if (activeId == id || id == null) {
      status = InstanceStatus(
        instanceId: id ?? status.instanceId,
        phase: ConnectionPhase.stopped,
        error: lastError,
      );
    }
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
    if (event.kind == EventKind.connected) {
      _completeVirtualIpSignal();
    }
    if (destination != EtDestination.activity) _unseenEvents++;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _connectGeneration++;
    _completeVirtualIpSignal();
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
