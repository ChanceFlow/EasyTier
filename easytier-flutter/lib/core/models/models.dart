import 'dart:math' as math;


/// Data model shared by every screen. It is deliberately transport-agnostic:
/// the mock client and the Rust FFI client produce the same types, so the UI
/// can be developed and reviewed without a live core.

enum ConnectionPhase {
  /// No instance running.
  stopped,

  /// Starting / joining the network.
  connecting,

  /// Tunnel up and peers reachable.
  connected,

  /// Tunnel up but the network is degraded (relay-only, high loss, ...).
  degraded,

  /// Start failed or the tunnel dropped with an error.
  error;

  bool get isUp => this == connected || this == degraded;

  bool get isBusy => this == connecting;
}

class Peer {
  const Peer({
    required this.id,
    required this.hostname,
    required this.ipv4,
    required this.path,
    this.latencyMs,
    this.online = true,
    this.relayVia,
    this.lastSeen,
  });

  final String id;
  final String hostname;
  final String ipv4;

  /// `direct` | `relay` | `lost`
  final String path;
  final int? latencyMs;
  final bool online;
  final String? relayVia;
  final DateTime? lastSeen;

  String get pathLabel => switch (path) {
    'direct' => 'Direct',
    'relay' => relayVia == null ? 'Relay' : 'Relay via $relayVia',
    _ => 'Lost',
  };
}

class TrafficSample {
  const TrafficSample({required this.at, required this.rxBps, required this.txBps});

  final DateTime at;
  final int rxBps;
  final int txBps;
}

class InstanceStatus {
  const InstanceStatus({
    required this.instanceId,
    required this.phase,
    this.virtualIp,
    this.latencyMs,
    this.peerCount = 0,
    this.routeCount = 0,
    this.rxBps = 0,
    this.txBps = 0,
    this.uptime = Duration.zero,
    this.peers = const [],
    this.error,
    this.history = const [],
  });

  final String instanceId;
  final ConnectionPhase phase;
  final String? virtualIp;
  final int? latencyMs;
  final int peerCount;
  final int routeCount;
  final int rxBps;
  final int txBps;
  final Duration uptime;
  final List<Peer> peers;
  final String? error;
  final List<TrafficSample> history;

  int get onlinePeers => peers.where((p) => p.online).length;

  InstanceStatus copyWith({
    ConnectionPhase? phase,
    String? virtualIp,
    int? latencyMs,
    int? peerCount,
    int? routeCount,
    int? rxBps,
    int? txBps,
    Duration? uptime,
    List<Peer>? peers,
    String? error,
    List<TrafficSample>? history,
    bool clearError = false,
  }) => InstanceStatus(
    instanceId: instanceId,
    phase: phase ?? this.phase,
    virtualIp: virtualIp ?? this.virtualIp,
    latencyMs: latencyMs ?? this.latencyMs,
    peerCount: peerCount ?? this.peerCount,
    routeCount: routeCount ?? this.routeCount,
    rxBps: rxBps ?? this.rxBps,
    txBps: txBps ?? this.txBps,
    uptime: uptime ?? this.uptime,
    peers: peers ?? this.peers,
    error: clearError ? null : (error ?? this.error),
    history: history ?? this.history,
  );

  static const stopped = InstanceStatus(
    instanceId: '',
    phase: ConnectionPhase.stopped,
  );
}

enum EventKind { connected, disconnected, peerJoined, peerLeft, warning, error, info }

class NetworkEvent {
  const NetworkEvent({
    required this.at,
    required this.kind,
    required this.title,
    this.detail,
  });

  final DateTime at;
  final EventKind kind;
  final String title;
  final String? detail;
}

class PortForward {
  const PortForward({required this.proto, required this.local, required this.remote});

  final String proto; // tcp | udp
  final String local; // 127.0.0.1:8080
  final String remote; // 10.144.0.2:80
}

