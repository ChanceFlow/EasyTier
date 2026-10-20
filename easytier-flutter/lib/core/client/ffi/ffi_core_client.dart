import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import '../../models/models.dart';
import '../core_client.dart';
import 'ffi_bindings.dart';
import 'native_library.dart';

/// Transport errors reported by [FfiCoreClient].
class CoreClientException implements Exception {
  CoreClientException(this.message);

  final String message;

  @override
  String toString() => 'CoreClientException: $message';
}

/// [CoreClient] backed by the `easytier-ffi` C ABI through `dart:ffi`.
///
/// Ported from the Tauri client, which linked the Rust crate directly. The
/// native library is located by [EasytierFfi.load]; configuration persistence is
/// implemented here because `easytier-ffi` intentionally has no config-file
/// storage host (its process management is created with a "static config"
/// control).
///
/// The instance id exposed to the UI is the instance UUID embedded in the
/// generated TOML (`instance_id`), so it survives restarts and matches
/// `list_instance` ids exactly.
class FfiCoreClient implements CoreClient, TunFdCapable {
  FfiCoreClient({
    EasytierFfi? native,
    String? configDirectory,
    this.startTimeout = const Duration(seconds: 30),
  }) : _providedNative = native,
       _configDirectoryOverride = configDirectory;

  /// Maximum time to wait for `run_network_instance` on the worker isolate.
  final Duration startTimeout;

  final EasytierFfi? _providedNative;
  final String? _configDirectoryOverride;

  late final EasytierFfiBindings _bindings;
  String? _libraryPath;

  NativeCallable<InstanceEventNative>? _eventCallable;
  final StreamController<NetworkEvent> _events =
      StreamController<NetworkEvent>.broadcast();

  /// Persisted configs keyed by instance UUID.
  final Map<String, NetworkConfig> _configs = <String, NetworkConfig>{};

  File? _storeFile;
  bool _storeUsable = false;
  bool _initialized = false;
  bool _disposed = false;
  String? _version;

  /// Instance name -> instance id, refreshed by every native list call.
  Map<String, String> _runningByName = const <String, String>{};

  final Map<String, String> _virtualIps = <String, String>{};
  final Map<String, ConnectionPhase> _lastPhase =
      <String, ConnectionPhase>{};
  final Map<String, DateTime> _connectedAt = <String, DateTime>{};
  final Map<String, List<TrafficSample>> _history =
      <String, List<TrafficSample>>{};
  final Map<String, _TrafficState> _traffic = <String, _TrafficState>{};

  @override
  Future<void> init() async {
    if (_initialized) return;

    final native = _providedNative ?? EasytierFfi.load();
    _bindings = native.bindings;
    _libraryPath = native.path;

    await _loadStore();

    final callable = NativeCallable<InstanceEventNative>.listener(
      _handleNativeEvent,
    );
    final status = _bindings.setInstanceEventCallback(
      callable.nativeFunction,
      nullptr,
    );
    if (status != 0) {
      final error = _bindings.takeLastError();
      // Closing here is safe: the native side never received a valid pointer
      // because the registration was rejected.
      callable.close();
      throw CoreClientException(
        'set_instance_event_callback failed: ${error ?? 'unknown error'}',
      );
    }
    _eventCallable = callable;
    _initialized = true;

    _emit(
      kind: EventKind.info,
      title: 'EasyTier core ready',
      detail: 'Version ${await version()}',
    );
  }

  @override
  Future<List<NetworkInstance>> listInstances() async {
    _ensureInitialized();
    final running = _listRunning();
    final instances = <NetworkInstance>[];
    final persistedNames = <String>{};

    for (final entry in _configs.entries) {
      final config = entry.value;
      persistedNames.add(config.instanceName);
      instances.add(
        NetworkInstance(
          id: entry.key,
          config: config,
          enabled: running.containsKey(config.instanceName),
        ),
      );
    }

    // Instances started by another host process (or before this client
    // persisted anything) are surfaced read-only with a synthetic config.
    for (final entry in running.entries) {
      if (persistedNames.contains(entry.key)) continue;
      instances.add(
        NetworkInstance(
          id: entry.value,
          config: NetworkConfig(
            instanceName: entry.key,
            hostname: entry.key,
            networkName: '',
          ),
          enabled: true,
          source: 'legacy',
        ),
      );
    }
    return instances;
  }

  @override
  Future<String> runInstance(NetworkConfig config) async {
    _ensureInitialized();
    final id = await _upsertConfig(config, strictStorage: false);

    final running = _listRunning();
    final existingId = running[config.instanceName];
    if (existingId != null) {
      return existingId;
    }

    final toml = _tomlFor(config, id);
    final result = await _runInWorker('run_network_instance', toml).timeout(
      startTimeout,
      onTimeout: () => throw CoreClientException(
        'run_network_instance timed out after ${startTimeout.inSeconds}s for '
        '"${config.instanceName}".',
      ),
    );
    if (result.status != 0) {
      // Another host started the same instance between our check and the call.
      if (result.error != null &&
          result.error!.toLowerCase().contains('already exists')) {
        return _listRunning()[config.instanceName] ?? id;
      }
      throw CoreClientException(
        'run_network_instance failed: ${result.error ?? 'unknown error'}',
      );
    }

    _virtualIps.remove(id);
    _connectedAt.remove(id);
    _traffic.remove(id);
    _history.remove(id);
    _emit(
      kind: EventKind.info,
      title: 'Connecting to ${config.networkName}',
      detail: config.instanceName,
    );
    return id;
  }

