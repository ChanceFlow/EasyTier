import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import '../../config/canonical_toml.dart';
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
class FfiCoreClient implements CoreClient, TunFdCapable, StorageAwareCoreClient {
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
  String? _storageWarning;
  String? _configStorePath;
  bool _initialized = false;
  bool _disposed = false;
  String? _version;

  @override
  String? get storageWarning => _storageWarning;

  @override
  String? get configStorePath => _configStorePath;

  /// Instance id -> instance name, refreshed by every native list call.
  Map<String, String> _runningNameById = const <String, String>{};

  final Map<String, String> _virtualIps = <String, String>{};
  final Map<String, int> _virtualIpPrefixes = <String, int>{};
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
    _emit(
      kind: _storeUsable ? EventKind.info : EventKind.warning,
      title: _storeUsable
          ? 'Configuration store ready'
          : 'Configuration store unavailable',
      detail: _storageWarning ?? _configStorePath,
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
      final info = _collectInfos()[config.instanceName];
      final healthy =
          info != null &&
          info['running'] == true &&
          (_asString(info['error_msg'])?.isEmpty ?? true);
      if (healthy) {
        return existingId;
      }
      await _deleteInWorker(<String>[config.instanceName]);
    }

    final toml = encodeToml(config, instanceId: id);
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