class AclRule {
  const AclRule({
    required this.action, // allow | deny
    required this.protocol, // tcp | udp | icmp | any
    required this.chain, // inbound | outbound
    this.source = '0.0.0.0/0',
    this.destination = '0.0.0.0/0',
    this.ports = '',
    this.comment = '',
  });

  final String action;
  final String protocol;
  final String chain;
  final String source;
  final String destination;
  final String ports;
  final String comment;
}

/// A safe subset of EasyTier's 44-field network config, grouped exactly like the
/// four disclosure sections of the config screen. The FFI client serializes this
/// into the TOML/JSON the core expects; unknown fields stay out of the model
/// until the migration needs them.
class NetworkConfig {
  const NetworkConfig({
    required this.instanceName,
    required this.hostname,
    required this.networkName,
    this.networkSecret = '',
    this.dhcp = true,
    this.virtualIpv4 = '',
    this.networkLength = 24,
    this.peerUrls = const [],
    this.listenerUrls = const ['tcp://0.0.0.0:11010', 'udp://0.0.0.0:11010'],
    this.disableEncryption = false,
    this.disableIpv6 = false,
    this.mtu,
    this.latencyFirst = false,
    this.multiThread = true,
    this.devName = '',
    this.useSmoltcp = false,
    this.bindDevice = true,
    this.noTun = false,
    this.enablePrivateMode = false,
    this.enableMagicDns = false,
    this.disableP2p = false,
    this.p2pOnly = false,
    this.relayAllPeerRpc = false,
    this.enableExitNode = false,
    this.proxyCidrs = const [],
    this.portForwards = const [],
    this.aclRules = const [],
  });

  final String instanceName;
  final String hostname;
  final String networkName;
  final String networkSecret;

  // Basic
  final bool dhcp;
  final String virtualIpv4;
  final int networkLength;
  final List<String> peerUrls;
  final List<String> listenerUrls;

  // Advanced
  final bool disableEncryption;
  final bool disableIpv6;
  final int? mtu;
  final bool latencyFirst;
  final bool multiThread;
  final String devName;
  final bool useSmoltcp;
  final bool bindDevice;
  final bool noTun;
  final bool enablePrivateMode;
  final bool enableMagicDns;
  final bool disableP2p;
  final bool p2pOnly;
  final bool relayAllPeerRpc;
  final bool enableExitNode;

  // Port forward / ACL
  final List<String> proxyCidrs;
  final List<PortForward> portForwards;
  final List<AclRule> aclRules;

  NetworkConfig copyWith({
    String? instanceName,
    String? hostname,
    String? networkName,
    String? networkSecret,
    bool? dhcp,
    String? virtualIpv4,
    int? networkLength,
    List<String>? peerUrls,
    List<String>? listenerUrls,
    bool? disableEncryption,
    bool? disableIpv6,
    int? mtu,
    bool? latencyFirst,
    bool? multiThread,
    String? devName,
    bool? useSmoltcp,
    bool? bindDevice,
    bool? noTun,
    bool? enablePrivateMode,
    bool? enableMagicDns,
    bool? disableP2p,
    bool? p2pOnly,
    bool? relayAllPeerRpc,
    bool? enableExitNode,
    List<String>? proxyCidrs,
    List<PortForward>? portForwards,
    List<AclRule>? aclRules,
  }) => NetworkConfig(
    instanceName: instanceName ?? this.instanceName,
    hostname: hostname ?? this.hostname,
    networkName: networkName ?? this.networkName,
    networkSecret: networkSecret ?? this.networkSecret,
    dhcp: dhcp ?? this.dhcp,
    virtualIpv4: virtualIpv4 ?? this.virtualIpv4,
    networkLength: networkLength ?? this.networkLength,
    peerUrls: peerUrls ?? this.peerUrls,
    listenerUrls: listenerUrls ?? this.listenerUrls,
    disableEncryption: disableEncryption ?? this.disableEncryption,
    disableIpv6: disableIpv6 ?? this.disableIpv6,
    mtu: mtu ?? this.mtu,
    latencyFirst: latencyFirst ?? this.latencyFirst,
    multiThread: multiThread ?? this.multiThread,
    devName: devName ?? this.devName,
    useSmoltcp: useSmoltcp ?? this.useSmoltcp,
    bindDevice: bindDevice ?? this.bindDevice,
    noTun: noTun ?? this.noTun,
    enablePrivateMode: enablePrivateMode ?? this.enablePrivateMode,
    enableMagicDns: enableMagicDns ?? this.enableMagicDns,
    disableP2p: disableP2p ?? this.disableP2p,
    p2pOnly: p2pOnly ?? this.p2pOnly,
    relayAllPeerRpc: relayAllPeerRpc ?? this.relayAllPeerRpc,
    enableExitNode: enableExitNode ?? this.enableExitNode,
    proxyCidrs: proxyCidrs ?? this.proxyCidrs,
    portForwards: portForwards ?? this.portForwards,
    aclRules: aclRules ?? this.aclRules,
  );