  @override
  Future<void> stopInstance(String id) async {
    _ensureInitialized();
    final config = _configs[id];
    final name = config?.instanceName;
    var wasUp = false;

    if (name != null && _listRunning().containsKey(name)) {
      wasUp = _connectedAt.containsKey(id);
      await _deleteInWorker(<String>[name]);
    }

    _dropTracking(id);
    if (wasUp) {
      _emit(
        kind: EventKind.disconnected,
        title: 'Disconnected',
        detail: config?.networkName,
      );
    }
  }

  @override
  Future<void> deleteInstance(String id) async {
    _ensureInitialized();
    final config = _configs[id];
    await stopInstance(id);
    if (_configs.remove(id) != null) {
      await _saveStore();
      _emit(
        kind: EventKind.info,
        title: 'Network removed',
        detail: config?.networkName ?? config?.instanceName,
      );
    }
  }

  @override
  Future<void> saveConfig(NetworkConfig config) async {
    _ensureInitialized();
    await _upsertConfig(config);
  }

  @override
  Future<NetworkConfig?> getConfig(String id) async {
    _ensureInitialized();
    return _configs[id];
  }

  @override
  Future<String?> validateConfig(NetworkConfig config) async {
    _ensureInitialized();
    final localError = _validateLocally(config);
    if (localError != null) return localError;

    final existingId = _idForInstanceName(config.instanceName);
    final pointer = _bindings.allocateCString(
      _tomlFor(config, existingId ?? _newUuid()),
    );
    try {
      final status = _bindings.parseConfig(pointer);
      if (status == 0) return null;
      return _bindings.takeLastError() ?? 'invalid configuration';
    } finally {
      _bindings.freeCString(pointer);
    }
  }

  @override
  Future<InstanceStatus> collectStatus(String id) async {
    _ensureInitialized();
    final config = _configs[id];
    final running = _listRunning();
    final name = config?.instanceName ?? _runningByName[id];
    if (name == null) {
      _dropTracking(id);
      return InstanceStatus(instanceId: id, phase: ConnectionPhase.stopped);
    }
    if (!running.containsKey(name)) {
      final lastError = _traffic[id]?.lastError;
      _dropTracking(id);
      return InstanceStatus(
        instanceId: id,
        phase: ConnectionPhase.stopped,
        error: lastError,
      );
    }

    final info = _collectInfos()[name];
    if (info == null) {
      // Running but the snapshot is not available yet: still starting up.
      return InstanceStatus(
        instanceId: id,
        phase: ConnectionPhase.connecting,
        virtualIp: _virtualIps[id],
      );
    }

    return _statusFromInfo(id, config, info);
  }

  @override
  Future<String> version() async {
    _ensureInitialized();
    final cached = _version;
    if (cached != null) return cached;
    final version = _bindings.readVersion();
    _version = version;
    return version;
  }

