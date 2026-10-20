import 'dart:async';

import 'package:easytier_flutter/app.dart';
import 'package:easytier_flutter/core/client/core_client.dart';
import 'package:easytier_flutter/core/client/mock_core_client.dart';
import 'package:easytier_flutter/core/models/models.dart';
import 'package:easytier_flutter/core/state/app_state.dart';
import 'package:easytier_flutter/core/theme/theme.dart';
import 'package:easytier_flutter/core/ui/et_shell.dart';
import 'package:easytier_flutter/features/home/home_page.dart';
import 'package:easytier_flutter/features/home/home_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_app.dart';

/// Pins every status snapshot to one phase so each render state is testable.
class _PhaseClient extends MockCoreClient {
  _PhaseClient(this.status) : super(startDelay: Duration.zero);

  final InstanceStatus status;

  @override
  Future<InstanceStatus> collectStatus(String id) async => status;
}

/// Holds `runInstance` until the gate opens so the connecting UI can be
/// asserted deterministically instead of raced against the mock's timer.
class _GatedClient extends MockCoreClient {
  _GatedClient() : super(startDelay: Duration.zero);

  final gate = Completer<void>();

  @override
  Future<String> runInstance(NetworkConfig config) async {
    await gate.future;
    return super.runInstance(config);
  }
}

/// Mock core that boots without a seeded instance, for the empty state.
class _EmptyClient extends MockCoreClient {
  _EmptyClient() : super(startDelay: Duration.zero);

  @override
  Future<void> init() async {}
}

Future<AppState> _pumpWith(
  WidgetTester tester,
  CoreClient client, {
  Size size = const Size(390, 844),
  double pixelRatio = 2.0,
  bool connect = false,
}) async {
  tester.view.physicalSize = size * pixelRatio;
  tester.view.devicePixelRatio = pixelRatio;
  addTearDown(tester.view.reset);

  final state = AppState(client: client, pollInterval: null);
  addTearDown(state.dispose);
  await tester.pumpWidget(EasytierApp(state: state));
  await pumpFrames(tester);
  if (connect) {
    final pending = state.connect();
    await pumpFrames(tester, frames: 12);
    await pending;
    await pumpFrames(tester);
  }
  return state;
}

Finder _inHome(Finder finder) => find.descendant(
      of: find.byType(HomePage),
      matching: finder,
    );

InstanceStatus _connectedStatus() => InstanceStatus(
      instanceId: 'inst-1',
      phase: ConnectionPhase.connected,
      virtualIp: '10.144.0.18',
      latencyMs: 18,
      peerCount: 6,
      routeCount: 6,
      rxBps: 820000,
      txBps: 160000,
      uptime: const Duration(minutes: 134),
      peers: const [
        Peer(id: 'p1', hostname: 'nas', ipv4: '10.144.0.4', path: 'direct', latencyMs: 8),
        Peer(id: 'p2', hostname: 'macbook', ipv4: '10.144.0.6', path: 'direct', latencyMs: 14),
        Peer(id: 'p3', hostname: 'homeserver', ipv4: '10.144.0.9', path: 'direct', latencyMs: 21),
        Peer(id: 'p4', hostname: 'shenzhen-edge', ipv4: '10.144.0.12', path: 'relay', relayVia: 'nas', latencyMs: 58),
        Peer(id: 'p5', hostname: 'laptop-old', ipv4: '10.144.0.15', path: 'direct', latencyMs: 9),
        Peer(id: 'p6', hostname: 'pi-lab', ipv4: '10.144.0.18', path: 'lost', online: false),
      ],
      history: seedTrafficHistory(baseRx: 820000, baseTx: 160000, points: 60),
    );

List<Peer> _relayOnlyPeers() => const [
      Peer(
        id: 'p1',
        hostname: 'shenzhen-edge',
        ipv4: '10.144.0.12',
        path: 'relay',
        relayVia: 'nas',
        latencyMs: 58,
      ),
      Peer(
        id: 'p2',
        hostname: 'pi-lab',
        ipv4: '10.144.0.18',
        path: 'lost',
        online: false,
      ),
    ];