    _dropTracking(id);
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
    final name = config?.instanceName ?? _runningNameById[id];
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
      try {
        await _saveStore();
      } on Object {
        // The removal already happened in memory; a stale on-disk copy is
        // reported through [storageWarning] instead of failing the delete.
      }
      _emit(
        kind: EventKind.info,
        title: 'Network removed',
        detail: config?.networkName ?? config?.instanceName,
      );
    }
  }

  @override
  Future<void> saveConfig(NetworkConfig config, {String? instanceId}) async {
    _ensureInitialized();
    // A writable sandbox is not guaranteed (Android without a host-provided
    // directory, a read-only data partition, a full disk). Keep the network
    // usable in memory and report the storage problem instead of refusing to
    // save at all: the user can still connect this session, and the UI shows
    // that it will not survive a restart.
    await _upsertConfig(config, instanceId: instanceId, strictStorage: false);
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
      encodeToml(config, instanceId: existingId ?? _newUuid()),
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
    final name = config?.instanceName ?? _runningNameById[id];
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
        virtualIpPrefixLength: _virtualIpPrefixes[id],
      );
    }

    return statusFromRunningInfo(id, config, info);
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
    final name =
        _configs[instanceId]?.instanceName ?? _runningNameById[instanceId];
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
        final byId = <String, String>{};
        for (var index = 0; index < count; index++) {
          final pair = buffer[index];
          final name = _bindings.copyCString(pair.key);
          final id = _bindings.copyCString(pair.value);
          _bindings.freeString(pair.key);
          _bindings.freeString(pair.value);
          running[name] = id;
          byId[id] = name;
        }
        if (count < capacity) {
          _runningNameById = byId;
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

  /// Converts a raw `collect_network_infos` snapshot into [InstanceStatus].
  /// Exposed for unit tests so JSON decoding can be verified without a native `.so`.
  InstanceStatus statusFromRunningInfo(
    String id,
    NetworkConfig? config,
    Map<String, dynamic> info,
  ) {
    final now = DateTime.now();
    final running = info['running'] == true;
    final error = _asString(info['error_msg']);
    final myNode = info['my_node_info'];
    final nodeIpInfo = _ipv4InfoOf(myNode);
    final virtualIp = nodeIpInfo?.ip ?? _virtualIps[id];
    final virtualIpPrefixLength =
        nodeIpInfo?.prefix ??
        _virtualIpPrefixes[id] ??
        ((virtualIp != null && virtualIp.isNotEmpty)
            ? (config?.dhcp == false ? config?.networkLength : 24)
            : null);
    if (virtualIp != null && virtualIp.isNotEmpty) {
      _virtualIps[id] = virtualIp;
      if (virtualIpPrefixLength != null) {
        _virtualIpPrefixes[id] = virtualIpPrefixLength;
      }
    }

    final myPeerId = myNode is Map ? _asInt(myNode['peer_id']) : null;
    final peers = _parsePeers(info, myPeerId: myPeerId);
    final remoteProxyCidrs = _extractRemoteProxyCidrs(
      info,
      config: config,
      myPeerId: myPeerId,
    );
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
      virtualIpPrefixLength: virtualIpPrefixLength,
      latencyMs: latencyMs,
      peerCount: peers.length,
      routeCount: routeCount,
      rxBps: traffic.rxBps,
      txBps: traffic.txBps,
      uptime: connectedAt == null ? Duration.zero : now.difference(connectedAt),
      peers: peers,
      remoteProxyCidrs: remoteProxyCidrs,
      error: error != null && error.isNotEmpty ? error : null,
      history: List<TrafficSample>.unmodifiable(
        _history[id] ?? const <TrafficSample>[],
      ),
    );
  }

  List<Peer> _parsePeers(Map<String, dynamic> info, {int? myPeerId}) {
    final pairs = _asList(info['peer_route_pairs']);
    final peerEntries = <Map<String, dynamic>>[];
    final routesByPeer = <int, Map<String, dynamic>>{};

    if (pairs != null && pairs.isNotEmpty) {
      for (final raw in pairs) {
        if (raw is! Map) continue;
        final route = raw['route'];
        int? routePeerId;
        if (route is Map) {
          routePeerId = _asInt(route['peer_id']);
          if (routePeerId != null) {
            routesByPeer[routePeerId] = Map<String, dynamic>.from(route);
          }
        }
        final peer = raw['peer'];
        if (peer is Map) {
          peerEntries.add(Map<String, dynamic>.from(peer));
        } else if (routePeerId != null && routePeerId != myPeerId) {
          peerEntries.add(<String, dynamic>{
            'peer_id': routePeerId,
            'conns': const <Object?>[],
          });
        }
      }
    } else {
      final fallback = _asList(info['peers']);
      if (fallback != null) {
        for (final raw in fallback) {
          if (raw is Map) peerEntries.add(Map<String, dynamic>.from(raw));
        }
      }
      final fallbackRoutes = _asList(info['routes']);
      if (fallbackRoutes != null) {
        for (final raw in fallbackRoutes) {
          if (raw is! Map) continue;
          final peerId = _asInt(raw['peer_id']);
          if (peerId != null) {
            routesByPeer[peerId] = Map<String, dynamic>.from(raw);
          }
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
      if (myPeerId != null && peerId == myPeerId) continue;
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
      final routeLatencyMs = _asInt(route['path_latency']);
      final latencyMs = latencyUs != null
          ? (latencyUs / 1000).round()
          : (routeLatencyMs != null && routeLatencyMs > 0 ? routeLatencyMs : null);

      peers.add(
        Peer(
          id: 'p$peerId',
          hostname: (hostname == null || hostname.isEmpty)
              ? 'peer $peerId'
              : hostname,
          ipv4: ipv4 ?? '',
          path: !online ? 'lost' : (direct ? 'direct' : 'relay'),
          latencyMs: latencyMs,
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

  List<String> _extractRemoteProxyCidrs(
    Map<String, dynamic> info, {
    NetworkConfig? config,
    int? myPeerId,
  }) {
    final local = <String>{
      for (final cidr in config?.proxyCidrs ?? const <String>[])
        ?_normalizeIpv4Cidr(cidr),
    };
    final result = <String>{};

    void addFromRoute(Object? rawRoute) {
      if (rawRoute is! Map) return;
      final peerId = _asInt(rawRoute['peer_id']);
      if (myPeerId != null && peerId == myPeerId) return;
      final cidrs = _asList(rawRoute['proxy_cidrs']);
      if (cidrs == null) return;
      for (final item in cidrs) {
        if (item is! String) continue;
        final normalized = _normalizeIpv4Cidr(item);
        if (normalized != null && !local.contains(normalized)) {
          result.add(normalized);
        }
      }
    }

    final routes = _asList(info['routes']);
    if (routes != null && routes.isNotEmpty) {
      for (final route in routes) {
        addFromRoute(route);
      }
    } else {
      final pairs = _asList(info['peer_route_pairs']);
      if (pairs != null) {
        for (final pair in pairs) {
          if (pair is Map) addFromRoute(pair['route']);
        }
      }
    }

    final sorted = result.toList()..sort();
    return List<String>.unmodifiable(sorted);
  }

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
      if (decoded is Map<String, dynamic>) processNativeEvent(decoded);
    } on Object {
      // Event handling must never throw into the native runtime.
    }
  }

  /// Processes a decoded native event payload (exposed for unit tests).
  void processNativeEvent(Map<String, dynamic> payload) {
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
        if (parsed is Map) {
          final nextRaw = parsed['new'];
          if (nextRaw is String) {
            final info = _ipv4InfoOf(nextRaw);
            if (info != null) {
              if (instanceId != null) {
                _virtualIps[instanceId] = info.ip;
                _virtualIpPrefixes[instanceId] = info.prefix ?? 24;
              }
              _emit(
                kind: EventKind.connected,
                title: 'Tunnel up',
                detail: instanceName == null
                    ? info.ip
                    : '${info.ip} · $instanceName',
              );
            }
          } else if (nextRaw == null && instanceId != null) {
            _virtualIps.remove(instanceId);
            _virtualIpPrefixes.remove(instanceId);
          }
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
    String? instanceId,
    bool strictStorage = true,
  }) async {
    // An explicit id means "this is an edit of that record"; matching by name
    // alone would turn a rename into a second network with a new uuid.
    final id = (instanceId != null && _configs.containsKey(instanceId))
        ? instanceId
        : _idForInstanceName(config.instanceName) ?? _newUuid();
    _configs[id] = config;
    try {
      await _saveStore();
    } on Object catch (error) {
      if (strictStorage) {
        throw error is CoreClientException
            ? error
            : CoreClientException('failed to persist the configuration: $error');
      }
      // Running an instance is still useful without disk persistence; surface
      // the storage problem as an event instead of blocking the save/connect
      // flow.
      _emit(
        kind: EventKind.warning,
        title: 'Configuration not persisted',
        detail: _storageWarning ?? '$error',
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

  /// Probes [directory] by creating and deleting a marker file inside it.
  ///
  /// `Directory.create` alone is not enough on Android: some candidate paths
  /// exist but reject every write, which previously looked like an empty
  /// configuration list (the app showed "no networks" with no explanation).
  ///
  /// Throws when the directory cannot be created or written.
  static Future<void> probeWritableDirectory(Directory directory) async {
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    final separator = directory.path.endsWith(Platform.pathSeparator)
        ? ''
        : Platform.pathSeparator;
    final probe = File('${directory.path}$separator.easytier_write_probe');
    await probe.writeAsString('probe', flush: true);
    await probe.delete();
  }

  Future<void> _probeWritable(Directory directory) =>
      probeWritableDirectory(directory);

  Future<void> _loadStore() async {
    final candidates = _configDirectoryCandidates();
    final attempts = <String>[];
    Directory? chosen;
    for (final directory in candidates) {
      try {
        await _probeWritable(directory);
        chosen = directory;
        break;
      } on Object catch (error) {
        attempts.add('${directory.path}: $error');
      }
    }

    if (chosen == null) {
      _storeUsable = false;
      _storeFile = null;
      _storageWarning =
          'No writable configuration directory. Networks work for this session '
          'but will not be saved across restarts. Tried: ${attempts.join('; ')}';
      _emit(
        kind: EventKind.warning,
        title: 'Configuration storage unavailable',
        detail: _storageWarning,
      );
      return;
    }

    _configStorePath = chosen.path;
    _storeFile = storeFileIn(chosen);
    _storeUsable = true;
    _storageWarning = null;

    final existedBefore = await _storeFile!.exists();
    await _readStoreFile(_storeFile!);
    if (!existedBefore) {
      await _importLegacyStores(candidates, chosen);
    }
  }

  /// `easytier_flutter.json` inside [directory].
  static File storeFileIn(Directory directory) {
    final separator = directory.path.endsWith(Platform.pathSeparator)
        ? ''
        : Platform.pathSeparator;
    return File('${directory.path}$separator.easytier_flutter.json');
  }

  /// Reads the persisted configurations from one store file.
  ///
  /// Returns an empty list for a missing or structurally empty file; throws
  /// [FormatException] when the file exists but is not a config store, so the
  /// caller can report a real problem instead of pretending nothing was saved.
  static Future<List<({String id, NetworkConfig config})>> readStoreFile(
    File file,
  ) async {
    if (!await file.exists()) return const <({String id, NetworkConfig config})>[];
    final decoded = _tryJsonDecode(await file.readAsString());
    if (decoded is! Map) {
      throw FormatException('${file.path} is not valid JSON');
    }
    final configs = decoded['configs'];
    if (configs is! List) {
      throw FormatException('${file.path} has no configs list');
    }
    final entries = <({String id, NetworkConfig config})>[];
    for (final raw in configs) {
      if (raw is! Map) continue;
      final id = _asString(raw['id']);
      final configJson = raw['config'];
      if (id == null || configJson is! Map) continue;
      entries.add((
        id: id,
        config: _configFromJson(Map<String, dynamic>.from(configJson)),
      ));
    }
    return entries;
  }

  Future<void> _readStoreFile(File file) async {
    final List<({String id, NetworkConfig config})> entries;
    try {
      entries = await readStoreFile(file);
    } on FormatException catch (error) {
      _storageWarning = 'Configuration file unreadable ($error); starting empty.';
      _emit(
        kind: EventKind.warning,
        title: 'Configuration file unreadable',
        detail: _storageWarning,
      );
      return;
    }
    for (final entry in entries) {
      _configs[entry.id] = entry.config;
    }
  }

  /// Imports configurations written by an older build into the store this
  /// install chose.
  ///
  /// The first Android builds could only fall back to a temp directory, so a
  /// network added before this fix lives there. Scanning the other candidates
  /// once (only when the new store does not exist yet) means those networks
  /// keep working instead of the user having to re-create them.
  Future<void> _importLegacyStores(
    List<Directory> candidates,
    Directory chosen,
  ) async {
    var imported = 0;
    for (final directory in candidates) {
      if (directory.path == chosen.path) continue;
      final file = storeFileIn(directory);
      final List<({String id, NetworkConfig config})> entries;
      try {
        entries = await readStoreFile(file);
      } on FormatException {
        continue;
      } on FileSystemException {
        continue;
      }
      for (final entry in entries) {
        final nameTaken = _configs.values.any(
          (config) => config.instanceName == entry.config.instanceName,
        );
        if (nameTaken) continue;
        _configs[entry.id] = entry.config;
        imported++;
      }
    }
    if (imported == 0) return;
    try {
      await _saveStore();
    } on Object {
      // The in-memory list is already correct; the storage warning explains
      // the rest.
    }
    _emit(
      kind: EventKind.info,
      title: 'Imported saved networks',
      detail: '$imported configuration(s) moved to ${chosen.path}',
    );
  }

  Future<void> _saveStore() async {
    final target = _storeFile;
    if (!_storeUsable || target == null) {
      final message = _storageWarning ??
          'No writable configuration directory. Pass FfiCoreClient('
              'configDirectory: ...) — on Android the host supplies '
              'context.filesDir; on iOS the Application Support directory.';
      _storageWarning = message;
      throw CoreClientException(message);
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
    try {
      final temporary = File('${target.path}.tmp');
      await temporary.writeAsString(payload, flush: true);
      await temporary.rename(target.path);
      _storageWarning = null;
    } on Object catch (error) {
      _storageWarning = 'Could not save configurations to ${target.path}: $error';
      rethrow;
    }
  }

  /// Directories to try, in priority order.
  ///
  /// The host-provided directory wins; the environment override is for desktop
  /// debugging. Everything after that is a heuristic fallback so a stripped
  /// sandbox still finds *something* writable instead of silently losing every
  /// configuration (Android used to end up with an empty list that way).
  List<Directory> _configDirectoryCandidates() {
    final candidates = <Directory>[];
    void add(String? path) {
      if (path == null || path.trim().isEmpty) return;
      final directory = Directory(path.trim());
      if (!candidates.any((existing) => existing.path == directory.path)) {
        candidates.add(directory);
      }
    }

    add(_configDirectoryOverride);
    add(Platform.environment['EASYTIER_FLUTTER_CONFIG_DIR']);

    final separator = Platform.pathSeparator;
    final temp = Directory.systemTemp.path;

    if (Platform.isAndroid || Platform.isIOS) {
      // dart:io cannot discover the app sandbox without host help; keep the
      // historical temp location as a last resort so an older install can
      // still read what it wrote.
      add('$temp${separator}easytier_flutter');
      add('$temp$separator.easytier_flutter');
      return candidates;
    }

    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        add('$appData${separator}EasyTier');
      }
    }
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (Platform.isMacOS && home != null && home.isNotEmpty) {
      add(
        '$home${separator}Library${separator}Application Support'
        '${separator}EasyTier',
      );
    }
    final xdg = Platform.environment['XDG_CONFIG_HOME'];
    if (xdg != null && xdg.isNotEmpty) {
      add('$xdg${separator}easytier');
    }
    if (home != null && home.isNotEmpty) {
      add('$home$separator.config${separator}easytier');
    }
    add('$temp${separator}easytier_flutter');
    return candidates;
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

  /// Serialises [config] into the canonical TOML read by the core's
  /// `TomlConfigLoader`. The source editor uses the very same encoder, so its
  /// text is a real config file rather than a client-only preview.
  static String encodeToml(NetworkConfig config, {String? instanceId}) =>
      encodeConfigToml(config, instanceId: instanceId ?? _newUuid());

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
      if (config.networkLength < 1 || config.networkLength > 32) {
        return 'Prefix length must be between 1 and 32.';
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
    _virtualIpPrefixes.remove(id);
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

  static String? _ipv4Of(Object? value) => _ipv4InfoOf(value)?.ip;

  static ({String ip, int? prefix})? _ipv4InfoOf(Object? value) {
    if (value == null) return null;
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty || trimmed.contains(':')) return null;
      final slash = trimmed.indexOf('/');
      final address = (slash < 0 ? trimmed : trimmed.substring(0, slash)).trim();
      if (address.isEmpty || address == '0.0.0.0') return null;
      final prefix = slash < 0
          ? null
          : int.tryParse(trimmed.substring(slash + 1).trim());
      return (
        ip: address,
        prefix: prefix != null && prefix > 0 && prefix <= 32 ? prefix : null,
      );
    }
    if (value is! Map) return null;

    final rawLength = _asInt(value['network_length'] ?? value['networkLength']);
    final mapPrefix = (rawLength != null && rawLength > 0 && rawLength <= 32)
        ? rawLength
        : null;

    // `common.Ipv4Inet` (protobuf JSON): {"address": {"addr": <u32>}, "network_length": <u32>}
    final nested = value['address'];
    if (nested != null) {
      final inner = _ipv4InfoOf(nested);
      if (inner == null) return null;
      return (ip: inner.ip, prefix: inner.prefix ?? mapPrefix);
    }
    final rawAddress = value['addr'];
    if (rawAddress is num) {
      final number = rawAddress.toInt();
      if (number == 0) return null;
      final ip =
          '${(number >> 24) & 0xff}.${(number >> 16) & 0xff}.'
          '${(number >> 8) & 0xff}.${number & 0xff}';
      return (ip: ip, prefix: mapPrefix);
    }
    if (rawAddress is String) {
      final inner = _ipv4InfoOf(rawAddress);
      if (inner == null) return null;
      return (ip: inner.ip, prefix: inner.prefix ?? mapPrefix);
    }
    final direct =
        value['virtual_ipv4'] ??
        value['virtualIpv4'] ??
        value['ipv4_addr'] ??
        value['ipv4Addr'] ??
        value['ipv4'] ??
        value['ip'];
    if (direct != null) {
      final inner = _ipv4InfoOf(direct);
      if (inner == null) return null;
      return (ip: inner.ip, prefix: inner.prefix ?? mapPrefix);
    }
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