  @override
  Stream<NetworkEvent> get events => _events.stream;

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final callable = _eventCallable;
    _eventCallable = null;
    if (callable != null) {
      try {
        _bindings.clearInstanceEventCallback();
      } on Object {
        // The library may already be unloaded during process shutdown.
      }
      // Do not close the NativeCallable synchronously: the native side may
      // have an event in flight that is already posted to this isolate, and
      // invoking a closed callable is undefined behaviour. A short grace
      // period lets queued events drain first.
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 250), callable.close),
      );
    }
    await _events.close();
  }

  /// Attaches an Android `VpnService` file descriptor to a running instance.
  ///
  /// This is deliberately not part of [CoreClient]: only the Android host knows
  /// when `VpnService.establish()` has produced a descriptor. Call it right
  /// after the service returns one and before the first packet is expected.
  @override
  Future<void> setTunFd(String instanceId, int fd) async {
    _ensureInitialized();
    final name = _configs[instanceId]?.instanceName ?? _runningByName[instanceId];
    if (name == null) {
      throw CoreClientException('Unknown instance "$instanceId".');
    }
    final pointer = _bindings.allocateCString(name);
    try {
      if (_bindings.setTunFd(pointer, fd) != 0) {
        throw CoreClientException(
          'set_tun_fd failed: ${_bindings.takeLastError() ?? 'unknown error'}',
        );
      }
    } finally {
      _bindings.freeCString(pointer);
    }
  }

  /// Escape hatch for RPC services that are not covered by [CoreClient]
  /// (for example the logger service). Blocks while the core handles the call,
  /// so use it sparingly from the UI isolate.
  Future<Map<String, dynamic>> callJsonRpc({
    required String service,
    required String method,
    required Map<String, dynamic> payload,
    String? domain,
  }) async {
    _ensureInitialized();
    final servicePtr = _bindings.allocateCString(service);
    final methodPtr = _bindings.allocateCString(method);
    final domainPtr = domain == null
        ? nullptr
        : _bindings.allocateCString(domain);
    final payloadPtr = _bindings.allocateCString(jsonEncode(payload));
    final outSlot = _bindings.allocatePointerSlot();
    try {
      final status = _bindings.callJsonRpc(
        servicePtr,
        methodPtr,
        domainPtr,
        payloadPtr,
        outSlot,
      );
      if (status != 0) {
        throw CoreClientException(
          'call_json_rpc failed: ${_bindings.takeLastError() ?? 'unknown error'}',
        );
      }
      final response = outSlot.value;
      if (response == nullptr) return const <String, dynamic>{};
      final text = _bindings.copyCString(response);
      _bindings.freeString(response);
      final decoded = jsonDecode(text);
      return decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{'value': decoded};
    } finally {
      _bindings.freeCString(servicePtr);
      _bindings.freeCString(methodPtr);
      if (domainPtr != nullptr) _bindings.freeCString(domainPtr);
      _bindings.freeCString(payloadPtr);
      _bindings.freeNative(outSlot);
    }
  }

  // ===== Native snapshots =====

  Map<String, String> _listRunning() {
    const initialCapacity = 64;
    var capacity = initialCapacity;
    while (true) {
      final buffer = _bindings.allocateKeyValuePairs(capacity);
      try {
        final count = _bindings.listInstance(buffer, capacity);
        if (count < 0) {
          throw CoreClientException(
            'list_instance failed: '
            '${_bindings.takeLastError() ?? 'unknown error'}',
          );
        }
        final running = <String, String>{};
        for (var index = 0; index < count; index++) {
          final pair = buffer[index];
          final name = _bindings.copyCString(pair.key);
          final id = _bindings.copyCString(pair.value);
          _bindings.freeString(pair.key);
          _bindings.freeString(pair.value);
          running[name] = id;
        }
        if (count < capacity) {
          _runningByName = running;
          return running;
        }
      } finally {
        _bindings.freeNative(buffer);
      }
      capacity *= 2;
      if (capacity > 8192) {
        throw CoreClientException('list_instance returned too many instances.');
      }
    }
  }

  Map<String, Map<String, dynamic>> _collectInfos() {
    var capacity = 64;
    while (true) {
      final buffer = _bindings.allocateKeyValuePairs(capacity);
      try {
        final count = _bindings.collectNetworkInfos(buffer, capacity);
        if (count < 0) {
          throw CoreClientException(
            'collect_network_infos failed: '
            '${_bindings.takeLastError() ?? 'unknown error'}',
          );
        }
        final infos = <String, Map<String, dynamic>>{};
        for (var index = 0; index < count; index++) {
          final pair = buffer[index];
          final name = _bindings.copyCString(pair.key);
          final json = _bindings.copyCString(pair.value);
          _bindings.freeString(pair.key);
          _bindings.freeString(pair.value);
          final decoded = _tryJsonDecode(json);
          if (decoded is Map<String, dynamic>) infos[name] = decoded;
        }
        if (count < capacity) return infos;
      } finally {
        _bindings.freeNative(buffer);
      }
      capacity *= 2;
      if (capacity > 8192) {
        throw CoreClientException(
          'collect_network_infos returned too many instances.',
        );
      }
    }
  }

  InstanceStatus _statusFromInfo(
    String id,
    NetworkConfig? config,
    Map<String, dynamic> info,
  ) {
    final now = DateTime.now();
    final running = info['running'] == true;
    final error = _asString(info['error_msg']);
    final myNode = info['my_node_info'];
    final virtualIp = _ipv4Of(myNode) ?? _virtualIps[id];
    if (virtualIp != null && virtualIp.isNotEmpty) {
      _virtualIps[id] = virtualIp;
    }

    final peers = _parsePeers(info);
    final traffic = _sampleTraffic(id, info, now);

    final ConnectionPhase phase;
    if (!running) {
      phase = (error != null && error.isNotEmpty)
          ? ConnectionPhase.error
          : ConnectionPhase.stopped;
    } else if (error != null && error.isNotEmpty) {
      phase = ConnectionPhase.error;
    } else if (virtualIp == null || virtualIp.isEmpty) {
      phase = ConnectionPhase.connecting;
    } else {
      final online = peers.where((peer) => peer.online).toList();
      final relayOnly =
          online.isNotEmpty && online.every((peer) => peer.path == 'relay');
      phase = relayOnly ? ConnectionPhase.degraded : ConnectionPhase.connected;
    }

    final previousPhase = _lastPhase[id];
    _lastPhase[id] = phase;
    if (phase == ConnectionPhase.error &&
        previousPhase != ConnectionPhase.error) {
      _emit(
        kind: EventKind.error,
        title: 'Network error',
        detail: error ?? config?.instanceName,
      );
    }

    if (phase.isUp) {
      _connectedAt.putIfAbsent(id, () => now);
    } else {
      _connectedAt.remove(id);
    }
    final connectedAt = _connectedAt[id];

    int? latencyMs;
    for (final peer in peers) {
      final latency = peer.latencyMs;
      if (!peer.online || latency == null) continue;
      latencyMs = latencyMs == null ? latency : math.min(latencyMs, latency);
    }

    final routeCount = _asList(info['routes'])?.length ??
        _asList(info['peer_route_pairs'])?.length ??
        0;

    return InstanceStatus(
      instanceId: id,
      phase: phase,
      virtualIp: virtualIp,
      latencyMs: latencyMs,
      peerCount: peers.length,
      routeCount: routeCount,
      rxBps: traffic.rxBps,
      txBps: traffic.txBps,
      uptime: connectedAt == null ? Duration.zero : now.difference(connectedAt),
      peers: peers,
      error: error != null && error.isNotEmpty ? error : null,
      history: List<TrafficSample>.unmodifiable(
        _history[id] ?? const <TrafficSample>[],
      ),
    );
  }

  List<Peer> _parsePeers(Map<String, dynamic> info) {
    final pairs = _asList(info['peer_route_pairs']);
    final peerEntries = <Map<String, dynamic>>[];
    final routesByPeer = <int, Map<String, dynamic>>{};

    if (pairs != null && pairs.isNotEmpty) {
      for (final raw in pairs) {
        if (raw is! Map) continue;
        final peer = raw['peer'];
        if (peer is! Map) continue;
        peerEntries.add(Map<String, dynamic>.from(peer));
        final route = raw['route'];
        if (route is Map) {
          final peerId = _asInt(route['peer_id']);
          if (peerId != null) {
            routesByPeer[peerId] = Map<String, dynamic>.from(route);
          }
        }
      }
    } else {
      final fallback = _asList(info['peers']);
      if (fallback != null) {
        for (final raw in fallback) {
          if (raw is Map) peerEntries.add(Map<String, dynamic>.from(raw));
        }
      }
    }

    final hostnames = <int, String>{};
    for (final entry in routesByPeer.entries) {
      final hostname = _asString(entry.value['hostname']);
      if (hostname != null && hostname.isNotEmpty) {
        hostnames[entry.key] = hostname;
      }
    }

    final peers = <Peer>[];
    for (final peer in peerEntries) {
      final peerId = _asInt(peer['peer_id']) ?? peers.length;
      final route = routesByPeer[peerId] ?? const <String, dynamic>{};
      final conns = _asList(peer['conns']) ?? const <Object?>[];
      final openConns = conns
          .whereType<Map>()
          .where((conn) => conn['is_closed'] != true)
          .toList();

      int? latencyUs;
      for (final conn in openConns) {
        final stats = conn['stats'];
        if (stats is! Map) continue;
        final value = _asInt(stats['latency_us']);
        if (value == null) continue;
        latencyUs = latencyUs == null ? value : math.min(latencyUs, value);
      }

      final cost = _asInt(route['cost']);
      final nextHop = _asInt(route['next_hop_peer_id']);
      final direct = cost != null
          ? cost <= 1
          : (nextHop != null && nextHop == peerId);
      final online =
          openConns.isNotEmpty || (conns.isEmpty && !direct);
      final hostname = _asString(route['hostname']);
      final ipv4 = _ipv4Of(route['ipv4_addr']);

      peers.add(
        Peer(
          id: 'p$peerId',
          hostname: (hostname == null || hostname.isEmpty)
              ? 'peer $peerId'
              : hostname,
          ipv4: ipv4 ?? '',
          path: !online ? 'lost' : (direct ? 'direct' : 'relay'),
          latencyMs: latencyUs == null ? null : (latencyUs / 1000).round(),
          online: online,
          relayVia: (!direct && nextHop != null) ? hostnames[nextHop] : null,
        ),
      );
    }

    peers.sort((left, right) {
      final leftLatency = left.latencyMs ?? 1 << 30;
      final rightLatency = right.latencyMs ?? 1 << 30;
      return leftLatency.compareTo(rightLatency);
    });
    return peers;
  }

  _TrafficState _sampleTraffic(
    String id,
    Map<String, dynamic> info,
    DateTime now,
  ) {
    var rxBytes = 0;
    var txBytes = 0;
    final pairs = _asList(info['peer_route_pairs']);
    final peers = pairs != null && pairs.isNotEmpty
        ? pairs.whereType<Map>().map((pair) => pair['peer']).toList()
        : (_asList(info['peers']) ?? const <Object?>[]);
    for (final rawPeer in peers) {
      if (rawPeer is! Map) continue;
      final conns = _asList(rawPeer['conns']);
      if (conns == null) continue;
      for (final rawConn in conns) {
        if (rawConn is! Map || rawConn['is_closed'] == true) continue;
        final stats = rawConn['stats'];
        if (stats is! Map) continue;
        rxBytes += _asInt(stats['rx_bytes']) ?? 0;
        txBytes += _asInt(stats['tx_bytes']) ?? 0;
      }
    }

    final previous = _traffic[id];
    final elapsedMs = previous == null
        ? 0
        : now.difference(previous.at).inMilliseconds;
    final rxBps = elapsedMs >= 200 && previous != null
        ? math.max(0, ((rxBytes - previous.rxBytes) * 1000 / elapsedMs).round())
        : 0;
    final txBps = elapsedMs >= 200 && previous != null
        ? math.max(0, ((txBytes - previous.txBytes) * 1000 / elapsedMs).round())
        : 0;

    final state = _TrafficState(
      rxBytes: rxBytes,
      txBytes: txBytes,
      at: now,
      rxBps: rxBps,
      txBps: txBps,
      lastError: _asString(info['error_msg']),
    );
    _traffic[id] = state;

    final history = _history.putIfAbsent(id, () => <TrafficSample>[]);
    history.add(TrafficSample(at: now, rxBps: rxBps, txBps: txBps));
    if (history.length > 60) {
      history.removeRange(0, history.length - 60);
    }
    return state;
  }

  // ===== Event callback =====

  void _handleNativeEvent(Pointer<Char> payload, Pointer<Void> userData) {
    // The native side transfers ownership of the JSON string: copy then free,
    // even when decoding fails, otherwise every event leaks.
    String text;
    try {
      text = _bindings.copyCString(payload);
    } finally {
      _bindings.freeString(payload);
    }
    if (_disposed || text.isEmpty) return;
    try {
      final decoded = _tryJsonDecode(text);
      if (decoded is Map<String, dynamic>) _onNativeEvent(decoded);
    } on Object {
      // Event handling must never throw into the native runtime.
    }
  }

  void _onNativeEvent(Map<String, dynamic> payload) {
    final event = _asString(payload['event']);
    if (event == null) return;
    final instanceId = _asString(payload['instance_id']);
    final instanceName =
        _asString(payload['instance_name']) ??
        (instanceId == null ? null : _configs[instanceId]?.instanceName);
    final detail = _asString(payload['detail']);

    switch (event) {
      case 'dhcp_ip_changed':
        final parsed = _tryJsonDecode(detail ?? '');
        if (parsed is Map && parsed['new'] is String) {
          final next = (parsed['new'] as String).split('/').first;
          if (instanceId != null) _virtualIps[instanceId] = next;
          _emit(
            kind: EventKind.connected,
            title: 'Tunnel up',
            detail: instanceName == null ? next : '$next · $instanceName',
          );
        }
      case 'proxy_cidrs_updated':
        _emit(
          kind: EventKind.info,
          title: 'Proxy routes updated',
          detail: instanceName,
        );
      case 'peer_added':
        _emit(kind: EventKind.peerJoined, title: 'Peer joined', detail: detail);
      case 'peer_removed':
        _emit(kind: EventKind.peerLeft, title: 'Peer left', detail: detail);
      case 'peer_conn_added':
      case 'connection_accepted':
        _emit(
          kind: EventKind.peerJoined,
          title: 'Peer connected',
          detail: detail,
        );
      case 'peer_conn_removed':
        _emit(
          kind: EventKind.peerLeft,
          title: 'Peer disconnected',
          detail: detail,
        );
      case 'connecting':
        _emit(kind: EventKind.info, title: 'Connecting', detail: detail);
      case 'connect_error':
      case 'connection_error':
        _emit(
          kind: EventKind.warning,
          title: 'Connection error',
          detail: detail,
        );
      case 'tun_device_ready':
        _emit(
          kind: EventKind.info,
          title: 'TUN device ready',
          detail: detail,
        );
      case 'tun_device_error':
        _emit(
          kind: EventKind.error,
          title: 'TUN device error',
          detail: detail,
        );
      case 'listener_add_failed':
      case 'listener_accept_failed':
        _emit(
          kind: EventKind.warning,
          title: 'Listener problem',
          detail: detail,
        );
      case 'dhcp_ip_conflicted':
        _emit(
          kind: EventKind.warning,
          title: 'Virtual IP conflict',
          detail: detail,
        );
      case 'event_lagged':
        _emit(
          kind: EventKind.warning,
          title: 'Events dropped',
          detail: detail,
        );
      case 'credential_changed':
        _emit(
          kind: EventKind.info,
          title: 'Credentials rotated',
          detail: instanceName,
        );
    }
  }

  void _emit({required EventKind kind, required String title, String? detail}) {
    if (_events.isClosed) return;
    _events.add(
      NetworkEvent(at: DateTime.now(), kind: kind, title: title, detail: detail),
    );
  }

  // ===== Persistence =====

  Future<String> _upsertConfig(
    NetworkConfig config, {
    bool strictStorage = true,
  }) async {
    final id = _idForInstanceName(config.instanceName) ?? _newUuid();
    _configs[id] = config;
    try {
      await _saveStore();
    } on CoreClientException catch (error) {
      if (strictStorage) rethrow;
      // Running an instance is still useful without disk persistence; surface
      // the storage problem as an event instead of blocking the connect flow.
      _emit(
        kind: EventKind.warning,
        title: 'Configuration not persisted',
        detail: error.message,
      );
    }
    return id;
  }

  String? _idForInstanceName(String instanceName) {
    for (final entry in _configs.entries) {
      if (entry.value.instanceName == instanceName) return entry.key;
    }
    return null;
  }

  Future<void> _loadStore() async {
    try {
      final directory = _resolveConfigDirectory();
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      final file = File(
        '${directory.path}${Platform.pathSeparator}easytier_flutter.json',
      );
      _storeFile = file;
      _storeUsable = true;
      if (!await file.exists()) return;

      final decoded = _tryJsonDecode(await file.readAsString());
      if (decoded is! Map) return;
      final configs = decoded['configs'];
      if (configs is! List) return;
      for (final raw in configs) {
        if (raw is! Map) continue;
        final id = _asString(raw['id']);
        final configJson = raw['config'];
        if (id == null || configJson is! Map) continue;
        _configs[id] = _configFromJson(Map<String, dynamic>.from(configJson));
      }
    } on Object catch (error) {
      _storeUsable = false;
      _emit(
        kind: EventKind.warning,
        title: 'Configuration storage unavailable',
        detail: '$error',
      );
    }
  }

  Future<void> _saveStore() async {
    if (!_storeUsable || _storeFile == null) {
      throw CoreClientException(
        'No writable configuration directory. Pass FfiCoreClient('
        'configDirectory: ...) — on Android use context.filesDir from the '
        'VpnService host; on iOS use the Application Support directory.',
      );
    }
    final payload = jsonEncode(<String, Object?>{
      'version': 1,
      'configs': <Object?>[
        for (final entry in _configs.entries)
          <String, Object?>{
            'id': entry.key,
            'config': _configToJson(entry.value),
          },
      ],
    });
    final target = _storeFile!;
    final temporary = File('${target.path}.tmp');
    await temporary.writeAsString(payload, flush: true);
    await temporary.rename(target.path);
  }

  Directory _resolveConfigDirectory() {
    final configured = _configDirectoryOverride;
    if (configured != null && configured.trim().isNotEmpty) {
      return Directory(configured);
    }
    final explicit = Platform.environment['EASYTIER_FLUTTER_CONFIG_DIR'];
    if (explicit != null && explicit.trim().isNotEmpty) {
      return Directory(explicit);
    }
    if (Platform.isAndroid || Platform.isIOS) {
      // dart:io cannot discover the app sandbox directory without a plugin.
      // Hosts should pass `configDirectory`; the temp fallback keeps read-mostly
      // flows working but does not survive a restart.
      return Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}easytier_flutter',
      );
    }

    final separator = Platform.pathSeparator;
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        return Directory('$appData${separator}EasyTier');
      }
    }
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (Platform.isMacOS && home != null && home.isNotEmpty) {
      return Directory(
        '$home${separator}Library${separator}Application Support'
        '${separator}EasyTier',
      );
    }
    final xdg = Platform.environment['XDG_CONFIG_HOME'];
    if (xdg != null && xdg.isNotEmpty) {
      return Directory('$xdg${separator}easytier');
    }
    if (home != null && home.isNotEmpty) {
      return Directory('$home$separator.config${separator}easytier');
    }
    return Directory(
      '${Directory.systemTemp.path}${separator}easytier_flutter',
    );
  }

  // ===== Config <-> JSON =====

  static Map<String, Object?> _configToJson(NetworkConfig config) =>
      <String, Object?>{
        'instanceName': config.instanceName,
        'hostname': config.hostname,
        'networkName': config.networkName,
        'networkSecret': config.networkSecret,
        'dhcp': config.dhcp,
        'virtualIpv4': config.virtualIpv4,
        'networkLength': config.networkLength,
        'peerUrls': config.peerUrls,
        'listenerUrls': config.listenerUrls,
        'disableEncryption': config.disableEncryption,
        'disableIpv6': config.disableIpv6,
        'mtu': config.mtu,
        'latencyFirst': config.latencyFirst,
        'multiThread': config.multiThread,
        'devName': config.devName,
        'useSmoltcp': config.useSmoltcp,
        'bindDevice': config.bindDevice,
        'noTun': config.noTun,
        'enablePrivateMode': config.enablePrivateMode,
        'enableMagicDns': config.enableMagicDns,
        'disableP2p': config.disableP2p,
        'p2pOnly': config.p2pOnly,
        'relayAllPeerRpc': config.relayAllPeerRpc,
        'enableExitNode': config.enableExitNode,
        'proxyCidrs': config.proxyCidrs,
        'portForwards': <Object?>[
          for (final forward in config.portForwards)
            <String, Object?>{
              'proto': forward.proto,
              'local': forward.local,
              'remote': forward.remote,
            },
        ],
        'aclRules': <Object?>[
          for (final rule in config.aclRules)
            <String, Object?>{
              'action': rule.action,
              'protocol': rule.protocol,
              'chain': rule.chain,
              'source': rule.source,
              'destination': rule.destination,
              'ports': rule.ports,
              'comment': rule.comment,
            },
        ],
      };

  static NetworkConfig _configFromJson(Map<String, dynamic> json) {
    final forwards = _asList(json['portForwards']) ?? const <Object?>[];
    final aclRules = _asList(json['aclRules']) ?? const <Object?>[];
    return NetworkConfig(
      instanceName: _asString(json['instanceName']) ?? '',
      hostname: _asString(json['hostname']) ?? '',
      networkName: _asString(json['networkName']) ?? '',
      networkSecret: _asString(json['networkSecret']) ?? '',
      dhcp: json['dhcp'] != false,
      virtualIpv4: _asString(json['virtualIpv4']) ?? '',
      networkLength: _asInt(json['networkLength']) ?? 24,
      peerUrls: _asStrings(json['peerUrls']),
      listenerUrls: _asStrings(json['listenerUrls']),
      disableEncryption: json['disableEncryption'] == true,
      disableIpv6: json['disableIpv6'] == true,
      mtu: _asInt(json['mtu']),
      latencyFirst: json['latencyFirst'] == true,
      multiThread: json['multiThread'] != false,
      devName: _asString(json['devName']) ?? '',
      useSmoltcp: json['useSmoltcp'] == true,
      bindDevice: json['bindDevice'] != false,
      noTun: json['noTun'] == true,
      enablePrivateMode: json['enablePrivateMode'] == true,
      enableMagicDns: json['enableMagicDns'] == true,
      disableP2p: json['disableP2p'] == true,
      p2pOnly: json['p2pOnly'] == true,
      relayAllPeerRpc: json['relayAllPeerRpc'] == true,
      enableExitNode: json['enableExitNode'] == true,
      proxyCidrs: _asStrings(json['proxyCidrs']),
      portForwards: <PortForward>[
        for (final raw in forwards)
          if (raw is Map)
            PortForward(
              proto: _asString(raw['proto']) ?? 'tcp',
              local: _asString(raw['local']) ?? '',
              remote: _asString(raw['remote']) ?? '',
            ),
      ],
      aclRules: <AclRule>[
        for (final raw in aclRules)
          if (raw is Map)
            AclRule(
              action: _asString(raw['action']) ?? 'allow',
              protocol: _asString(raw['protocol']) ?? 'any',
              chain: _asString(raw['chain']) ?? 'inbound',
              source: _asString(raw['source']) ?? '0.0.0.0/0',
              destination: _asString(raw['destination']) ?? '0.0.0.0/0',
              ports: _asString(raw['ports']) ?? '',
              comment: _asString(raw['comment']) ?? '',
            ),
      ],
    );
  }

  // ===== TOML generation =====

  static const Map<String, int> _aclChainTypes = <String, int>{
    'inbound': 1,
    'outbound': 2,
    'forward': 3,
  };

  static const Map<String, int> _aclActions = <String, int>{
    'allow': 1,
    'deny': 2,
    'drop': 2,
  };

  static const Map<String, int> _aclProtocols = <String, int>{
    'tcp': 1,
    'udp': 2,
    'icmp': 3,
    'icmpv6': 4,
    'any': 5,
  };

  /// Serializes [config] into the TOML the core's `TomlConfigLoader` reads.
  ///
  /// The client uses this internally with the persisted instance UUID. It is
  /// public so the config screen can show the exact effective config (rather
  /// than the human-readable preview on [NetworkConfig.debugToml]) and so the
  /// wire format can be cross-checked against the Rust core in tests.
  static String encodeToml(NetworkConfig config, {String? instanceId}) =>
      _tomlFor(config, instanceId ?? _newUuid());

  static String _tomlFor(NetworkConfig config, String instanceId) {
    final buffer = StringBuffer();
    void line(String value) => buffer.writeln(value);
    void blank() => buffer.writeln();

    line('instance_name = ${_tomlString(config.instanceName)}');
    line('instance_id = ${_tomlString(instanceId)}');
    line('hostname = ${_tomlString(config.hostname)}');
    line('dhcp = ${config.dhcp}');
    if (!config.dhcp && config.virtualIpv4.trim().isNotEmpty) {
      line(
        'ipv4 = ${_tomlString('${config.virtualIpv4.trim()}/${config.networkLength}')}',
      );
    }
    line(
      'listeners = ['
      '${config.listenerUrls.map(_tomlString).join(', ')}]',
    );

    for (final peer in config.peerUrls) {
      if (peer.trim().isEmpty) continue;
      blank();
      line('[[peer]]');
      line('uri = ${_tomlString(peer.trim())}');
    }
    for (final cidr in config.proxyCidrs) {
      if (cidr.trim().isEmpty) continue;
      blank();
      line('[[proxy_network]]');
      line('cidr = ${_tomlString(cidr.trim())}');
    }
    for (final forward in config.portForwards) {
      blank();
      line('[[port_forward]]');
      line('bind_addr = ${_tomlString(forward.local)}');
      line('dst_addr = ${_tomlString(forward.remote)}');
      line('proto = ${_tomlString(forward.proto.toLowerCase())}');
    }

    blank();
    line('[network_identity]');
    line('network_name = ${_tomlString(config.networkName)}');
    line('network_secret = ${_tomlString(config.networkSecret)}');

    blank();
    line('[flags]');
    line('enable_encryption = ${!config.disableEncryption}');
    line('enable_ipv6 = ${!config.disableIpv6}');
    line('latency_first = ${config.latencyFirst}');
    line('multi_thread = ${config.multiThread}');
    line('use_smoltcp = ${config.useSmoltcp}');
    line('bind_device = ${config.bindDevice}');
    line('no_tun = ${config.noTun}');
    line('private_mode = ${config.enablePrivateMode}');
    line('accept_dns = ${config.enableMagicDns}');
    line('disable_p2p = ${config.disableP2p}');
    line('p2p_only = ${config.p2pOnly}');
    line('relay_all_peer_rpc = ${config.relayAllPeerRpc}');
    line('enable_exit_node = ${config.enableExitNode}');
    final mtu = config.mtu;
    if (mtu != null && mtu > 0) {
      line('mtu = $mtu');
    }
    if (config.devName.trim().isNotEmpty) {
      line('dev_name = ${_tomlString(config.devName.trim())}');
    }

    // ACL rules are grouped into one chain per direction. `default_action = 1`
    // (Allow) is intentional: the UI exposes individual rules, so an explicit
    // deny must not implicitly turn the list into a deny-all policy.
    final rulesByChain = <String, List<AclRule>>{};
    for (final rule in config.aclRules) {
      final chain = rule.chain.trim().toLowerCase();
      rulesByChain.putIfAbsent(chain, () => <AclRule>[]).add(rule);
    }
    for (final entry in rulesByChain.entries) {
      final chainType = _aclChainTypes[entry.key] ?? 1;
      blank();
      line('[[acl.acl_v1.chains]]');
      line('name = ${_tomlString('${entry.key}-rules')}');
      line('chain_type = $chainType');
      line('enabled = true');
      line('default_action = 1');
      for (var index = 0; index < entry.value.length; index++) {
        final rule = entry.value[index];
        final comment = rule.comment.trim();
        line('[[acl.acl_v1.chains.rules]]');
        line(
          'name = ${_tomlString(comment.isEmpty ? '${entry.key}-rule-${index + 1}' : comment)}',
        );
        if (comment.isNotEmpty) {
          line('description = ${_tomlString(comment)}');
        }
        line('priority = ${(entry.value.length - index).clamp(0, 65535)}');
        line('enabled = true');
        line('action = ${_aclActions[rule.action.trim().toLowerCase()] ?? 1}');
        line(
          'protocol = ${_aclProtocols[rule.protocol.trim().toLowerCase()] ?? 5}',
        );
        line(
          'source_ips = [${_tomlString(rule.source.trim().isEmpty ? '0.0.0.0/0' : rule.source.trim())}]',
        );
        line(
          'destination_ips = [${_tomlString(rule.destination.trim().isEmpty ? '0.0.0.0/0' : rule.destination.trim())}]',
        );
        final ports = rule.ports
            .split(',')
            .map((port) => port.trim())
            .where((port) => port.isNotEmpty)
            .toList();
        if (ports.isNotEmpty) {
          line('ports = [${ports.map(_tomlString).join(', ')}]');
        }
      }
    }

    return buffer.toString();
  }

  static String _tomlString(String value) => '"${value
      .replaceAll('\\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r')
      .replaceAll('\t', r'\t')}"';

  static String? _validateLocally(NetworkConfig config) {
    if (config.instanceName.trim().isEmpty) {
      return 'Instance name is required.';
    }
    if (config.networkName.trim().isEmpty) {
      return 'Network name is required.';
    }
    if (!config.dhcp) {
      if (config.virtualIpv4.trim().isEmpty) {
        return 'Static mode needs a virtual IPv4 address.';
      }
      if (!const <int>[8, 16, 24, 32].contains(config.networkLength)) {
        return 'Prefix length must be one of 8, 16, 24, 32.';
      }
      if (!_ipv4Pattern.hasMatch(config.virtualIpv4.trim())) {
        return 'Virtual IPv4 address is not a valid dotted quad.';
      }
    }
    for (final url in config.peerUrls) {
      if (url.trim().isEmpty) continue;
      if (!url.contains('://')) {
        return 'Peer URL "$url" needs a scheme (for example tcp://host:11010).';
      }
    }
    for (final url in config.listenerUrls) {
      if (url.trim().isEmpty) continue;
      if (!url.contains('://')) {
        return 'Listener URL "$url" needs a scheme (for example tcp://0.0.0.0:11010).';
      }
    }
    return null;
  }

  static final RegExp _ipv4Pattern = RegExp(
    r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$',
  );

  // ===== Worker isolate plumbing =====

  Future<_NativeResult> _runInWorker(String operation, String toml) async {
    final arguments = <Object?>[operation, toml, _libraryPath];
    final raw = await Isolate.run(() => _runNativeOperation(arguments));
    return _NativeResult(
      status: raw[0]! as int,
      error: raw[1] as String?,
    );
  }

  Future<void> _deleteInWorker(List<String> names) async {
    final arguments = <Object?>['delete_network_instance', names, _libraryPath];
    final raw = await Isolate.run(() => _runNativeOperation(arguments));
    final status = raw[0]! as int;
    if (status != 0) {
      throw CoreClientException(
        'delete_network_instance failed: ${raw[1] as String? ?? 'unknown error'}',
      );
    }
  }

  // ===== Helpers =====

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('FfiCoreClient.init() must be awaited before use.');
    }
  }

  void _dropTracking(String id) {
    _virtualIps.remove(id);
    _lastPhase.remove(id);
    _connectedAt.remove(id);
    _traffic.remove(id);
    _history.remove(id);
  }

  static String _newUuid() {
    final random = math.Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }

  static String? _ipv4Of(Object? value) {
    if (value == null) return null;
    if (value is String) {
      final address = value.split('/').first;
      return address.contains(':') ? null : address;
    }
    if (value is! Map) return null;

    // `common.Ipv4Inet` (protobuf JSON): {"address": {"addr": <u32>}, ...}
    final nested = value['address'];
    if (nested != null) return _ipv4Of(nested);
    final rawAddress = value['addr'];
    if (rawAddress is num) {
      final number = rawAddress.toInt();
      return '${(number >> 24) & 0xff}.${(number >> 16) & 0xff}.'
          '${(number >> 8) & 0xff}.${number & 0xff}';
    }
    if (rawAddress is String) {
      final address = rawAddress.split('/').first;
      return address.contains(':') ? null : address;
    }
    final direct = value['ipv4'] ?? value['ip'];
    if (direct != null) return _ipv4Of(direct);
    return null;
  }

  static Object? _tryJsonDecode(String source) {
    try {
      return jsonDecode(source);
    } on FormatException {
      return null;
    }
  }

  static List<Object?>? _asList(Object? value) =>
      value is List ? value.cast<Object?>() : null;

  static List<String> _asStrings(Object? value) {
    final list = _asList(value);
    if (list == null) return const <String>[];
    return <String>[
      for (final item in list)
        if (item is String) item,
    ];
  }

  static String? _asString(Object? value) {
    if (value is String) return value;
    if (value == null) return null;
    return value.toString();
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}

