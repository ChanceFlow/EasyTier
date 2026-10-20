import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/theme.dart';
import '../../core/ui/ui.dart';
import 'home_widgets.dart';

/// Which story Home is telling right now. Derived once per build so the hero,
/// the banner and the single action can never disagree with each other.
enum _HomeView { stopped, connecting, connected, degraded, error }

/// Home — the one screen that answers "is my network up?".
///
/// Google Material 3: an AppBar page with tonal cards, a status block
/// (signal → state line → large latency metric → supporting text), one M3
/// primary action, then network / traffic / peer summaries. A banner is the
/// only extra block, and only while the network is degraded or failed.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final active = state.active;
    if (active == null) return _NoNetworkHome(state: state);

    final status = state.status;
    final connecting = status.phase == ConnectionPhase.connecting ||
        (state.busy && !state.connected);
    final failed = !connecting &&
        (status.phase == ConnectionPhase.error ||
            (!status.phase.isUp && state.lastError != null));
    final view = connecting
        ? _HomeView.connecting
        : failed
            ? _HomeView.error
            : switch (status.phase) {
                ConnectionPhase.connected => _HomeView.connected,
                ConnectionPhase.degraded => _HomeView.degraded,
                _ => _HomeView.stopped,
              };

    final networkName = active.config.networkName;
    final up = status.phase.isUp;
    final latencyMs = up ? status.latencyMs : null;
    final virtualIp =
        (status.virtualIp?.isNotEmpty ?? false) ? status.virtualIp : null;

    final (EtSignalState signalState, String? signalLabel) = switch (view) {
      _HomeView.stopped => (EtSignalState.off, null),
      _HomeView.connecting => (EtSignalState.connecting, null),
      _HomeView.connected => (EtSignalState.connected, null),
      _HomeView.degraded => (EtSignalState.degraded, 'Degraded — relay only'),
      _HomeView.error => (EtSignalState.disconnected, null),
    };

    final stateLine = switch (view) {
      _HomeView.stopped => 'Not connected',
      _HomeView.connecting => 'Connecting to $networkName…',
      _HomeView.connected => 'Connected to $networkName',
      _HomeView.degraded => 'Connected to $networkName · relay path',
      _HomeView.error => 'Connection failed',
    };

    final Widget? banner = switch (view) {
      _HomeView.degraded => _degradedBanner(status),
      _HomeView.error => EtBanner(
          tone: EtTone.danger,
          title: 'Connection failed',
          message: status.error ??
              state.lastError ??
              'The core could not start this network.',
        ),
      _ => null,
    };

    // Exactly one M3 primary action for the whole screen. Filled for "bring it
    // up", tonal for "take it down" — never a second filled button.
    final Widget action = switch (view) {
      _HomeView.stopped => EtPrimaryButton(
          label: 'Connect',
          icon: Symbols.cable,
          onPressed: () => unawaited(state.connect()),
        ),
      _HomeView.connecting => const EtPrimaryButton(
          label: 'Connecting…',
          loading: true,
        ),
      _HomeView.error => EtPrimaryButton(
          label: 'Reconnect',
          icon: Symbols.refresh,
          onPressed: () => unawaited(state.connect()),
        ),
      _HomeView.connected || _HomeView.degraded => state.busy
          ? const EtPrimaryButton(
              label: 'Disconnecting…',
              tonal: true,
              loading: true,
            )
          : EtPrimaryButton(
              label: 'Disconnect',
              icon: Symbols.power_settings_new,
              onPressed: () => unawaited(state.disconnect()),
            ),
    };

    final trafficEmptyMessage = switch (view) {
      _HomeView.stopped => 'Traffic starts when you connect.',
      _HomeView.connecting => 'Waiting for the tunnel…',
      _HomeView.error => 'Traffic stopped.',
      _ => null,
    };

    final hero = HomeHero(
      signalState: signalState,
      signalLabel: signalLabel,
      latencyMs: latencyMs,
      stateLine: stateLine,
      uptimeLabel: up ? 'up ${formatUptime(status.uptime)}' : '—',
      action: action,
    );

    final stats = HomeStatsRow(
      up: up,
      onlinePeers: status.onlinePeers,
      peerCount: status.peers.isEmpty ? status.peerCount : status.peers.length,
      routeCount: status.routeCount,
      rxBps: status.rxBps,
    );

    final networkCard = HomeNetworkCard(
      instanceName: active.config.instanceName,
      networkName: networkName,
      virtualIp: virtualIp,
      up: up,
      onlinePeers: status.onlinePeers,
      peerCount: status.peers.isEmpty ? status.peerCount : status.peers.length,
      routeCount: status.routeCount,
    );

    final peersCard = HomePeersCard(peers: up ? status.peers : const [], up: up);

    return EtPage(
      title: 'Home',
      subtitle: networkName,
      child: EtScrollBody(
        children: [
          ?banner,
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 900;
              final trafficCard = HomeTrafficCard(
                history: status.history,
                rxBps: status.rxBps,
                txBps: status.txBps,
                emptyMessage: trafficEmptyMessage,
                graphHeight: wide ? 180 : 140,
              );

              if (!wide) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    hero,
                    const SizedBox(height: EtSpace.x3),
                    stats,
                    const SizedBox(height: EtSpace.x4),
                    trafficCard,
                    const SizedBox(height: EtSpace.x4),
                    peersCard,
                    const SizedBox(height: EtSpace.x4),
                    networkCard,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 5,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        hero,
                        const SizedBox(height: EtSpace.x3),
                        stats,
                        const SizedBox(height: EtSpace.x4),
                        networkCard,
                      ],
                    ),
                  ),
                  const SizedBox(width: EtSpace.x6),
                  Expanded(
                    flex: 5,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        trafficCard,
                        const SizedBox(height: EtSpace.x4),
                        peersCard,
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  EtBanner _degradedBanner(InstanceStatus status) {
    final online = status.peers.where((peer) => peer.online).toList();
    final relayOnly =
        online.isNotEmpty && online.every((peer) => peer.path == 'relay');
    return EtBanner(
      tone: EtTone.warn,
      title: relayOnly ? 'Relay-only path' : 'Network degraded',
      message: relayOnly
          ? 'All online peers are reached through a relay. Direct paths are unavailable right now.'
          : 'Some peers are unreachable or relayed. Open Devices for the per-peer paths.',
    );
  }
}

/// No instance at all: the only honest thing to show is the way to create one.
class _NoNetworkHome extends StatelessWidget {
  const _NoNetworkHome({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return EtPage(
      title: 'Home',
      subtitle: 'No network',
      child: EtScrollBody(
        top: EtSpace.x6,
        children: [
          EtEmptyState(
            icon: Symbols.gpp_bad,
            title: 'No networks yet',
            message: 'Add a network to start routing peers.',
            action: EtPrimaryButton(
              label: 'Add network',
              icon: Symbols.add,
              expanded: false,
              onPressed: () => unawaited(state.addInstance()),
            ),
          ),
        ],
      ),
    );
  }
}
