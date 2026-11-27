import 'dart:async';
import 'dart:io';

import 'package:easytier_flutter/core/client/core_client.dart';
import 'package:easytier_flutter/core/client/ffi/ffi_core_client.dart';
import 'package:easytier_flutter/core/models/models.dart';
import 'package:easytier_flutter/core/state/app_state.dart';
import 'package:easytier_flutter/core/vpn/vpn_controller.dart';
import 'package:easytier_flutter/core/vpn/vpn_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression coverage for the "saved a network but Home still says No networks"
/// class of bugs, plus the storage-degradation contract.
class _EmptyThenSaveClient implements CoreClient {
  _EmptyThenSaveClient({this.failSaves = false});

  bool failSaves;

  /// Mirrors the FFI transport, which reports persisted-but-running instances
  /// with `enabled: true`.
  bool markEnabled = false;

  final Map<String, NetworkConfig> configs = <String, NetworkConfig>{};
  int _nextId = 1;
  int saveCalls = 0;
  int listCalls = 0;
  final StreamController<NetworkEvent> _events =
      StreamController<NetworkEvent>.broadcast();

  @override
  Future<void> init() async {}

  @override
  Future<List<NetworkInstance>> listInstances() async {
    listCalls++;
    return <NetworkInstance>[
      for (final entry in configs.entries)
        NetworkInstance(
          id: entry.key,
          config: entry.value,
          enabled: markEnabled,
        ),
    ];
  }

  @override
  Future<String> runInstance(NetworkConfig config) async {
    for (final entry in configs.entries) {
      if (entry.value.instanceName == config.instanceName) return entry.key;
    }
    return 'inst-runtime';
  }

  @override
  Future<void> stopInstance(String id) async {}

  @override
  Future<void> deleteInstance(String id) async {
    configs.remove(id);
  }

  @override
  Future<void> saveConfig(NetworkConfig config) async {
    saveCalls++;
    if (failSaves) {
      throw StateError('No writable configuration directory.');
    }
    final existing = configs.entries
        .where((entry) => entry.value.instanceName == config.instanceName)
        .toList();
    final id = existing.isEmpty ? 'inst-${_nextId++}' : existing.first.key;
    configs[id] = config;
  }

  @override
  Future<NetworkConfig?> getConfig(String id) async => configs[id];

  @override
  Future<String?> validateConfig(NetworkConfig config) async => null;

  @override
  Future<InstanceStatus> collectStatus(String id) async =>
      InstanceStatus(instanceId: id, phase: ConnectionPhase.stopped);

  @override
  Future<String> version() async => '2.6.4-test';

  @override
  Stream<NetworkEvent> get events => _events.stream;

  @override
  Future<void> dispose() async => _events.close();
}

/// Storage-aware transport that reports a persistent warning (the shape of a
/// sandbox with no writable directory).
class _StorageAwareClient extends _EmptyThenSaveClient
    implements StorageAwareCoreClient {
  _StorageAwareClient();

  @override
  String? get storageWarning => _warning;

  final String _warning = 'No writable configuration directory.';

  @override
  String? get configStorePath => null;
}

Future<AppState> _boot(CoreClient client) async {
  final state = AppState(client: client, pollInterval: null);
  await state.bootstrap();
  return state;
}

