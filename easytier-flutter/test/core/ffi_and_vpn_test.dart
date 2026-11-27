import 'dart:async';
import 'dart:convert';

import 'package:easytier_flutter/core/client/core_client.dart';
import 'package:easytier_flutter/core/client/ffi/ffi_core_client.dart';
import 'package:easytier_flutter/core/models/models.dart';
import 'package:easytier_flutter/core/state/app_state.dart';
import 'package:easytier_flutter/core/vpn/vpn_controller.dart';
import 'package:easytier_flutter/core/vpn/vpn_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _ScriptedTunClient implements CoreClient, TunFdCapable {
  _ScriptedTunClient({required this.config});

  final NetworkConfig config;
  final _events = StreamController<NetworkEvent>.broadcast();

  String id = 'inst-1';
  InstanceStatus nextStatus = const InstanceStatus(
    instanceId: 'inst-1',
    phase: ConnectionPhase.stopped,
  );
  int runCalls = 0;
  int stopCalls = 0;
  final List<int> attachedFds = <int>[];
  Object? setTunFdError;

  @override
  Future<void> init() async {}

  @override
  Future<List<NetworkInstance>> listInstances() async => [
    NetworkInstance(id: id, config: config, enabled: true),
  ];

  @override
  Future<String> runInstance(NetworkConfig config) async {
    runCalls++;
    return id;
  }

  @override
  Future<void> stopInstance(String id) async {
    stopCalls++;
    nextStatus = InstanceStatus(instanceId: id, phase: ConnectionPhase.stopped);
  }

  @override
  Future<void> deleteInstance(String id) async {}

  @override
  Future<void> saveConfig(NetworkConfig config, {String? instanceId}) async {}

  @override
  Future<NetworkConfig?> getConfig(String id) async => config;

  @override
  Future<String?> validateConfig(NetworkConfig config) async => null;

  @override
  Future<InstanceStatus> collectStatus(String id) async => nextStatus;

  @override
  Future<String> version() async => '2.6.4-test';

  @override
  Stream<NetworkEvent> get events => _events.stream;

  @override
  Future<void> setTunFd(String instanceId, int fd) async {
    if (setTunFdError != null) throw setTunFdError!;
    attachedFds.add(fd);
  }

  void emitConnectedEvent(String detail) {
    _events.add(
      NetworkEvent(
        at: DateTime.now(),
        kind: EventKind.connected,
        title: 'Tunnel up',
        detail: detail,
      ),
    );
  }

  @override
  Future<void> dispose() async => _events.close();
}

int _ipv4Int(int a, int b, int c, int d) =>
    (a << 24) | (b << 16) | (c << 8) | d;

