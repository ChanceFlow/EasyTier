import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../../core/theme/theme.dart';
import '../../core/ui/ui.dart';

/// Expressive card header: one title, one quiet trailing meta.
class HomeCardHeader extends StatelessWidget {
  const HomeCardHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.et;
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: p.text,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// The hero: one large expressive surface (aurora aura + connection orb +
/// the single primary action). Everything else on Home is a supporting block.
class HomeHero extends StatelessWidget {
  const HomeHero({
    super.key,
    required this.signalState,
    required this.signalLabel,
    required this.latencyMs,
    required this.stateLine,
    required this.uptimeLabel,
    required this.action,
  });

  final EtSignalState signalState;
  final String? signalLabel;

  /// `null` whenever the tunnel is not up: the hero shows an em dash instead of
  /// a stale number.
  final int? latencyMs;

  final String stateLine;
  final String uptimeLabel;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final p = context.et;
    final text = Theme.of(context).textTheme;
    final reduced = context.etReducedMotion;
    final value = latencyMs == null ? '—' : '$latencyMs';
    final semantics = latencyMs == null
        ? 'Latency unavailable'
        : 'Latency $latencyMs milliseconds';

    final (tone, icon, defaultLabel) = switch (signalState) {
      EtSignalState.connected => (EtTone.success, Symbols.check_circle, 'Connected'),
      EtSignalState.connecting => (EtTone.info, Symbols.sync, 'Connecting'),
      EtSignalState.degraded => (EtTone.warn, Symbols.warning, 'Degraded'),
      EtSignalState.disconnected => (EtTone.danger, Symbols.link_off, 'Disconnected'),
      EtSignalState.off => (EtTone.neutral, Symbols.radio_button_unchecked, 'Not running'),
    };
    final statusText = signalLabel ?? defaultLabel;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(EtRadius.hero),
        border: Border.all(color: p.scheme.primary.withValues(alpha: 0.22)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Expressive aurora: layered radial glows over a tonal base. Screen
          // blending keeps the colour vivid on dark; on light it would wash
          // out, so the painter switches to source-over with lower alpha.
          Positioned.fill(
            child: CustomPaint(
              painter: _AuroraPainter(
                base: p.isDark
                    ? Color.alphaBlend(
                        p.scheme.primary.withValues(alpha: 0.10),
                        const Color(0xFF0E0D12),
                      )
                    : p.scheme.surfaceContainerLow,
                primary: EtAccent.blue,
                tertiary: EtAccent.violet,
                success: EtAccent.cyan,
                dark: p.isDark,
                intensity: switch (signalState) {
                  EtSignalState.connected => 1.0,
                  EtSignalState.connecting => 0.85,
                  EtSignalState.degraded => 0.7,
                  _ => 0.40,
                },
              ),
            ),
          ),
          // Top inner highlight (1px glass edge) for depth.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Container(
                height: 1,
                color: p.scheme.onSurface.withValues(alpha: 0.16),
              ),
            ),
          ),
          // Calm lower half so text and the action always sit on a stable tone.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.55, 1.0],
                  colors: [
                    Colors.transparent,
                    p.scheme.surfaceContainerHigh.withValues(alpha: 0.10),
                    p.scheme.surfaceContainerHigh.withValues(alpha: 0.34),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(EtSpace.x5, EtSpace.x4, EtSpace.x5, EtSpace.x5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      EtBadge(label: statusText, tone: tone, icon: icon),
                      const Spacer(),
                      Text(
                        uptimeLabel,
                        style: EtText.mono(size: EtType.caption, color: p.text2),
                      ),
                    ],
                  ),
                  const SizedBox(height: EtSpace.x2),
                  Center(child: EtConnectionOrb(state: signalState, size: 112)),
                  const SizedBox(height: EtSpace.x1),
                  Center(
                    child: Text(
                      stateLine,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleLarge?.copyWith(
                        color: p.text,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: EtSpace.x2),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Latency',
                          style: text.labelLarge?.copyWith(color: p.text2),
                        ),
                        Semantics(
                          label: semantics,
                          child: ExcludeSemantics(
                            child: AnimatedSwitcher(
                              duration: reduced ? Duration.zero : EtDuration.base,
                              switchInCurve: EtCurves.spring,
                              switchOutCurve: EtCurves.exit,
                              child: Row(
                                key: ValueKey<String>(value),
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Text(
                                    value,
                                    style: EtText.mono(
                                      size: EtType.expressive,
                                      weight: FontWeight.w700,
                                      color: latencyMs == null ? p.text2 : p.text,
                                      height: 1.05,
                                    ),
                                  ),
                                  if (latencyMs != null) ...[
                                    const SizedBox(width: EtSpace.x2),
                                    Text(
                                      'ms',
                                      style: text.titleMedium?.copyWith(color: p.text2),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (latencyMs != null)
                          Text(
                            'to nearest peer',
                            style: text.bodySmall?.copyWith(color: p.text2),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: EtSpace.x4),
                  action,
                ],
              ),
            ),
        ],
      ),
    );
  }
}



