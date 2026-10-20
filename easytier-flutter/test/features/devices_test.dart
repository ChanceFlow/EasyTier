import 'dart:async';

import 'package:easytier_flutter/app.dart';
import 'package:easytier_flutter/core/client/core_client.dart';
import 'package:easytier_flutter/core/models/models.dart';
import 'package:easytier_flutter/core/state/app_state.dart';
import 'package:easytier_flutter/core/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_app.dart';

/// Devices screen: grouped peer table, search, sort, detail sheet, responsive
/// table layout and the empty/degraded states. All list assertions exercise the
/// real app (shell + AppState), only the transport is scripted where the mock
/// cannot express the state under test (no peers, relay-only, 60 peers).

const NetworkConfig _testConfig = NetworkConfig(
  instanceName: 'net-1',
  hostname: 'test-host',
  networkName: 'Test Mesh',
);

class _StaticClient implements CoreClient {
  _StaticClient({required this.status});

  InstanceStatus status;
  final StreamController<NetworkEvent> _events = StreamController<NetworkEvent>.broadcast();

  @override
  Future<void> init() async {}

  @override
  Future<List<NetworkInstance>> listInstances() async => [
        const NetworkInstance(id: 'inst-1', config: _testConfig, enabled: true),
      ];

  @override
  Future<String> runInstance(NetworkConfig config) async => 'inst-1';

  @override
  Future<void> stopInstance(String id) async => status = InstanceStatus.stopped;

  @override
  Future<void> deleteInstance(String id) async {}

  @override
  Future<void> saveConfig(NetworkConfig config) async {}

  @override
  Future<NetworkConfig?> getConfig(String id) async => _testConfig;

  @override
  Future<String?> validateConfig(NetworkConfig config) async => null;

  @override
  Future<InstanceStatus> collectStatus(String id) async => status;

  @override
  Future<String> version() async => '2.7.0-test';

  @override
  Stream<NetworkEvent> get events => _events.stream;

  @override
  Future<void> dispose() async => _events.close();
}

/// Runs [body] against a booted app, then removes the tree and disposes the
/// store. Disposing inside the test body is required: `flutter_test` asserts no
/// pending timers at the end of each test body, and `AppState` owns a poll timer.
Future<void> _runWithApp(
  WidgetTester tester,
  Future<void> Function(AppState state) body, {
  bool connect = true,
  bool desktop = false,
  CoreClient? client,
  Size size = const Size(390, 844),
}) async {
  final AppState state;
  if (client == null) {
    // `pumpPhoneApp` registers its own disposal; tests never pumpAndSettle here
    // because honest loading indicators may never settle (project convention).
    state = desktop
        ? await pumpDesktopApp(tester, connect: false)
        : await pumpPhoneApp(tester, size: size, connect: false);
  } else {
    tester.view.physicalSize = size * 2.0;
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    state = AppState(client: client, pollInterval: null);
    addTearDown(state.dispose);
    await tester.pumpWidget(EasytierApp(state: state));
    await pumpFrames(tester);
  }
  if (connect) {
    await state.connect();
    await pumpFrames(tester, frames: 12);
  }
  await body(state);
}

List<Peer> _peers(int count) => [
      for (var i = 0; i < count; i++)
        Peer(
          id: 'p$i',
          hostname: 'node-${i.toString().padLeft(2, '0')}',
          ipv4: '10.144.0.${i + 2}',
          path: i % 7 == 0 ? 'relay' : 'direct',
          relayVia: 'node-00',
          latencyMs: 5 + i,
        ),
    ];

