import 'dart:async';

import 'package:easytier_flutter/app.dart';
import 'package:easytier_flutter/core/client/core_client.dart';
import 'package:easytier_flutter/core/models/models.dart';
import 'package:easytier_flutter/core/state/app_state.dart';
import 'package:easytier_flutter/core/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_app.dart';

/// Activity screen: reverse-chronological day groups, semantic icons, filter
/// menu, local-only clear with confirmation, empty states and list virtualization.

const NetworkConfig _testConfig = NetworkConfig(
  instanceName: 'net-1',
  hostname: 'test-host',
  networkName: 'Test Mesh',
);

class _EventClient implements CoreClient {
  final StreamController<NetworkEvent> _events = StreamController<NetworkEvent>.broadcast();

  void emit(NetworkEvent event) => _events.add(event);

  @override
  Future<void> init() async {}

  @override
  Future<List<NetworkInstance>> listInstances() async => [
        const NetworkInstance(id: 'inst-1', config: _testConfig, enabled: true),
      ];

  @override
  Future<String> runInstance(NetworkConfig config) async => 'inst-1';

  @override
  Future<void> stopInstance(String id) async {}

  @override
  Future<void> deleteInstance(String id) async {}

  @override
  Future<void> saveConfig(NetworkConfig config) async {}

  @override
  Future<NetworkConfig?> getConfig(String id) async => _testConfig;

  @override
  Future<String?> validateConfig(NetworkConfig config) async => null;

  @override
  Future<InstanceStatus> collectStatus(String id) async =>
      const InstanceStatus(instanceId: 'inst-1', phase: ConnectionPhase.stopped);

  @override
  Future<String> version() async => '2.7.0-test';

  @override
  Stream<NetworkEvent> get events => _events.stream;

  @override
  Future<void> dispose() async => _events.close();
}

