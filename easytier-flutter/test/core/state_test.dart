import 'package:easytier_flutter/core/client/mock_core_client.dart';
import 'package:easytier_flutter/core/models/models.dart';
import 'package:easytier_flutter/core/state/app_state.dart';
import 'package:easytier_flutter/core/ui/et_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mock core + AppState', () {
    late AppState state;

    setUp(() async {
      state = AppState(
        client: MockCoreClient(startDelay: Duration.zero),
        pollInterval: const Duration(days: 1),
      );
      await state.bootstrap();
    });

    tearDown(() => state.dispose());

    test('boots with one configured network and stopped status', () {
      expect(state.initialized, isTrue);
      expect(state.instances, hasLength(1));
      expect(state.activeId, isNotNull);
      expect(state.status.phase, ConnectionPhase.stopped);
      expect(state.connected, isFalse);
    });

    test('connect moves to connected, emits events and fills peers', () async {
      await state.connect();
      expect(state.status.phase, ConnectionPhase.connected);
      expect(state.status.peers, isNotEmpty);
      expect(state.events.any((e) => e.kind == EventKind.connected), isTrue);

      // Status snapshots include the offline peer: offline peers are never hidden.
      expect(state.status.peers.any((p) => !p.online), isTrue);
      expect(state.status.rxBps, greaterThan(0));
    });

    test('disconnect returns to stopped and emits a disconnected event', () async {
      await state.connect();
      await state.disconnect();
      expect(state.status.phase, ConnectionPhase.stopped);
      expect(state.events.any((e) => e.kind == EventKind.disconnected), isTrue);
    });

    test('saveConfig persists into the instance list', () async {
      final updated = state.activeConfig!.copyWith(networkName: 'renamed-net');
      final saved = await state.saveConfig(updated);
      expect(saved, isTrue);
      expect(state.activeConfig!.networkName, 'renamed-net');
    });

    test('validateConfig returns a specific error instead of throwing', () async {
      final invalid = state.activeConfig!.copyWith(networkName: '');
      expect(await state.validateConfig(invalid), contains('Network name'));
      expect(await state.validateConfig(state.activeConfig!), isNull);
    });

    test('unseen event badge clears when Activity is opened', () async {
      await state.connect();
      expect(state.unseenEvents, greaterThan(0));

      state.setDestination(EtDestination.activity);
      expect(state.unseenEvents, 0);

      // Background events do not raise the badge while Activity is in front.
      await state.disconnect();
      expect(state.unseenEvents, 0);
    });

    test('theme mode defaults to system and toggles dark/light', () {
      expect(state.themeMode, ThemeMode.system);
      state.toggleTheme();
      expect(state.themeMode, ThemeMode.dark);
      state.toggleTheme();
      expect(state.themeMode, ThemeMode.light);
    });
  });

  group('model formatting', () {
    test('rates use the shared formatter', () {
      expect(formatRate(512), '512 B/s');
      expect(formatRate(2048), '2.0 KB/s');
      expect(formatRate(5 * 1024 * 1024), '5.0 MB/s');
    });

    test('uptime is compact', () {
      expect(formatUptime(const Duration(seconds: 42)), '42s');
      expect(formatUptime(const Duration(minutes: 90)), '1h 30m');
    });

    test('peer path label never returns an empty string', () {
      const p = Peer(id: 'x', hostname: 'h', ipv4: '10.0.0.1', path: 'lost');
      expect(p.pathLabel, isNotEmpty);
    });
  });
}