void main() {
  group('FfiCoreClient status and event decoding', () {
    test('parses my_node_info.virtual_ipv4 for static IP configs', () {
      final client = FfiCoreClient();
      const config = NetworkConfig(
        instanceName: 'redmi',
        hostname: 'redmi',
        networkName: 'mynet',
        dhcp: false,
        virtualIpv4: '10.144.0.10',
        networkLength: 24,
        proxyCidrs: ['192.168.100.0/24'],
      );

      final status = client.statusFromRunningInfo('inst-1', config, {
        'running': true,
        'error_msg': null,
        'my_node_info': {
          'peer_id': 2539797991,
          'virtual_ipv4': {
            'address': {'addr': _ipv4Int(10, 144, 0, 10)},
            'network_length': 24,
          },
          'hostname': 'redmi',
        },
        'routes': [
          {
            'peer_id': 3888771881,
            'ipv4_addr': {
              'address': {'addr': _ipv4Int(10, 144, 0, 1)},
              'network_length': 24,
            },
            'cost': 1,
            'next_hop_peer_id': 3888771881,
            'hostname': 'server',
            'proxy_cidrs': ['172.16.0.0/16', '192.168.100.0/24'],
          },
        ],
        'peer_route_pairs': [
          {
            'route': {
              'peer_id': 3888771881,
              'ipv4_addr': {
                'address': {'addr': _ipv4Int(10, 144, 0, 1)},
                'network_length': 24,
              },
              'cost': 1,
              'next_hop_peer_id': 3888771881,
              'hostname': 'server',
              'proxy_cidrs': ['172.16.0.0/16', '192.168.100.0/24'],
            },
            'peer': {
              'peer_id': 3888771881,
              'conns': [
                {
                  'is_closed': false,
                  'stats': {'latency_us': 14200, 'rx_bytes': 100, 'tx_bytes': 200},
                },
              ],
            },
          },
          {
            'route': {
              'peer_id': 4007161797,
              'ipv4_addr': {
                'address': {'addr': _ipv4Int(10, 144, 0, 5)},
                'network_length': 24,
              },
              'cost': 2,
              'next_hop_peer_id': 3888771881,
              'path_latency': 42,
              'hostname': 'nas',
              'proxy_cidrs': [],
            },
            'peer': null,
          },
        ],
      });

      expect(status.phase, ConnectionPhase.connected);
      expect(status.virtualIp, '10.144.0.10');
      expect(status.virtualIpPrefixLength, 24);
      expect(status.virtualIpCidr, '10.144.0.10/24');
      expect(status.peers, hasLength(2));
      expect(status.peers[0].hostname, 'server');
      expect(status.peers[0].latencyMs, 14);
      expect(status.peers[1].hostname, 'nas');
      expect(status.peers[1].path, 'relay');
      expect(status.peers[1].relayVia, 'server');
      expect(status.peers[1].latencyMs, 42);
      // Excludes local proxyCidrs (`192.168.100.0/24`), keeps remote peer cidrs.
      expect(status.remoteProxyCidrs, ['172.16.0.0/16']);
    });

    test('ignores zero addr=0 and parses dhcp_ip_changed with prefix', () async {
      final client = FfiCoreClient();
      const dhcpConfig = NetworkConfig(
        instanceName: 'net-1',
        hostname: 'phone',
        networkName: 'mynet',
        dhcp: true,
      );

      final before = client.statusFromRunningInfo('inst-1', dhcpConfig, {
        'running': true,
        'my_node_info': {
          'virtual_ipv4': {
            'address': {'addr': 0},
            'network_length': 0,
          },
        },
        'peer_route_pairs': const [],
      });
      expect(before.phase, ConnectionPhase.connecting);
      expect(before.virtualIp, isNull);

      final events = <NetworkEvent>[];
      final sub = client.events.listen(events.add);
      addTearDown(sub.cancel);

      client.processNativeEvent({
        'instance_id': 'inst-1',
        'instance_name': 'net-1',
        'event': 'dhcp_ip_changed',
        'detail': jsonEncode({'old': null, 'new': '10.144.0.17/20'}),
      });
      await Future<void>.delayed(Duration.zero);

      final after = client.statusFromRunningInfo('inst-1', dhcpConfig, {
        'running': true,
        'my_node_info': {},
        'peer_route_pairs': const [],
      });
      expect(after.phase, ConnectionPhase.connected);
      expect(after.virtualIp, '10.144.0.17');
      expect(after.virtualIpPrefixLength, 20);
      expect(after.virtualIpCidr, '10.144.0.17/20');
      expect(events.single.kind, EventKind.connected);
      await client.dispose();
    });
  });

  group('AppState + Android VpnController orchestration', () {
    test('static IP starts VPN with CIDR prefix, subnet route, and setTunFd', () async {
      const config = NetworkConfig(
        instanceName: 'redmi',
        hostname: 'redmi',
        networkName: 'mynet',
        dhcp: false,
        virtualIpv4: '10.144.0.10',
        networkLength: 24,
        enableMagicDns: true,
        proxyCidrs: ['192.168.50.0/24'],
      );
      final client = _ScriptedTunClient(config: config)
        ..nextStatus = const InstanceStatus(
          instanceId: 'inst-1',
          phase: ConnectionPhase.connected,
          virtualIp: '10.144.0.10',
          virtualIpPrefixLength: 24,
          remoteProxyCidrs: ['172.16.0.0/16'],
        );
      final vpnService = FakeVpnService();
      final vpn = VpnController(service: vpnService);
      final state = AppState(
        client: client,
        vpn: vpn,
        pollInterval: null,
        virtualIpPollInterval: const Duration(milliseconds: 10),
      );
      addTearDown(state.dispose);

      await state.bootstrap();
      await state.connect();

      expect(state.lastError, isNull);
      expect(state.status.phase, ConnectionPhase.connected);
      expect(vpnService.prepareCalls, greaterThanOrEqualTo(1));
      expect(vpnService.startCalls, 1);
      expect(vpnService.lastRequest!.ipv4Cidr, '10.144.0.10/24');
      expect(vpnService.lastRequest!.dns, ['100.100.100.101']);
      expect(vpnService.lastRequest!.routes, [
        '10.144.0.0/24',
        '100.100.100.101/32',
        '172.16.0.0/16',
      ]);
      expect(client.attachedFds, [42]);
    });

    test('DHCP waits for delayed lease and reconciles new remote routes', () async {
      const config = NetworkConfig(
        instanceName: 'net-1',
        hostname: 'phone',
        networkName: 'mynet',
        dhcp: true,
      );
      final client = _ScriptedTunClient(config: config)
        ..nextStatus = const InstanceStatus(
          instanceId: 'inst-1',
          phase: ConnectionPhase.connecting,
        );
      final vpnService = FakeVpnService();
      final vpn = VpnController(service: vpnService);
      final state = AppState(
        client: client,
        vpn: vpn,
        pollInterval: null,
        virtualIpPollInterval: const Duration(milliseconds: 20),
        dhcpVirtualIpTimeout: const Duration(seconds: 2),
      );
      addTearDown(state.dispose);

      await state.bootstrap();
      final connecting = state.connect();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(state.busy, isTrue);

      client.nextStatus = const InstanceStatus(
        instanceId: 'inst-1',
        phase: ConnectionPhase.connected,
        virtualIp: '10.144.0.19',
        virtualIpPrefixLength: 24,
      );
      client.emitConnectedEvent('10.144.0.19 · net-1');
      await connecting;

      expect(state.lastError, isNull);
      expect(state.status.phase, ConnectionPhase.connected);
      expect(vpnService.lastRequest!.ipv4Cidr, '10.144.0.19/24');
      expect(vpnService.lastRequest!.routes, ['10.144.0.0/24']);
      expect(client.attachedFds, [42]);

      // Later peer joins advertising a new proxy CIDR -> VPN routes reconcile.
      client.nextStatus = const InstanceStatus(
        instanceId: 'inst-1',
        phase: ConnectionPhase.connected,
        virtualIp: '10.144.0.19',
        virtualIpPrefixLength: 24,
        remoteProxyCidrs: ['10.20.0.0/16'],
      );
      await state.refresh();
      expect(vpnService.startCalls, 2);
      expect(vpnService.lastRequest!.routes, ['10.144.0.0/24', '10.20.0.0/16']);
      expect(client.attachedFds, [42, 43]);
    });

    test('missing virtual IP stops core instance and leaves connecting to error', () async {
      const config = NetworkConfig(
        instanceName: 'net-1',
        hostname: 'phone',
        networkName: 'mynet',
        dhcp: true,
      );
      final client = _ScriptedTunClient(config: config)
        ..nextStatus = const InstanceStatus(
          instanceId: 'inst-1',
          phase: ConnectionPhase.connecting,
        );
      final vpnService = FakeVpnService();
      final vpn = VpnController(service: vpnService);
      final state = AppState(
        client: client,
        vpn: vpn,
        pollInterval: null,
        virtualIpPollInterval: const Duration(milliseconds: 10),
        dhcpVirtualIpTimeout: const Duration(milliseconds: 50),
      );
      addTearDown(state.dispose);

      await state.bootstrap();
      await state.connect();

      expect(client.runCalls, 1);
      expect(client.stopCalls, 1);
      expect(vpnService.startCalls, 0);
      expect(state.busy, isFalse);
      expect(state.status.phase, ConnectionPhase.error);
      expect(state.lastError, isNotNull);
    });

    test('declined VPN consent does not start core instance', () async {
      const config = NetworkConfig(
        instanceName: 'redmi',
        hostname: 'redmi',
        networkName: 'mynet',
        dhcp: false,
        virtualIpv4: '10.144.0.10',
      );
      final client = _ScriptedTunClient(config: config);
      final vpnService = FakeVpnService(consentGranted: false);
      final vpn = VpnController(service: vpnService);
      final state = AppState(
        client: client,
        vpn: vpn,
        pollInterval: null,
      );
      addTearDown(state.dispose);

      await state.bootstrap();
      await state.connect();

      expect(client.runCalls, 0);
      expect(state.status.phase, ConnectionPhase.error);
      expect(state.lastError, contains('VPN permission was declined'));
    });

    test('setTunFd failure cleans up VPN and stops core instance', () async {
      const config = NetworkConfig(
        instanceName: 'redmi',
        hostname: 'redmi',
        networkName: 'mynet',
        dhcp: false,
        virtualIpv4: '10.144.0.10',
      );
      final client = _ScriptedTunClient(config: config)
        ..setTunFdError = StateError('boom')
        ..nextStatus = const InstanceStatus(
          instanceId: 'inst-1',
          phase: ConnectionPhase.connected,
          virtualIp: '10.144.0.10',
          virtualIpPrefixLength: 24,
        );
      final vpnService = FakeVpnService();
      final vpn = VpnController(service: vpnService);
      final state = AppState(
        client: client,
        vpn: vpn,
        pollInterval: null,
        virtualIpPollInterval: const Duration(milliseconds: 10),
      );
      addTearDown(state.dispose);

      await state.bootstrap();
      await state.connect();

      expect(vpnService.stopCalls, 1);
      expect(client.stopCalls, 1);
      expect(state.status.phase, ConnectionPhase.error);
      expect(state.lastError, contains('setTunFd'));
    });

    test('noTun skips Android VpnService completely', () async {
      const config = NetworkConfig(
        instanceName: 'redmi',
        hostname: 'redmi',
        networkName: 'mynet',
        dhcp: false,
        virtualIpv4: '10.144.0.10',
        noTun: true,
      );
      final client = _ScriptedTunClient(config: config)
        ..nextStatus = const InstanceStatus(
          instanceId: 'inst-1',
          phase: ConnectionPhase.connected,
          virtualIp: '10.144.0.10',
          virtualIpPrefixLength: 24,
        );
      final vpnService = FakeVpnService();
      final vpn = VpnController(service: vpnService);
      final state = AppState(
        client: client,
        vpn: vpn,
        pollInterval: null,
      );
      addTearDown(state.dispose);

      await state.bootstrap();
      await state.connect();

      expect(vpnService.prepareCalls, 0);
      expect(vpnService.startCalls, 0);
      expect(client.attachedFds, isEmpty);
      expect(state.status.phase, ConnectionPhase.connected);
    });
  });
}
