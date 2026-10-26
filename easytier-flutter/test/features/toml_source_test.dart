import 'package:easytier_flutter/core/models/models.dart';
import 'package:easytier_flutter/features/config/config_validation.dart';
import 'package:easytier_flutter/features/config/toml_source.dart';
import 'package:flutter_test/flutter_test.dart';

const _full = NetworkConfig(
  instanceName: 'office-mesh',
  hostname: 'chance-desktop',
  networkName: 'EasyTier Home',
  networkSecret: 's3cret "quoted" \\ value',
  dhcp: false,
  virtualIpv4: '10.144.0.2',
  networkLength: 24,
  peerUrls: ['tcp://public.easytier.top:11010', 'udp://relay.example:11010'],
  listenerUrls: ['tcp://0.0.0.0:11010', 'udp://0.0.0.0:11010'],
  disableEncryption: true,
  disableIpv6: true,
  mtu: 1380,
  latencyFirst: true,
  multiThread: false,
  devName: 'et0',
  useSmoltcp: true,
  bindDevice: false,
  noTun: true,
  enablePrivateMode: true,
  enableMagicDns: true,
  disableP2p: true,
  p2pOnly: true,
  relayAllPeerRpc: true,
  enableExitNode: true,
  proxyCidrs: ['192.168.0.0/16', '10.0.0.0/8'],
  portForwards: [
    PortForward(proto: 'tcp', local: '127.0.0.1:8080', remote: '10.144.0.9:80'),
    PortForward(proto: 'udp', local: '127.0.0.1:5353', remote: '10.144.0.4:53'),
  ],
  aclRules: [
    AclRule(
      action: 'allow',
      protocol: 'tcp',
      chain: 'inbound',
      source: '10.144.0.0/24',
      destination: '10.144.0.2',
      ports: '80,443',
      comment: 'web only',
    ),
    AclRule(action: 'deny', protocol: 'any', chain: 'outbound'),
  ],
);

void main() {
  test('canonical schema round-trips every editable field', () {
    final toml = encodeConfigToml(_full, instanceId: 'inst-1');
    // Canonical core schema, not the flat UI preview.
    expect(toml, contains('[network_identity]'));
    expect(toml, contains('[[peer]]'));
    expect(toml, contains('[[proxy_network]]'));
    expect(toml, contains('[[port_forward]]'));
    expect(toml, contains('bind_addr ='));
    expect(toml, contains('[flags]'));
    expect(toml, contains('enable_encryption = false'));
    expect(toml, contains('[[acl.acl_v1.chains]]'));
    expect(toml, contains('[[acl.acl_v1.chains.rules]]'));
    expect(toml, contains('instance_id = "inst-1"'));

    final result = parseConfigToml(toml, base: _full);
    expect(result.errors, isEmpty, reason: result.errors.map((e) => e.message).join('\n'));
    expect(result.hasUnsupportedFields, isFalse);
    expect(result.instanceId, 'inst-1');
    expect(configEquals(result.config!, _full), isTrue);
  });

  test('missing fields keep the base draft values', () {
    const base = NetworkConfig(
      instanceName: 'old',
      hostname: 'old-host',
      networkName: 'Old Net',
      latencyFirst: true,
    );
    final result = parseConfigToml(
      'instance_name = "new"\n[network_identity]\nnetwork_name = "New Net"\n[flags]\nmtu = 1280\n',
      base: base,
    );

    expect(result.ok, isTrue);
    final config = result.config!;
    expect(config.instanceName, 'new');
    expect(config.networkName, 'New Net');
    expect(config.hostname, 'old-host');
    expect(config.latencyFirst, isTrue);
    expect(config.mtu, 1280);
  });

  test('fields the UI cannot model block Apply instead of being dropped', () {
    final result = parseConfigToml(
      'routes = ["10.0.0.0/8 via 0.0.0.0"]\n',
      base: _full,
    );

    expect(result.ok, isTrue);
    expect(result.hasUnsupportedFields, isTrue);
    expect(result.unsupported.single.message, contains('routes'));
  });

  test('syntax errors name the offending line and block the result', () {
    final result = parseConfigToml('mtu = not-a-number\n', base: _full);

    expect(result.ok, isFalse);
    expect(result.errors.single.line, 1);
    expect(result.config, isNull);
  });

  test('multi-line arrays and comments parse in canonical form', () {
    final result = parseConfigToml(
      'listeners = [\n  "tcp://a:11010", # primary\n  "udp://b:11010",\n]\n[network_identity]\nnetwork_name = "N"\n',
      base: _full,
    );

    expect(result.ok, isTrue);
    expect(result.config!.listenerUrls, ['tcp://a:11010', 'udp://b:11010']);
  });

  test('canonical port forwards and ACL chains parse', () {
    final result = parseConfigToml(
      '''
[network_identity]
network_name = "N"
[[port_forward]]
bind_addr = "127.0.0.1:8080"
dst_addr = "10.144.0.9:80"
proto = "udp"
[[acl.acl_v1.chains]]
chain_type = 1
[[acl.acl_v1.chains.rules]]
action = 2
protocol = 1
source_ips = ["10.0.0.0/8"]
destination_ips = ["10.144.0.2"]
ports = ["80", "443"]
description = "block"
''',
      base: _full,
    );

    expect(result.ok, isTrue);
    final config = result.config!;
    expect(config.portForwards.single.proto, 'udp');
    expect(config.portForwards.single.local, '127.0.0.1:8080');
    expect(config.aclRules.single.action, 'deny');
    expect(config.aclRules.single.protocol, 'tcp');
    expect(config.aclRules.single.chain, 'inbound');
    expect(config.aclRules.single.ports, '80,443');
  });

  test('ipv4 parses address and prefix together', () {
    final result = parseConfigToml('ipv4 = "10.9.0.7/20"\n', base: _full);
    expect(result.ok, isTrue);
    expect(result.config!.virtualIpv4, '10.9.0.7');
    expect(result.config!.networkLength, 20);
  });
}