/// Outcome of one blocking native call executed on a worker isolate.
class _NativeResult {
  const _NativeResult({required this.status, required this.error});

  final int status;
  final String? error;
}

class _TrafficState {
  const _TrafficState({
    required this.rxBytes,
    required this.txBytes,
    required this.at,
    required this.rxBps,
    required this.txBps,
    this.lastError,
  });

  final int rxBytes;
  final int txBytes;
  final DateTime at;
  final int rxBps;
  final int txBps;
  final String? lastError;
}

/// Runs one blocking FFI operation on a worker isolate.
///
/// `run_network_instance` and `delete_network_instance` call
/// `Runtime::block_on` in Rust, so calling them on the UI isolate would stall
/// the Flutter event loop. A separate isolate keeps the UI responsive; the
/// library can be opened there because `dart:ffi` handles are per-isolate while
/// the loaded shared object and Rust statics stay process-wide. `get_error_msg`
/// is thread-local, so the error is read inside the same worker.
///
/// Arguments: `[operation, payload, libraryPath]` where payload is a TOML string
/// for `run_network_instance` and a `List<String>` of instance names for
/// `delete_network_instance`. Returns `[status, error]`.
List<Object?> _runNativeOperation(List<Object?> arguments) {
  final operation = arguments[0]! as String;
  final payload = arguments[1];
  final libraryPath = arguments[2] as String?;
  final bindings = EasytierFfi.load(overridePath: libraryPath).bindings;
  switch (operation) {
    case 'run_network_instance':
      final pointer = bindings.allocateCString(payload! as String);
      try {
        final status = bindings.runNetworkInstance(pointer);
        return <Object?>[
          status,
          status == 0 ? null : bindings.takeLastError(),
        ];
      } finally {
        bindings.freeCString(pointer);
      }
    case 'delete_network_instance':
      final names = (payload! as List<Object?>).cast<String>();
      final pointers = bindings.allocateCStringPointerArray(names.length);
      try {
        for (var index = 0; index < names.length; index++) {
          pointers[index] = bindings.allocateCString(names[index]);
        }
        final status = bindings.deleteNetworkInstance(pointers, names.length);
        return <Object?>[
          status,
          status == 0 ? null : bindings.takeLastError(),
        ];
      } finally {
        for (var index = 0; index < names.length; index++) {
          bindings.freeCString(pointers[index]);
        }
        bindings.freeNative(pointers);
      }
    default:
      return <Object?>[-1, 'unsupported native operation: $operation'];
  }
}
