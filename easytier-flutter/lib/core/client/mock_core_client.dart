import 'dart:async';
import 'dart:math' as math;

import '../models/models.dart';
import 'core_client.dart';

/// A deterministic-enough simulation of the EasyTier core.
///
/// It exists for two reasons: the UI can be built, reviewed and golden-tested
/// without a Rust toolchain; and the transport semantics (async start, status
/// polling, event push) are pinned down before the FFI client is written.
class MockCoreClient implements CoreClient {
  MockCoreClient({
    this.startDelay = const Duration(milliseconds: 900),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Duration startDelay;

  /// Injectable clock so golden tests are deterministic.
  final DateTime Function() _clock;
  final _events = StreamController<NetworkEvent>.broadcast();
  final _random = math.Random(42);
  final Map<String, _SimInstance> _sims = {};
  int _nextId = 1;

  @override
  Future<void> init() async {
    if (_sims.isNotEmpty) return;
    final cfg = _defaultConfig();
    final inst = NetworkInstance(id: 'inst-1', config: cfg, enabled: true);
    _sims[inst.id] = _SimInstance(inst);
    _events.add(NetworkEvent(
      at: _clock(),
      kind: EventKind.info,
      title: 'Client ready',
      detail: 'Mock core — 1 network configured',
    ));
  }

  @override
  Future<List<NetworkInstance>> listInstances() async =>
      _sims.values.map((s) => s.instance).toList(growable: false);

  @override
  Future<String> runInstance(NetworkConfig config) async {
    final existing = _sims.values.where((s) => s.instance.config.instanceName == config.instanceName);
    final id = existing.isNotEmpty ? existing.first.instance.id : 'inst-${_nextId++}';
    final sim = _sims.putIfAbsent(id, () => _SimInstance(NetworkInstance(id: id, config: config, enabled: true)));
    _sims[id] = sim.copyWith(instance: sim.instance.copyWith(config: config, enabled: true));

    final current = _sims[id]!;
    if (current.phase.isUp) return id;
    current.phase = ConnectionPhase.connecting;
    current.connectedAt = null;
    current.error = null;
    _events.add(NetworkEvent(
      at: _clock(),
      kind: EventKind.info,
      title: 'Connecting to ${config.networkName}',
      detail: config.instanceName,
    ));

    // Zero delay must resolve as a microtask: widget tests run in FakeAsync,
    // where a zero-duration timer only fires when the tester elapses time.
    await (startDelay == Duration.zero
        ? Future<void>.microtask(() {})
        : Future<void>.delayed(startDelay));
    final now = _sims[id];
    if (now == null || now.phase != ConnectionPhase.connecting) return id;
    now.phase = ConnectionPhase.connected;
    // Seeded a few minutes in the past so the mock (and goldens) show a
    // realistic uptime instead of "up 0s" on the first frame.
    now.connectedAt = _clock().subtract(const Duration(minutes: 14, seconds: 32));
    now.peers = _seedPeers();
    now.error = null;
    now.history = seedTrafficHistory(baseRx: 820000, baseTx: 160000, now: _clock());
    _events.add(NetworkEvent(
      at: _clock(),
      kind: EventKind.connected,
      title: 'Connected to ${config.networkName}',
      detail: '${now.peers.length} peers · ${now.peers.first.ipv4}',
    ));
    return id;
  }

  @override
  Future<void> stopInstance(String id) async {
    final sim = _sims[id];
    if (sim == null) return;
    final wasUp = sim.phase.isUp;
    sim.phase = ConnectionPhase.stopped;
    sim.connectedAt = null;
    sim.peers = const [];
    sim.history = const [];
    if (wasUp) {
      _events.add(NetworkEvent(
        at: _clock(),
        kind: EventKind.disconnected,
        title: 'Disconnected',
        detail: sim.instance.config.networkName,
      ));
    }
  }

  @override
  Future<void> deleteInstance(String id) async {
    final sim = _sims.remove(id);
    if (sim != null) {
      _events.add(NetworkEvent(
        at: _clock(),
        kind: EventKind.info,
        title: 'Network removed',
        detail: sim.instance.config.networkName,
      ));
    }
  }

  @override
  Future<void> saveConfig(NetworkConfig config) async {
    for (final entry in _sims.entries.toList()) {
      if (entry.value.instance.config.instanceName != config.instanceName) continue;
      _sims[entry.key] = entry.value.copyWith(
        instance: entry.value.instance.copyWith(config: config),
      );
      return;
    }
    final id = 'inst-${_nextId++}';
    _sims[id] = _SimInstance(NetworkInstance(id: id, config: config));
  }

  @override
  Future<NetworkConfig?> getConfig(String id) async => _sims[id]?.instance.config;

  @override
  Future<String?> validateConfig(NetworkConfig config) async {
    if (config.networkName.trim().isEmpty) return 'Network name is required.';
    if (config.instanceName.trim().isEmpty) return 'Instance name is required.';
    if (!config.dhcp && config.virtualIpv4.trim().isEmpty) {
      return 'Static mode needs a virtual IPv4 address.';
    }
    final lengths = <int>[8, 16, 24, 32];
    if (!config.dhcp && !lengths.contains(config.networkLength)) {
      return 'Prefix length must be one of 8, 16, 24, 32.';
    }
    return null;
  }

  @override
  Future<InstanceStatus> collectStatus(String id) async {
    final sim = _sims[id];
    if (sim == null) return InstanceStatus.stopped;
    if (!sim.phase.isUp) {
      return InstanceStatus(
        instanceId: id,
        phase: sim.phase,
        error: sim.error,
        virtualIp: sim.instance.config.virtualIpv4,
      );
    }

    final now = _clock();
    final tick = now.millisecondsSinceEpoch ~/ 1000;
    final rx = 620000 + (math.sin(tick / 3) * 180000).round() + _random.nextInt(40000);
    final tx = 140000 + (math.cos(tick / 4) * 60000).round() + _random.nextInt(20000);
    final latency = 18 + (math.sin(tick / 5) * 6).round() + _random.nextInt(4);

    sim.history = [
      ...sim.history.skip(sim.history.length > 59 ? 1 : 0),
      TrafficSample(at: now, rxBps: rx, txBps: tx),
    ];

    sim.peers = sim.peers
        .map((p) => Peer(
              id: p.id,
              hostname: p.hostname,
              ipv4: p.ipv4,
              path: p.path,
              relayVia: p.relayVia,
              latencyMs: p.latencyMs == null
                  ? null
                  : math.max(3, p.latencyMs! + _random.nextInt(5) - 2),
              online: p.online,
              lastSeen: p.lastSeen,
            ))
        .toList(growable: false);

    final peers = sim.peers;
    final allRelay = peers.where((p) => p.online).every((p) => p.path == 'relay');
    return InstanceStatus(
      instanceId: id,
      phase: allRelay && peers.isNotEmpty ? ConnectionPhase.degraded : sim.phase,
      virtualIp: sim.instance.config.dhcp ? '10.144.0.${17 + _nextId}' : sim.instance.config.virtualIpv4,
      latencyMs: latency,
      peerCount: peers.length,
      routeCount: peers.where((p) => p.online).length + 1,
      rxBps: rx,
      txBps: tx,
      uptime: sim.connectedAt == null ? Duration.zero : now.difference(sim.connectedAt!),
      peers: peers,
      history: sim.history,
    );
  }

  @override
  Future<String> version() async => '2.7.0-mock';

  @override
  Stream<NetworkEvent> get events => _events.stream;

  @override
  Future<void> dispose() async => _events.close();

  NetworkConfig _defaultConfig() => const NetworkConfig(
        instanceName: 'office-mesh',
        hostname: 'chance-desktop',
        networkName: 'EasyTier Home',
        networkSecret: 'correct-horse-battery',
        dhcp: true,
        peerUrls: ['tcp://public.easytier.top:11010'],
        listenerUrls: ['tcp://0.0.0.0:11010', 'udp://0.0.0.0:11010', 'wg://0.0.0.0:11011'],
      );

  List<Peer> _seedPeers() => const [
        Peer(id: 'p1', hostname: 'nas', ipv4: '10.144.0.4', path: 'direct', latencyMs: 8),
        Peer(id: 'p2', hostname: 'macbook', ipv4: '10.144.0.6', path: 'direct', latencyMs: 14),
        Peer(id: 'p3', hostname: 'homeserver', ipv4: '10.144.0.9', path: 'direct', latencyMs: 21),
        Peer(id: 'p4', hostname: 'shenzhen-edge', ipv4: '10.144.0.12', path: 'relay', relayVia: 'nas', latencyMs: 58),
        Peer(id: 'p5', hostname: 'laptop-old', ipv4: '10.144.0.15', path: 'direct', latencyMs: 9, online: true),
        Peer(id: 'p6', hostname: 'pi-lab', ipv4: '10.144.0.18', path: 'lost', latencyMs: null, online: false, lastSeen: null),
      ];
}

class _SimInstance {
  _SimInstance(this.instance);

  NetworkInstance instance;
  ConnectionPhase phase = ConnectionPhase.stopped;
  DateTime? connectedAt;
  List<Peer> peers = const [];
  List<TrafficSample> history = const [];
  String? error;

  _SimInstance copyWith({NetworkInstance? instance}) =>
      _SimInstance(instance ?? this.instance)
        ..phase = phase
        ..connectedAt = connectedAt
        ..peers = peers
        ..history = history
        ..error = error;
}