/// Boots the app against the default mock (or a scripted client), runs [body],
/// then tears the tree down and disposes the store so no poll timer survives the
/// test body (flutter_test asserts that per test).
Future<void> _runWithApp(
  WidgetTester tester,
  Future<void> Function(AppState state) body, {
  bool connect = true,
  CoreClient? client,
  Size size = const Size(390, 844),
}) async {
  final AppState state;
  if (client == null) {
    // `pumpPhoneApp` registers its own disposal; tests never pumpAndSettle here
    // because honest loading indicators may never settle (project convention).
    state = await pumpPhoneApp(tester, size: size, connect: false);
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

void main() {
  setUpAll(loadEtFonts);

  group('Activity', () {
    testWidgets('renders a reverse-chronological timeline grouped by day', (tester) async {
      await _runWithApp(tester, (state) async {
        await openDestination(tester, EtDestination.activity);

        expect(find.text('2 events'), findsOneWidget);
        expect(find.text('Today'), findsOneWidget);
        expect(find.text('Connecting to EasyTier Home'), findsOneWidget);
        expect(find.text('Connected to EasyTier Home'), findsOneWidget);

        // The connected event is the newest one, so it sits above "Connecting…".
        expect(
          tester.getTopLeft(find.text('Connected to EasyTier Home')).dy,
          lessThan(tester.getTopLeft(find.text('Connecting to EasyTier Home')).dy),
        );

        // Semantic icon for "connected" (the shell's selected tab uses a
        // different glyph, so this only matches the event row).
        expect(find.byIcon(Symbols.check_circle), findsOneWidget);

        // Machine time, right aligned and mono: HH:mm exists for every row.
        expect(find.textContaining(RegExp(r'^\d{2}:\d{2}$')), findsNWidgets(2));
      });
    });

    testWidgets('filter chips narrow the feed and offer a way back', (tester) async {
      await _runWithApp(tester, (state) async {
        await openDestination(tester, EtDestination.activity);

        await tester.tap(find.byKey(const Key('activity-filter-peers')));
        await pumpFrames(tester, frames: 16);

        expect(find.text('No peer events'), findsOneWidget);
        expect(find.text('Nothing in 2 events matches this filter.'), findsOneWidget);
        expect(find.text('0 of 2 events'), findsOneWidget);

        await tester.tap(find.text('Show all'));
        await pumpFrames(tester, frames: 16);
        expect(find.text('Connecting to EasyTier Home'), findsOneWidget);

        await tester.tap(find.byKey(const Key('activity-filter-warnings')));
        await pumpFrames(tester, frames: 16);
        expect(find.text('No warnings'), findsOneWidget);
      });
    });

    testWidgets('clear asks for confirmation and can be cancelled', (tester) async {
      await _runWithApp(tester, (state) async {
        await openDestination(tester, EtDestination.activity);

        await tester.tap(find.byKey(const Key('activity-clear')));
        await pumpFrames(tester, frames: 16);
        expect(find.text('Clear activity?'), findsOneWidget);
        expect(find.textContaining('local event timeline'), findsOneWidget);

        await tester.tap(find.text('Cancel'));
        await pumpFrames(tester, frames: 16);
        expect(find.text('Connecting to EasyTier Home'), findsOneWidget);
        expect(find.text('Activity cleared'), findsNothing);
      });
    });

    testWidgets('clear is local-only and leaves an honest empty state', (tester) async {
      await _runWithApp(tester, (state) async {
        await openDestination(tester, EtDestination.activity);

        await tester.tap(find.byKey(const Key('activity-clear')));
        await pumpFrames(tester, frames: 16);
        await tester.tap(find.byKey(const Key('activity-clear-confirm')));
        await pumpFrames(tester, frames: 16);

        expect(find.text('Activity cleared'), findsOneWidget);
        expect(find.textContaining('The core keeps its own logs'), findsOneWidget);
        expect(find.text('Connecting to EasyTier Home'), findsNothing);
        expect(find.text('0 events'), findsOneWidget);
        // The shell contract: AppState still owns the events; only the local
        // timeline hides the ones seen before the clear.
        expect(state.events, isNotEmpty);
      });
    });

    testWidgets('groups today and yesterday and shows local events while stopped', (tester) async {
      final client = _EventClient();
      await _runWithApp(
        tester,
        (state) async {
          final now = DateTime.now();
          client.emit(NetworkEvent(
            at: now,
            kind: EventKind.info,
            title: 'Mesh started',
            detail: 'net-1',
          ));
          client.emit(NetworkEvent(
            at: now.subtract(const Duration(days: 1)),
            kind: EventKind.peerJoined,
            title: 'nas joined',
            detail: '10.144.0.4',
          ));
          await pumpFrames(tester, frames: 16);

          await openDestination(tester, EtDestination.activity);

          // The core is not connected, yet the local feed is still shown.
          expect(find.text('Today'), findsOneWidget);
          expect(find.text('Yesterday'), findsOneWidget);
          expect(find.text('Mesh started'), findsOneWidget);
          expect(find.text('nas joined'), findsOneWidget);
          expect(find.byIcon(Symbols.person_add), findsOneWidget);
        },
        client: client,
        connect: false,
      );
    });

    testWidgets('long feeds are virtualized', (tester) async {
      final client = _EventClient();
      await _runWithApp(
        tester,
        (state) async {
          final now = DateTime.now();
          for (var i = 0; i < 120; i++) {
            client.emit(NetworkEvent(
              at: now.subtract(Duration(minutes: i)),
              kind: i.isEven ? EventKind.info : EventKind.peerJoined,
              title: 'event-$i',
            ));
          }
          await pumpFrames(tester, frames: 16);

          await openDestination(tester, EtDestination.activity);

          expect(find.text('event-0'), findsOneWidget);
          expect(find.text('event-119'), findsNothing);

          await tester.scrollUntilVisible(
            find.text('event-119'),
            600,
            scrollable: find.byType(Scrollable).first,
            maxScrolls: 40,
          );
          expect(find.text('event-119'), findsOneWidget);
        },
        client: client,
        connect: false,
      );
    });

    testWidgets('timeline survives a 320px viewport', (tester) async {
      await _runWithApp(
        tester,
        (state) async {
          await openDestination(tester, EtDestination.activity);
          expect(find.text('Today'), findsOneWidget);
        },
        size: const Size(320, 640),
      );
    });
  });
}