void main() {
  group('instance list recovery', () {
    test('saveConfig makes a network appear even when the list started empty',
        () async {
      final client = _EmptyThenSaveClient();
      final state = await _boot(client);
      addTearDown(state.dispose);

      expect(state.instances, isEmpty);
      expect(state.active, isNull);

      final saved = await state.saveConfig(
        const NetworkConfig(
          instanceName: 'redmi',
          hostname: 'redmi',
          networkName: 'mynet',
          dhcp: false,
          virtualIpv4: '10.144.0.10',
        ),
      );

      expect(saved, isTrue);
      expect(state.instances, hasLength(1));
      expect(state.activeId, isNotNull);
      expect(state.active!.config.instanceName, 'redmi');
      expect(state.active!.config.virtualIpv4, '10.144.0.10');
    });

    test('connect self-heals a stale instance list instead of doing nothing',
        () async {
      final client = _EmptyThenSaveClient();
      final state = await _boot(client);
      addTearDown(state.dispose);
      expect(state.instances, isEmpty);

      // Another engine (or the host) persisted a config after bootstrap.
      client.configs['inst-9'] = const NetworkConfig(
        instanceName: 'phone',
        hostname: 'phone',
        networkName: 'mynet',
        dhcp: false,
        virtualIpv4: '10.144.0.11',
      );

      await state.connect();

      expect(state.instances, hasLength(1));
      expect(state.activeId, 'inst-9');
      // No storage problem, so the previous "No network is configured yet"
      // message must not linger.
      expect(state.lastError, isNull);
    });

    test('connect without any network reports why it cannot start', () async {
      final client = _EmptyThenSaveClient();
      final state = await _boot(client);
      addTearDown(state.dispose);

      await state.connect();

      expect(state.lastError, contains('No network is configured'));
      expect(state.busy, isFalse);
    });

    test('a failed add keeps the UI alive and a later add succeeds', () async {
      final client = _EmptyThenSaveClient(failSaves: true);
      final state = await _boot(client);
      addTearDown(state.dispose);

      await state.addInstance();
      expect(state.instances, isEmpty);
      expect(state.lastError, contains('No writable configuration directory'));

      client.failSaves = false;
      await state.addInstance();
      expect(state.instances, hasLength(1));
      expect(state.activeId, isNotNull);
    });

    test('add after delete never reuses an existing instance name', () async {
      final client = _EmptyThenSaveClient();
      final state = await _boot(client);
      addTearDown(state.dispose);

      await state.addInstance();
      final first = state.instances.single;
      expect(first.config.instanceName, 'net-1');

      await state.addInstance();
      expect(
        state.instances.map((instance) => instance.config.instanceName),
        containsAll(<String>['net-1', 'net-2']),
      );

      await state.removeInstance(first.id);
      final remainingBefore = state.instances.length;
      await state.addInstance();

      final names =
          state.instances.map((instance) => instance.config.instanceName).toList();
      expect(state.instances, hasLength(remainingBefore + 1));
      expect(names.toSet(), hasLength(names.length),
          reason: 'instance names are unique keys in the core');
    });

    test('storage warning from the transport reaches the UI state', () async {
      final client = _StorageAwareClient();
      final state = await _boot(client);
      addTearDown(state.dispose);

      expect(state.storageWarning, contains('No writable'));
      expect(
        state.logs.entries.any(
          (entry) => entry.message.contains('Configuration storage'),
        ),
        isTrue,
      );
    });
  });

  group('native VPN reconciliation on boot', () {
    test('an orphaned system tunnel is torn down', () async {
      final client = _EmptyThenSaveClient();
      final service = FakeVpnService()..currentTunnel = const VpnTunnel(
        fd: 7,
        ipv4Cidr: '10.144.0.9/24',
      );
      final state = AppState(
        client: client,
        vpn: VpnController(service: service),
        pollInterval: null,
      );
      addTearDown(state.dispose);

      await state.bootstrap();

      expect(service.stopCalls, 1);
      expect(state.instances, isEmpty);
      expect(
        state.logs.entries.any(
          (entry) => entry.message.contains('orphaned system VPN tunnel'),
        ),
        isTrue,
      );
    });

    test('a tunnel backed by a running core instance is left alone', () async {
      final client = _EmptyThenSaveClient()
        ..markEnabled = true
        ..configs['inst-1'] = const NetworkConfig(
          instanceName: 'redmi',
          hostname: 'redmi',
          networkName: 'mynet',
          dhcp: false,
          virtualIpv4: '10.144.0.10',
        );
      final service = FakeVpnService()..currentTunnel = const VpnTunnel(
        fd: 8,
        ipv4Cidr: '10.144.0.10/24',
      );
      final state = AppState(
        client: client,
        vpn: VpnController(service: service),
        pollInterval: null,
      );
      addTearDown(state.dispose);

      await state.bootstrap();

      expect(service.stopCalls, 0);
      expect(state.instances, hasLength(1));
      expect(state.activeId, 'inst-1');
    });
  });

  group('store file decoding', () {
    test('reads persisted configurations keyed by instance id', () async {
      final directory = await Directory.systemTemp.createTemp('easytier_store');
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      final file = FfiCoreClient.storeFileIn(directory);
      await file.writeAsString('''
{
  "version": 1,
  "configs": [
    {
      "id": "inst-1",
      "config": {
        "instanceName": "redmi",
        "hostname": "redmi",
        "networkName": "mynet",
        "dhcp": false,
        "virtualIpv4": "10.144.0.10",
        "networkLength": 24
      }
    }
  ]
}
''');

      final entries = await FfiCoreClient.readStoreFile(file);

      expect(entries, hasLength(1));
      expect(entries.single.id, 'inst-1');
      expect(entries.single.config.instanceName, 'redmi');
      expect(entries.single.config.virtualIpv4, '10.144.0.10');
    });

    test('a missing file is empty, a corrupt file throws', () async {
      final directory = await Directory.systemTemp.createTemp('easytier_store');
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      final file = FfiCoreClient.storeFileIn(directory);

      expect(await FfiCoreClient.readStoreFile(file), isEmpty);

      await file.writeAsString('not json at all');
      await expectLater(
        FfiCoreClient.readStoreFile(file),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('config store probing', () {
    test('a writable directory passes the probe and is left clean', () async {
      final directory = await Directory.systemTemp.createTemp('easytier_probe');
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });

      await FfiCoreClient.probeWritableDirectory(directory);

      final leftovers = directory
          .listSync()
          .map((entry) => entry.path.split('/').last)
          .where((name) => name.contains('easytier_write_probe'));
      expect(leftovers, isEmpty);
    });

    test('a nested directory is created by the probe', () async {
      final parent = await Directory.systemTemp.createTemp('easytier_probe');
      addTearDown(() async {
        if (await parent.exists()) await parent.delete(recursive: true);
      });
      final nested = Directory('${parent.path}/a/b/c');

      await FfiCoreClient.probeWritableDirectory(nested);

      expect(await nested.exists(), isTrue);
    });

    test('an unwritable path is reported instead of silently accepted',
        () async {
      // /proc is a kernel pseudo-filesystem: creating a directory there always
      // fails, which is the exact failure mode the probing exists to catch.
      final unwritable = Directory('/proc/easytier_should_not_exist/sub');

      await expectLater(
        FfiCoreClient.probeWritableDirectory(unwritable),
        throwsA(isA<FileSystemException>()),
      );
    });
  });
}
