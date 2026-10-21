import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';

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
///
/// Motion: the content is choreographed (badge → orb → state → latency →
/// action) on first paint and replayed whenever the connection state changes,
/// so "connected" lands with a deliberate beat instead of a hard swap.
class HomeHero extends StatefulWidget {
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
  State<HomeHero> createState() => _HomeHeroState();
}

class _HomeHeroState extends State<HomeHero>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: EtDuration.hero,
  )..forward();

  @override
  void didUpdateWidget(HomeHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.signalState != widget.signalState) {
      if (context.etReducedMotion) {
        _controller.value = 1;
      } else {
        _controller.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Animation<double> _slice(double begin, double end) => CurvedAnimation(
        parent: _controller,
        curve: Interval(begin, end, curve: EtCurves.enter),
      );

  @override
  Widget build(BuildContext context) {
    final p = context.et;
    final text = Theme.of(context).textTheme;
    final reduced = context.etReducedMotion;
    final latencyMs = widget.latencyMs;
    final value = latencyMs == null ? '—' : '$latencyMs';
    final semantics = latencyMs == null
        ? 'Latency unavailable'
        : 'Latency $latencyMs milliseconds';

    final (tone, icon, defaultLabel) = switch (widget.signalState) {
      EtSignalState.connected => (EtTone.success, Symbols.check_circle, I18n.t('Connected')),
      EtSignalState.connecting => (EtTone.info, Symbols.sync, I18n.t('Connecting')),
      EtSignalState.degraded => (EtTone.warn, Symbols.warning, I18n.t('Degraded')),
      EtSignalState.disconnected => (EtTone.danger, Symbols.link_off, I18n.t('Disconnected')),
      EtSignalState.off => (EtTone.neutral, Symbols.radio_button_unchecked, I18n.t('Not running')),
    };
    final statusText = widget.signalLabel ?? defaultLabel;
    final (chipBg, chipFg) = tone.resolve(p);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(EtRadius.hero),
        border: Border.all(
          color: p.isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _AuroraPainter(
                base: p.isDark
                    ? const Color(0xFF0C111D)
                    : p.scheme.surfaceContainerLowest,
                primary: EtAccent.blue,
                tertiary: EtAccent.violet,
                success: EtAccent.cyan,
                dark: p.isDark,
                intensity: switch (widget.signalState) {
                  EtSignalState.connected => 1.0,
                  EtSignalState.connecting => 0.8,
                  EtSignalState.degraded => 0.65,
                  _ => 0.32,
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              EtSpace.x5,
              EtSpace.x4,
              EtSpace.x5,
              EtSpace.x5,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                EtEnter(
                  animation: _slice(0.0, 0.55),
                  child: Row(
                    children: [
                      _HeroStatusChip(
                        label: statusText,
                        icon: icon,
                        fg: chipFg,
                        bg: chipBg,
                      ),
                      const Spacer(),
                      if (widget.uptimeLabel != '—')
                        Text(
                          widget.uptimeLabel,
                          style: EtText.mono(
                            size: EtType.caption,
                            color: p.text2,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: EtSpace.x4),
                EtEnter(
                  animation: _slice(0.08, 0.68),
                  interval: const Interval(0.08, 0.68, curve: EtCurves.enter),
                  offset: 6,
                  child: Center(
                    child: EtConnectionOrb(
                      state: widget.signalState,
                      size: 100,
                    ),
                  ),
                ),
                const SizedBox(height: EtSpace.x2),
                EtEnter(
                  animation: _slice(0.16, 0.76),
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: reduced ? Duration.zero : EtDuration.fast,
                      switchInCurve: EtCurves.enter,
                      switchOutCurve: EtCurves.exit,
                      child: Text(
                        widget.stateLine,
                        key: ValueKey<String>(widget.stateLine),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleLarge?.copyWith(
                          fontSize: 24,
                          color: p.text,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: EtSpace.x3),
                EtEnter(
                  animation: _slice(0.24, 0.86),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          I18n.t('LATENCY'),
                          style: text.labelSmall?.copyWith(
                            color: p.text3,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.3,
                          ),
                        ),
                        const SizedBox(height: 2),
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
                                      size: 38,
                                      weight: FontWeight.w700,
                                      color: latencyMs == null ? p.text3 : p.text,
                                      height: 1.05,
                                    ),
                                  ),
                                  if (latencyMs != null)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        left: 3,
                                        bottom: 5,
                                      ),
                                      child: Text(
                                        'ms',
                                        style: text.labelMedium?.copyWith(
                                          color: p.text2,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Text(
                          latencyMs == null
                              ? I18n.t('connect to measure')
                              : I18n.t('to nearest peer'),
                          style: text.bodySmall?.copyWith(color: p.text2),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: EtSpace.x4),
                EtEnter(
                  animation: _slice(0.32, 1.0),
                  child: EtPressScale(child: widget.action),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Restrained status pill for the hero: a coloured dot + label on a quiet
/// tonal field, never a saturated badge on top of a gradient.
class _HeroStatusChip extends StatelessWidget {
  const _HeroStatusChip({
    required this.label,
    required this.icon,
    required this.fg,
    required this.bg,
  });

  final String label;
  final IconData icon;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    final p = context.et;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Color.alphaBlend(bg.withValues(alpha: 0.55), p.scheme.surface),
        borderRadius: BorderRadius.circular(EtRadius.pill),
        border: Border.all(color: fg.withValues(alpha: 0.26)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: EtText.ui(
              size: EtType.caption,
              weight: FontWeight.w600,
              color: fg,
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

    final boost = (dark ? 1.0 : 0.6) * intensity;
    final blend = dark ? BlendMode.screen : BlendMode.srcOver;

    // One purposeful glow behind the orb instead of a muddy multi-blob aurora.
    final center = Offset(size.width * 0.5, size.height * 0.30);
    canvas.drawRect(
      rect,
      Paint()
        ..blendMode = blend
        ..shader = RadialGradient(
          colors: [
            primary.withValues(alpha: 0.34 * boost),
            primary.withValues(alpha: 0),
          ],
        ).createShader(
          Rect.fromCircle(center: center, radius: size.width * 0.82),
        ),
    );
    // A single cool counter-light keeps the lower half from going flat.
    canvas.drawRect(
      rect,
      Paint()
        ..blendMode = blend
        ..shader = RadialGradient(
          center: const Alignment(-0.9, 0.95),
          radius: 0.9,
          colors: [
            success.withValues(alpha: 0.10 * boost),
            success.withValues(alpha: 0),
          ],
        ).createShader(rect),
    );

    // Concentric guide rings anchor the orb without decoration noise.
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = (dark ? Colors.white : Colors.black)
          .withValues(alpha: dark ? 0.055 : 0.045);
    for (final radius in const [66.0, 84.0, 104.0]) {
      canvas.drawCircle(center, radius, ring);
    }

    // Fine top edge highlight.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, 1),
      Paint()
        ..color = (dark ? Colors.white : Colors.black)
            .withValues(alpha: dark ? 0.10 : 0.05),
    );
  }

  @override
  bool shouldRepaint(_AuroraPainter old) =>
      old.base != base || old.primary != primary || old.tertiary != tertiary ||
      old.success != success || old.dark != dark || old.intensity != intensity;
}

/// Three quiet stat cells in one segmented card. Colour lives in the icon
/// tile only; the rest is typography, which reads calmer than three saturated
/// blocks and keeps the dashboard scannable.
class HomeStatsRow extends StatelessWidget {
  const HomeStatsRow({
    super.key,
    required this.up,
    required this.onlinePeers,
    required this.peerCount,
    required this.routeCount,
    required this.rxBps,
    this.onOpenDevices,
  });

  final bool up;
  final int onlinePeers;
  final int peerCount;
  final int routeCount;
  final int rxBps;
  final VoidCallback? onOpenDevices;

  @override
  Widget build(BuildContext context) {
    final p = context.et;
    final tiles = <Widget>[
      _HomeStatCell(
        label: I18n.t('Peers'),
        value: up ? '$onlinePeers / $peerCount' : '—',
        icon: Symbols.devices,
        tone: EtTone.accent,
        onTap: onOpenDevices,
      ),
      _HomeStatCell(
        label: I18n.t('Routes'),
        value: up ? '$routeCount' : '—',
        icon: Symbols.alt_route,
        tone: EtTone.warn,
        onTap: onOpenDevices,
      ),
      _HomeStatCell(
        label: I18n.t('Downlink'),
        value: up ? formatRate(rxBps) : '—',
        icon: Symbols.arrow_downward,
        tone: EtTone.success,
      ),
    ];

    return EtSurface(
      padding: EdgeInsets.zero,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < tiles.length; i++) ...[
              if (i > 0)
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: p.border.withValues(alpha: 0.55),
                ),
              Expanded(child: tiles[i]),
            ],
          ],
        ),
      ),
    );
  }
}

class _HomeStatCell extends StatelessWidget {
  const _HomeStatCell({
    required this.label,
    required this.value,
    required this.icon,
    required this.tone,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final EtTone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.et;
    final text = Theme.of(context).textTheme;
    final (bg, fg) = tone.resolve(p);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: p.scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 15, color: fg),
                ),
                const Spacer(),
                if (onTap != null)
                  Icon(
                    Symbols.chevron_right,
                    size: 14,
                    color: p.textDisabled,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: EtText.mono(
                size: EtType.title,
                weight: FontWeight.w600,
                color: p.text,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              label.toUpperCase(),
              style: text.labelSmall?.copyWith(
                color: p.text2,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Identity of the selected network, with a direct link to edit its
/// configuration and one-tap Virtual IP copy.
class HomeNetworkCard extends StatelessWidget {
  const HomeNetworkCard({
    super.key,
    required this.instanceName,
    required this.networkName,
    required this.virtualIp,
    required this.up,
    this.onConfigure,
    this.onCopyIp,
  });

  final String instanceName;
  final String networkName;
  final String? virtualIp;
  final bool up;
  final VoidCallback? onConfigure;
  final VoidCallback? onCopyIp;

  @override
  Widget build(BuildContext context) {
    final p = context.et;
    return EtSurface(
      padding: const EdgeInsets.fromLTRB(0, EtSpace.x3, 0, EtSpace.x2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: EtSpace.x4),
            child: HomeCardHeader(
              title: I18n.t('Network'),
              trailing: onConfigure == null
                  ? null
                  : TextButton.icon(
                      onPressed: onConfigure,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: EtSpace.x2,
                        ),
                      ),
                      icon: const Icon(Symbols.tune, size: 16),
                      label: Text(I18n.t('Configure')),
                    ),
            ),
          ),
          const SizedBox(height: EtSpace.x1),
          _DetailTile(
            label: I18n.t('Virtual IP'),
            value: virtualIp ?? '—',
            mono: true,
            onTap: virtualIp != null ? onCopyIp : null,
          ),
          Divider(
            height: 1,
            indent: EtSpace.x4,
            endIndent: EtSpace.x4,
            color: p.border.withValues(alpha: 0.5),
          ),
          _DetailTile(label: I18n.t('Instance'), value: instanceName, mono: true),
          Divider(
            height: 1,
            indent: EtSpace.x4,
            endIndent: EtSpace.x4,
            color: p.border.withValues(alpha: 0.5),
          ),
          _DetailTile(label: I18n.t('Network'), value: networkName),
        ],
      ),
    );
  }
}

/// One `ListTile` data row: label on the left, mono/UI value right-aligned.
class _DetailTile extends StatelessWidget {
  const _DetailTile({
    required this.label,
    required this.value,
    this.mono = false,
    this.onTap,
  });

  final String label;
  final String value;
  final bool mono;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.et;
    final text = Theme.of(context).textTheme;
    return ListTile(
      onTap: onTap,
      dense: true,
      minVerticalPadding: 0,
      contentPadding: const EdgeInsets.symmetric(horizontal: EtSpace.x4),
      title: Text(label, style: text.bodyMedium?.copyWith(color: p.text2)),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 196),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
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
            if (onTap != null) ...[
              const SizedBox(width: EtSpace.x1),
              Icon(Symbols.content_copy, size: 14, color: p.text2),
            ],
          ],
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
            title: I18n.t('Traffic'),
            trailing: live
                ? Text(
                    I18n.t('60 s'),
                    style: EtText.mono(size: EtType.micro, color: p.text2),
                  )
                : null,
          ),
          const SizedBox(height: EtSpace.x3),
          Container(
            padding: const EdgeInsets.symmetric(vertical: EtSpace.x2),
            child: live
                ? EtSpeedGraph(history: history, height: graphHeight)
                : SizedBox(
                    height: 96,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Symbols.monitoring, size: 24, color: p.text2),
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
  const HomePeersCard({
    super.key,
    required this.peers,
    required this.up,
    this.onOpenDevices,
  });

  final List<Peer> peers;
  final bool up;
  final VoidCallback? onOpenDevices;

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
              title: I18n.t('Peers'),
              trailing: InkWell(
                borderRadius: BorderRadius.circular(EtRadius.sm),
                onTap: onOpenDevices,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: EtSpace.x1,
                    vertical: 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        up
                            ? '${online.length} of ${peers.length} online'
                            : I18n.t('0 peers'),
                        style: text.bodySmall?.copyWith(color: p.text2),
                      ),
                      if (onOpenDevices != null) ...[
                        const SizedBox(width: 2),
                        Icon(Symbols.chevron_right, size: 16, color: p.text2),
                      ],
                    ],
                  ),
                ),
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
                child: EtPeerRow(peer: shown[i], onTap: onOpenDevices),
              ),
            ],
        ],
      ),
    );
  }
}
