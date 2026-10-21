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
  test('serialise → parse round-trips every editable field', () {
    final toml = networkConfigToToml(_full);
    final result = parseNetworkConfigToml(toml, base: _full);

    expect(result.errors, isEmpty, reason: result.errors.map((e) => e.message).join('\n'));
    expect(result.warnings, isEmpty);
    expect(configEquals(result.config!, _full), isTrue);
    expect(toml, contains('[[port_forward]]'));
    expect(toml, contains('[[acl_rule]]'));
    expect(toml, contains('proxy_networks'));
  });

  test('missing keys keep the base draft values', () {
    const base = NetworkConfig(
      instanceName: 'old',
      hostname: 'old-host',
      networkName: 'Old Net',
      latencyFirst: true,
    );
    final result = parseNetworkConfigToml(
      'network_name = "New Net"\nmtu = 1280\n',
      base: base,
    );

    expect(result.ok, isTrue);
    final config = result.config!;
    expect(config.networkName, 'New Net');
    expect(config.instanceName, 'old');
    expect(config.hostname, 'old-host');
    expect(config.latencyFirst, isTrue);
    expect(config.mtu, 1280);
  });

  test('unknown keys are warnings, not errors', () {
    final result = parseNetworkConfigToml(
      'network_name = "N"\nthis_is_not_real = 1\n',
      base: _full,
    );

    expect(result.ok, isTrue);
    expect(result.warnings.single.line, 2);
    expect(result.warnings.single.message, contains('this_is_not_real'));
  });

  test('syntax errors name the offending line and block the result', () {
    final result = parseNetworkConfigToml(
      'network_name = "N"\nmtu = not-a-number\n',
      base: _full,
    );

    expect(result.ok, isFalse);
    expect(result.errors.single.line, 2);
    expect(result.config, isNull);
  });

  test('multi-line arrays and comments parse', () {
    final result = parseNetworkConfigToml(
      'peers = [\n  "tcp://a:11010", # primary\n  "udp://b:11010",\n]\n',
      base: _full,
    );

    expect(result.ok, isTrue);
    expect(result.config!.peerUrls, ['tcp://a:11010', 'udp://b:11010']);
  });

  test('ipv4 parses address and prefix together', () {
    final result = parseNetworkConfigToml(
      'ipv4 = "10.9.0.7/20"\n',
      base: _full,
    );

    expect(result.ok, isTrue);
    expect(result.config!.virtualIpv4, '10.9.0.7');
    expect(result.config!.networkLength, 20);
  });
}