/// Layered radial aurora used behind the hero content.
class _AuroraPainter extends CustomPainter {
  const _AuroraPainter({
    required this.base,
    required this.primary,
    required this.tertiary,
    required this.success,
    required this.dark,
    required this.intensity,
  });

  final Color base;
  final Color primary;
  final Color tertiary;
  final Color success;
  final bool dark;
  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = base);
    // On dark surfaces screen blending makes the glow luminous; on light it
    // would clip to white, so paint normally with calmer alphas.
    final blend = dark ? BlendMode.screen : BlendMode.srcOver;
    final boost = (dark ? 1.0 : 0.55) * intensity;

    void blob(Offset center, double radius, Color color, double alpha) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..blendMode = blend
          ..shader = RadialGradient(
            colors: [color.withValues(alpha: alpha * boost), color.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }

    blob(Offset(size.width * 0.08, size.height * 0.06), size.width * 0.72, primary, 0.95);
    blob(Offset(size.width * 0.98, size.height * 0.55), size.width * 0.80, tertiary, 0.85);
    blob(Offset(size.width * 0.95, size.height * 0.02), size.width * 0.34, success, 0.34);
    blob(Offset(size.width * 0.05, size.height * 0.92), size.width * 0.46, tertiary, 0.45);
    // Fine top highlight for depth.
    blob(Offset(size.width * 0.5, -size.height * 0.14), size.width * 0.7, primary, dark ? 0.28 : 0.16);
  }

  @override
  bool shouldRepaint(_AuroraPainter old) =>
      old.base != base || old.primary != primary || old.tertiary != tertiary ||
      old.success != success || old.dark != dark || old.intensity != intensity;
}

/// Three tonal bento stats under the hero.
class HomeStatsRow extends StatelessWidget {
  const HomeStatsRow({
    super.key,
    required this.up,
    required this.onlinePeers,
    required this.peerCount,
    required this.routeCount,
    required this.rxBps,
  });

  final bool up;
  final int onlinePeers;
  final int peerCount;
  final int routeCount;
  final int rxBps;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: EtStatTile(
            label: 'Peers',
            value: up ? '$onlinePeers / $peerCount' : '—',
            icon: Symbols.devices,
            tone: up ? EtTone.accent : EtTone.neutral,
          ),
        ),
        const SizedBox(width: EtSpace.x3),
        Expanded(
          child: EtStatTile(
            label: 'Routes',
            value: up ? '$routeCount' : '—',
            icon: Symbols.alt_route,
            tone: up ? EtTone.warn : EtTone.neutral,
          ),
        ),
        const SizedBox(width: EtSpace.x3),
        Expanded(
          child: EtStatTile(
            label: 'Downlink',
            value: up ? formatRate(rxBps) : '—',
            icon: Symbols.arrow_downward,
            tone: up ? EtTone.success : EtTone.neutral,
          ),
        ),
      ],
    );
  }
}

/// Identity + counts of the selected network, as M3 list rows on a card.
class HomeNetworkCard extends StatelessWidget {
  const HomeNetworkCard({
    super.key,
    required this.instanceName,
    required this.networkName,
    required this.virtualIp,
    required this.up,
    required this.onlinePeers,
    required this.peerCount,
    required this.routeCount,
  });

  final String instanceName;
  final String networkName;
  final String? virtualIp;
  final bool up;
  final int onlinePeers;
  final int peerCount;
  final int routeCount;