  NetworkConfig withDefaultsForNewInstance(int index) => copyWith(
    instanceName: instanceName.isEmpty ? 'net-$index' : instanceName,
  );

  /// Short TOML preview shown in the config screen's "effective config" sheet.
  /// The authoritative serialization lives in the Rust bridge; this is for
  /// human readback only.
  String debugToml() {
    final b = StringBuffer()
      ..writeln('instance_name = "$instanceName"')
      ..writeln('hostname = "$hostname"')
      ..writeln('network_name = "$networkName"')
      ..writeln('network_secret = "${networkSecret.isEmpty ? '<unset>' : '***'}"')
      ..writeln('dhcp = $dhcp');
    if (!dhcp) b.writeln('ipv4 = "$virtualIpv4/$networkLength"');
    b.writeln('listeners = [${listenerUrls.map((u) => '"$u"').join(', ')}]');
    if (peerUrls.isNotEmpty) {
      b.writeln('peers = [${peerUrls.map((u) => '"$u"').join(', ')}]');
    }
    b
      ..writeln('disable_encryption = $disableEncryption')
      ..writeln('latency_first = $latencyFirst');
    if (mtu != null) b.writeln('mtu = $mtu');
    return b.toString();
  }
}

class NetworkInstance {
  const NetworkInstance({
    required this.id,
    required this.config,
    this.enabled = false,
    this.source = 'user',
  });

  final String id;
  final NetworkConfig config;
  final bool enabled;

  /// `user` | `web` | `legacy` — where the persisted config came from.
  final String source;

  NetworkInstance copyWith({NetworkConfig? config, bool? enabled}) =>
      NetworkInstance(
        id: id,
        config: config ?? this.config,
        enabled: enabled ?? this.enabled,
        source: source,
      );
}

/// Formats a byte rate for display. Data text is mono, but the formatter is
/// shared so all screens agree on the unit.
String formatRate(int bytesPerSecond) {
  if (bytesPerSecond < 1024) return '$bytesPerSecond B/s';
  final kb = bytesPerSecond / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB/s';
  final mb = kb / 1024;
  return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB/s';
}

String formatUptime(Duration d) {
  if (d.inSeconds < 60) return '${d.inSeconds}s';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

/// Builds a 60s rolling window of samples with plausible jitter, used by the
/// mock client and the design-preview tests.
List<TrafficSample> seedTrafficHistory({
  required int baseRx,
  required int baseTx,
  int points = 60,
  int seed = 7,
  DateTime? now,
}) {
  final random = math.Random(seed);
  final end = now ?? DateTime.now();
  return List.generate(points, (i) {
    final wave = 0.6 + 0.4 * math.sin(i / 6 + seed);
    return TrafficSample(
      at: end.subtract(Duration(seconds: points - i)),
      rxBps: (baseRx * wave * (0.85 + random.nextDouble() * 0.3)).round(),
      txBps: (baseTx * (1.15 - wave) * (0.85 + random.nextDouble() * 0.3)).round(),
    );
  });
}
