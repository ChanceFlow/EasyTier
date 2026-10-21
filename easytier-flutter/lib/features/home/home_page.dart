import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
          onPressed: () {
            EtHaptics.impact();
            unawaited(state.connect());
          },
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
          : SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                onPressed: () {
                  EtHaptics.impact();
                  unawaited(state.disconnect());
                },
                style: OutlinedButton.styleFrom(
                  shape: const StadiumBorder(),
                  side: BorderSide(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.22),
                  ),
                  foregroundColor: context.et.text,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.surface.withValues(alpha: 0.16),
                  textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                icon: const Icon(Symbols.power_settings_new, size: 18),
                label: const Text('Disconnect'),
              ),
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
      onOpenDevices: () => state.setDestination(EtDestination.devices),
    );

    final networkCard = HomeNetworkCard(
      instanceName: active.config.instanceName,
      networkName: networkName,
      virtualIp: virtualIp,
      up: up,
      onConfigure: () => state.setDestination(EtDestination.config),
      onCopyIp: virtualIp == null
          ? null
          : () async {
              EtHaptics.selection();
              await Clipboard.setData(ClipboardData(text: virtualIp));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Copied $virtualIp')),
              );
            },
    );

    final peersCard = HomePeersCard(
      peers: up ? status.peers : const [],
      up: up,
      onOpenDevices: () => state.setDestination(EtDestination.devices),
    );

    return EtPage(
      title: 'Home',
      subtitle: networkName,
      actions: [
        _NetworkSwitcherAction(
          instanceName: active.config.instanceName,
          onTap: () => _showNetworkSwitcherSheet(context, state),
        ),
      ],
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

  Future<void> _showNetworkSwitcherSheet(
    BuildContext context,
    AppState state,
  ) async {
    await showEtSheet<void>(
      context: context,
      builder: (sheetContext) {
        final p = sheetContext.et;
        final text = Theme.of(sheetContext).textTheme;
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            EtSpace.x4,
            EtSpace.x1,
            EtSpace.x4,
            EtSpace.x5,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: EtSpace.x2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Network profiles',
                        style: text.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: p.text,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        unawaited(state.addInstance());
                      },
                      icon: const Icon(Symbols.add, size: 18),
                      label: const Text('New'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: EtSpace.x2),
              for (final instance in state.instances)
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(EtRadius.lg),
                  ),
                  leading: EtAvatar(
                    name: instance.config.instanceName,
                    size: 38,
                  ),
                  title: Text(
                    instance.config.networkName,
                    style: text.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: p.text,
                    ),
                  ),
                  subtitle: Text(
                    instance.config.instanceName,
                    style: EtText.mono(size: EtType.caption, color: p.text2),
                  ),
                  trailing: instance.id == state.activeId
                      ? const EtBadge(
                          label: 'Active',
                          tone: EtTone.success,
                          icon: Symbols.check_circle,
                        )
                      : Icon(Symbols.chevron_right, color: p.text2),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    unawaited(state.selectInstance(instance.id));
                  },
                ),
              const SizedBox(height: EtSpace.x2),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  state.setDestination(EtDestination.config);
                },
                icon: const Icon(Symbols.tune, size: 18),
                label: const Text('Edit active configuration'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _NetworkSwitcherAction extends StatelessWidget {
  const _NetworkSwitcherAction({
    required this.instanceName,
    required this.onTap,
  });

  final String instanceName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.et;
    return Tooltip(
      message: 'Switch network',
      child: Material(
        color: p.scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(EtRadius.pill),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: EtSpace.x3,
              vertical: 6,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Symbols.lan, size: 15, color: p.accent),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 112),
                  child: Text(
                    instanceName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: EtText.mono(
                      size: EtType.caption,
                      weight: FontWeight.w500,
                      color: p.text,
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                Icon(Symbols.expand_more, size: 16, color: p.text2),
              ],
            ),
          ),
        ),
      ),
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