void main() {
  setUpAll(loadEtFonts);

  group('Devices', () {
    testWidgets('groups online first and keeps offline peers visible', (tester) async {
      await _runWithApp(tester, (state) async {
        await openDestination(tester, EtDestination.devices);

        expect(find.text('5 of 6 online · 6 routes'), findsOneWidget);
        expect(find.text('Online · 5'), findsOneWidget);
        expect(find.text('Offline · 1'), findsOneWidget);

        // The offline peer is never dropped from the table.
        expect(find.text('pi-lab'), findsOneWidget);
        expect(find.text('offline'), findsOneWidget);
        expect(find.byType(EtPeerRow), findsNWidgets(6));

        // Online rows sit above the offline group; latency sorts within groups.
        final onlineHeader = tester.getTopLeft(find.text('Online · 5')).dy;
        final offlineHeader = tester.getTopLeft(find.text('Offline · 1')).dy;
        expect(offlineHeader, greaterThan(onlineHeader));
        expect(
          tester.getTopLeft(find.text('nas')).dy,
          lessThan(tester.getTopLeft(find.text('macbook')).dy),
        );
      });
    });

    testWidgets('not connected shows the connect empty state and connects', (tester) async {
      await _runWithApp(
        tester,
        (state) async {
          await openDestination(tester, EtDestination.devices);

          expect(find.text('Not connected'), findsOneWidget);
          expect(find.text('Connect to see peers'), findsOneWidget);

          await tester.tap(find.text('Connect'));
          await pumpFrames(tester, frames: 16);

          expect(state.connected, isTrue);
          expect(find.text('nas'), findsOneWidget);
          expect(find.text('5 of 6 online · 6 routes'), findsOneWidget);
        },
        connect: false,
      );
    });

    testWidgets('connected with no peers shows the "No peers yet" empty state', (tester) async {
      final client = _StaticClient(
        status: const InstanceStatus(
          instanceId: 'inst-1',
          phase: ConnectionPhase.connected,
          peerCount: 0,
          routeCount: 0,
        ),
      );
      await _runWithApp(
        tester,
        (state) async {
          await openDestination(tester, EtDestination.devices);
          expect(find.text('No peers yet'), findsOneWidget);
          expect(find.byType(EtPeerRow), findsNothing);
        },
        client: client,
      );
    });

    testWidgets('relay-only network shows the degraded banner', (tester) async {
      final client = _StaticClient(
        status: const InstanceStatus(
          instanceId: 'inst-1',
          phase: ConnectionPhase.degraded,
          peerCount: 1,
          routeCount: 2,
          latencyMs: 58,
          peers: [
            Peer(
              id: 'p1',
              hostname: 'edge',
              ipv4: '10.144.0.7',
              path: 'relay',
              relayVia: 'nas',
              latencyMs: 58,
            ),
          ],
        ),
      );
      await _runWithApp(
        tester,
        (state) async {
          await openDestination(tester, EtDestination.devices);
          expect(find.text('All peers are relayed'), findsOneWidget);
          expect(find.text('edge'), findsOneWidget);
        },
        client: client,
      );
    });

    testWidgets('search filters by hostname and IP, and reports no matches', (tester) async {
      await _runWithApp(tester, (state) async {
        await openDestination(tester, EtDestination.devices);
        await tester.tap(find.byTooltip('Search devices'));
        await pumpFrames(tester, frames: 16);
        expect(find.byType(SearchBar), findsOneWidget);

        await tester.enterText(find.byKey(const Key('devices-search-field')), 'nas');
        await pumpFrames(tester, frames: 16);
        expect(find.widgetWithText(EtPeerRow, 'nas'), findsOneWidget);
        expect(find.widgetWithText(EtPeerRow, 'macbook'), findsNothing);

        await tester.enterText(find.byKey(const Key('devices-search-field')), '10.144.0.18');
        await pumpFrames(tester, frames: 16);
        expect(find.widgetWithText(EtPeerRow, 'pi-lab'), findsOneWidget);
        expect(find.widgetWithText(EtPeerRow, 'nas'), findsNothing);

        await tester.enterText(find.byKey(const Key('devices-search-field')), 'zzz');
        await pumpFrames(tester, frames: 16);
        expect(find.text('No devices match'), findsOneWidget);
        expect(find.text('Clear search'), findsOneWidget);

        await tester.tap(find.text('Clear search'));
        await pumpFrames(tester, frames: 16);
        expect(find.widgetWithText(EtPeerRow, 'nas'), findsOneWidget);
        expect(find.text('No devices match'), findsNothing);
      });
    });

    testWidgets('tapping a peer opens the detail sheet and copies the IP', (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );

      await _runWithApp(tester, (state) async {
        await openDestination(tester, EtDestination.devices);
        await tester.tap(find.text('nas'));
        await pumpFrames(tester, frames: 16);

        // Sheet facts: identity, address, path, latency, last seen.
        expect(find.text('10.144.0.4'), findsWidgets);
        expect(find.text('Path'), findsOneWidget);
        expect(find.text('Latency'), findsOneWidget);
        expect(find.text('Last seen'), findsOneWidget);
        expect(find.text('Copy IP'), findsOneWidget);

        await tester.tap(find.text('Copy IP'));
        await pumpFrames(tester, frames: 16);

        expect(find.text('Copied 10.144.0.4'), findsOneWidget);
        final copy = calls.lastWhere((call) => call.method == 'Clipboard.setData');
        expect((copy.arguments as Map)['text'], '10.144.0.4');
      });
    });

    testWidgets('desktop uses an M3 DataTable with sortable columns', (tester) async {
      await _runWithApp(
        tester,
        (state) async {
          await openDestination(tester, EtDestination.devices);

          // Wide windows use Material's table, not hand-rolled column geometry.
          expect(find.byType(DataTable), findsOneWidget);
          expect(find.text('Status'), findsOneWidget);
          expect(find.text('Device'), findsOneWidget);
          expect(find.text('Path'), findsOneWidget);
          expect(find.text('Latency'), findsOneWidget);

          // Group headers stay visible as table section rows.
          expect(find.text('Online · 5'), findsOneWidget);
          expect(find.text('Offline · 1'), findsOneWidget);
          expect(find.text('nas'), findsOneWidget);
          expect(find.text('pi-lab'), findsOneWidget);
          expect(find.byType(EtPeerRow), findsNothing);
        },
        desktop: true,
      );
    });

    testWidgets('long peer lists are virtualized and keep their scroll offset', (tester) async {
      final client = _StaticClient(
        status: InstanceStatus(
          instanceId: 'inst-1',
          phase: ConnectionPhase.connected,
          peerCount: 60,
          routeCount: 61,
          latencyMs: 12,
          peers: _peers(60),
        ),
      );
      await _runWithApp(
        tester,
        (state) async {
          await openDestination(tester, EtDestination.devices);

          // Virtualized: the 60-peer mesh never builds all rows at once.
          expect(find.text('node-00'), findsOneWidget);
          expect(find.text('node-59'), findsNothing);
          expect(find.byType(EtPeerRow).evaluate().length, lessThan(60));

          await tester.drag(find.byType(ListView), const Offset(0, -600));
          await pumpFrames(tester, frames: 16);
          final before = tester
              .state<ScrollableState>(find.byType(Scrollable).first)
              .position
              .pixels;
          expect(before, greaterThan(0));

          // Tab switches must not rebuild the screen or reset the list.
          await openDestination(tester, EtDestination.home);
          await openDestination(tester, EtDestination.devices);
          final after = tester
              .state<ScrollableState>(find.byType(Scrollable).first)
              .position
              .pixels;
          expect(after, before);
        },
        client: client,
      );
    });

    testWidgets('phone layout survives a 320px viewport with search open', (tester) async {
      await _runWithApp(
        tester,
        (state) async {
          await openDestination(tester, EtDestination.devices);
          await tester.tap(find.byTooltip('Search devices'));
          await pumpFrames(tester, frames: 16);
          await tester.enterText(find.byKey(const Key('devices-search-field')), '10.144');
          await pumpFrames(tester, frames: 16);
          expect(find.text('nas'), findsOneWidget);
        },
        size: const Size(320, 640),
      );
    });
  });
}