void main() {
  setUpAll(loadEtFonts);
  testWidgets('connected Home shows signal, hero latency and one action',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpPhoneApp(tester);

    expect(_inHome(find.text('Connected')), findsOneWidget);
    expect(_inHome(find.text('Latency')), findsOneWidget);
    expect(_inHome(find.text('Connected to EasyTier Home')), findsOneWidget);
    expect(_inHome(find.text('Disconnect')), findsOneWidget);
    expect(_inHome(find.text('Connect')), findsNothing);
    expect(_inHome(find.text('Virtual IP')), findsOneWidget);
    expect(_inHome(find.textContaining('10.144.0.')), findsWidgets);
    expect(_inHome(find.text('Traffic')), findsOneWidget);
    expect(_inHome(find.text('last 60 s')), findsOneWidget);
    expect(_inHome(find.text('Down')), findsOneWidget);
    expect(_inHome(find.text('Up')), findsOneWidget);
    expect(_inHome(find.text('5 of 6 online')), findsOneWidget);
    // Top three by latency, plus the offline peer: offline peers are never hidden.
    expect(_inHome(find.text('nas')), findsOneWidget);
    expect(_inHome(find.text('laptop-old')), findsOneWidget);
    expect(_inHome(find.text('pi-lab')), findsOneWidget);
    // The hero number is machine data and is announced as milliseconds.
    expect(
      find.bySemanticsLabel(RegExp(r'^Latency \d+ milliseconds$')),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('stopped Home keeps the traffic card honest', (tester) async {
    final state = await pumpPhoneApp(tester, connect: false);
    expect(state.status.phase, ConnectionPhase.stopped);

    expect(_inHome(find.text('Not running')), findsOneWidget);
    expect(_inHome(find.text('Not connected')), findsOneWidget);
    expect(_inHome(find.text('Connect')), findsOneWidget);
    expect(_inHome(find.text('Disconnect')), findsNothing);
    expect(_inHome(find.text('Traffic starts when you connect.')), findsOneWidget);
    expect(_inHome(find.text('0 peers')), findsOneWidget);
    expect(_inHome(find.text('—')), findsWidgets);
  });

  testWidgets('connecting Home breathes and disables the action', (tester) async {
    final client = _GatedClient();
    final state = await _pumpWith(tester, client);

    final pending = state.connect();
    await pumpFrames(tester, frames: 4);

    expect(_inHome(find.text('Connecting')), findsOneWidget);
    expect(_inHome(find.text('Connecting to EasyTier Home…')), findsOneWidget);
    expect(_inHome(find.text('Waiting for the tunnel…')), findsOneWidget);
    // M3 loading button: label stays next to an inline spinner, action disabled.
    expect(_inHome(find.text('Connecting…')), findsOneWidget);
    expect(_inHome(find.byType(CircularProgressIndicator)), findsOneWidget);
    expect(
      tester.widget<FilledButton>(_inHome(find.byType(FilledButton))).onPressed,
      isNull,
    );

    client.gate.complete();
    await pumpFrames(tester, frames: 12);
    await pending;
    await pumpFrames(tester);
    expect(_inHome(find.text('Disconnect')), findsOneWidget);
  });

  testWidgets('degraded Home shows the relay-only banner', (tester) async {
    final client = _PhaseClient(
      InstanceStatus(
        instanceId: 'inst-1',
        phase: ConnectionPhase.degraded,
        virtualIp: '10.144.0.9',
        latencyMs: 55,
        peerCount: 2,
        routeCount: 2,
        rxBps: 120000,
        txBps: 4000,
        uptime: const Duration(minutes: 134),
        peers: _relayOnlyPeers(),
        history: seedTrafficHistory(baseRx: 120000, baseTx: 4000, points: 30),
      ),
    );
    await _pumpWith(tester, client, connect: true);

    expect(_inHome(find.text('Degraded — relay only')), findsOneWidget);
    expect(_inHome(find.text('Relay-only path')), findsOneWidget);
    expect(
      _inHome(find.text(
        'All online peers are reached through a relay. Direct paths are unavailable right now.',
      )),
      findsOneWidget,
    );
    expect(_inHome(find.text('55')), findsOneWidget);
    expect(_inHome(find.text('1 of 2 online')), findsOneWidget);
    expect(_inHome(find.text('Disconnect')), findsOneWidget);
  });

  testWidgets('error Home explains the cause and offers Reconnect',
      (tester) async {
    const message = 'TUN device could not be created (permission denied).';
    final client = _PhaseClient(
      const InstanceStatus(
        instanceId: 'inst-1',
        phase: ConnectionPhase.error,
        error: message,
      ),
    );
    await _pumpWith(tester, client);

    expect(_inHome(find.text('Disconnected')), findsOneWidget);
    expect(_inHome(find.text('Reconnect')), findsOneWidget);
    expect(_inHome(find.text(message)), findsOneWidget);
    // Both the signal sentence and the banner title name the failure.
    expect(_inHome(find.text('Connection failed')), findsNWidgets(2));
  });

  testWidgets('no instance Home offers Add network and creates one',
      (tester) async {
    final state = await _pumpWith(tester, _EmptyClient());
    expect(state.instances, isEmpty);

    expect(_inHome(find.text('No networks yet')), findsOneWidget);
    expect(_inHome(find.text('Add network')), findsOneWidget);

    await tester.tap(_inHome(find.text('Add network')));
    await pumpFrames(tester, frames: 12);

    expect(state.instances, hasLength(1));
    expect(_inHome(find.text('Connect')), findsOneWidget);
  });

  testWidgets('Home never overflows at 320px', (tester) async {
    tester.view.physicalSize = const Size(320, 640) * 2.0;
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    // Scoped harness: pump the real HomePage composition (EtPage + tokens)
    // without the shell, so an offstage tab cannot fail this check.
    final state = AppState(
      client: _PhaseClient(_connectedStatus()),
      pollInterval: null,
    );
    addTearDown(state.dispose);
    state.instances = const [
      NetworkInstance(
        id: 'inst-1',
        config: NetworkConfig(
          instanceName: 'office-mesh',
          hostname: 'chance-desktop',
          networkName: 'EasyTier Home',
        ),
      ),
    ];
    state.activeId = 'inst-1';
    state.status = _connectedStatus();

    await tester.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildEtTheme(brightness: Brightness.dark),
          home: const Scaffold(body: HomePage()),
        ),
      ),
    );
    await pumpFrames(tester);

    expect(tester.takeException(), isNull);
    expect(_inHome(find.text('Latency')), findsOneWidget);
  });

  testWidgets('desktop Home uses the two-column grid', (tester) async {
    await pumpDesktopApp(tester);

    final hero = tester.getTopLeft(find.byType(HomeHero));
    final traffic = tester.getTopLeft(find.byType(HomeTrafficCard));
    expect(traffic.dx, greaterThan(hero.dx));
    expect((traffic.dy - hero.dy).abs(), lessThan(1));
    // Navigation stays on the rail at desktop width.
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('Home header names the active network', (tester) async {
    await pumpPhoneApp(tester);

    final page = tester.widget<EtPage>(_inHome(find.byType(EtPage)));
    expect(page.title, 'Home');
    expect(page.subtitle, 'EasyTier Home');
  });
}