  @override
  Widget build(BuildContext context) {
    final p = context.et;
    return EtSurface(
      padding: const EdgeInsets.fromLTRB(0, EtSpace.x4, 0, EtSpace.x2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: EtSpace.x4),
            child: HomeCardHeader(title: 'Network'),
          ),
          const SizedBox(height: EtSpace.x1),
          _DetailTile(label: 'Virtual IP', value: virtualIp ?? '—', mono: true),
          _DetailTile(label: 'Instance', value: instanceName, mono: true),
          _DetailTile(label: 'Network', value: networkName),
          Divider(height: 1, indent: EtSpace.x4, endIndent: EtSpace.x4, color: p.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              EtSpace.x4,
              EtSpace.x4,
              EtSpace.x4,
              EtSpace.x2,
            ),
            child: Row(
              children: [
                Expanded(
                  child: EtKpi(
                    label: 'Peers online',
                    value: up ? '$onlinePeers / $peerCount' : '—',
                  ),
                ),
                Expanded(
                  child: EtKpi(
                    label: 'Routes',
                    value: up ? '$routeCount' : '—',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One `ListTile` data row: label on the left, mono/UI value right-aligned.
class _DetailTile extends StatelessWidget {
  const _DetailTile({required this.label, required this.value, this.mono = false});

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final p = context.et;
    final text = Theme.of(context).textTheme;
    return ListTile(
      dense: true,
      minVerticalPadding: 0,
      contentPadding: const EdgeInsets.symmetric(horizontal: EtSpace.x4),
      title: Text(label, style: text.bodyMedium?.copyWith(color: p.text2)),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 176),
        child: Text(
          value,
          textAlign: TextAlign.end,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: mono
              ? EtText.mono(size: EtType.bodySm, color: p.text)
              : text.bodyMedium?.copyWith(color: p.text),
        ),
      ),
    );
  }
}

/// Rolling traffic. The chart sits in its own tonal well so it reads as a data
/// surface, not as decoration.
class HomeTrafficCard extends StatelessWidget {
  const HomeTrafficCard({
    super.key,
    required this.history,
    required this.rxBps,
    required this.txBps,
    required this.emptyMessage,
    this.graphHeight = 140,
  });

  final List<TrafficSample> history;
  final int rxBps;
  final int txBps;

  /// `null` means live; otherwise the placeholder sentence for the phase.
  final String? emptyMessage;
  final double graphHeight;

  @override
  Widget build(BuildContext context) {
    final p = context.et;
    final text = Theme.of(context).textTheme;
    final live = emptyMessage == null;
    return EtSurface(
      padding: const EdgeInsets.all(EtSpace.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HomeCardHeader(
            title: 'Traffic',
            trailing: live
                ? Text(
                    'last 60 s',
                    style: text.bodySmall?.copyWith(color: p.text2),
                  )
                : null,
          ),
          const SizedBox(height: EtSpace.x3),
          Container(
            padding: const EdgeInsets.symmetric(vertical: EtSpace.x2),
            child: live
                ? EtSpeedGraph(history: history, height: graphHeight)
                : SizedBox(
                    height: graphHeight,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Symbols.monitoring, size: 28, color: p.text2),
                          const SizedBox(height: EtSpace.x2),
                          Text(
                            emptyMessage!,
                            textAlign: TextAlign.center,
                            style: text.bodySmall?.copyWith(color: p.text2),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
          if (live) ...[
            const SizedBox(height: EtSpace.x3),
            EtTrafficLegend(rxBps: rxBps, txBps: txBps),
          ],
        ],
      ),
    );
  }
}

/// Peer summary: the three lowest-latency online peers, then every offline peer.
/// Offline peers are never hidden here or anywhere else in the client.
class HomePeersCard extends StatelessWidget {
  const HomePeersCard({super.key, required this.peers, required this.up});

  final List<Peer> peers;
  final bool up;

  @override
  Widget build(BuildContext context) {
    final p = context.et;
    final text = Theme.of(context).textTheme;
    final online = peers.where((peer) => peer.online).toList()
      ..sort((a, b) {
        final left = a.latencyMs ?? 1 << 20;
        final right = b.latencyMs ?? 1 << 20;
        return left.compareTo(right);
      });
    final offline = peers.where((peer) => !peer.online).toList();
    final shown = [...online.take(3), ...offline];

    return EtSurface(
      padding: const EdgeInsets.fromLTRB(0, EtSpace.x4, 0, EtSpace.x2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: EtSpace.x4),
            child: HomeCardHeader(
              title: 'Peers',
              trailing: Text(
                up ? '${online.length} of ${peers.length} online' : '0 peers',
                style: text.bodySmall?.copyWith(color: p.text2),
              ),
            ),
          ),
          const SizedBox(height: EtSpace.x2),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                EtSpace.x4,
                0,
                EtSpace.x4,
                EtSpace.x2,
              ),
              child: Text(
                up
                    ? 'Connected, but no peers yet. Share the network name to invite a device.'
                    : 'Peers appear here once the tunnel is up.',
                style: text.bodySmall?.copyWith(color: p.text2),
              ),
            )
          else
            for (var i = 0; i < shown.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  indent: EtSpace.x4,
                  endIndent: EtSpace.x4,
                  color: p.border,
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: EtSpace.x2),
                child: EtPeerRow(peer: shown[i]),
              ),
            ],
        ],
      ),
    );
  }
}
