import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/models.dart';
import '../theme/theme.dart';

/// Shared UI kit built from Material 3 primitives.
///
/// Every widget here is a thin, token-driven composition of M3 components
/// (`Card`, `FilledButton`, `ListTile`, `ExpansionTile`, `SwitchListTile`,
/// `TextFormField`, `IconButton`) so the app reads as Google Material 3 while
/// screens stay declarative and consistent.

/// Five-state connection signal. M3 encodes state with a status icon + label;
/// colour is a support, not the only carrier.
enum EtSignalState { connected, connecting, degraded, disconnected, off }

class EtSignal extends StatelessWidget {
  const EtSignal({
    super.key,
    required this.state,
    this.label,
    this.compact = false,
  });

  final EtSignalState state;
  final String? label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.et;
    final (icon, color, text) = switch (state) {
      EtSignalState.connected => (Symbols.check_circle, p.success, 'Connected'),
      EtSignalState.connecting => (
        Symbols.progress_activity,
        p.accent,
        'Connecting',
      ),
      EtSignalState.degraded => (Symbols.warning, p.warn, 'Degraded'),
      EtSignalState.disconnected => (
        Symbols.link_off,
        p.danger,
        'Disconnected',
      ),
      EtSignalState.off => (
        Symbols.radio_button_unchecked,
        p.neutral,
        'Not running',
      ),
    };

    if (compact) {
      return Tooltip(
        message: label ?? text,
        child: Icon(icon, size: 20, color: color, semanticLabel: label ?? text),
      );
    }

    return Semantics(
      label: label ?? text,
      container: true,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: EtSpace.x2),
            Text(
              label ?? text,
              style: EtText.ui(
                size: EtType.bodySm,
                weight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// M3 surface: an elevated Card with optional tap target.
class EtSurface extends StatelessWidget {
  const EtSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(EtSpace.x4),
    this.onTap,
    this.color,
    this.borderColor,
    this.radius = EtRadius.card,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final p = context.et;
    final content = Padding(padding: padding, child: child);
    return Card(
      elevation: 1,
      margin: EdgeInsets.zero,
      semanticContainer: false,
      color: color ?? p.surface1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: borderColor == null
            ? BorderSide.none
            : BorderSide(color: borderColor!),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
  }
}

/// Tone for badges, banners and tinted affordances — maps onto M3 containers.
enum EtTone { accent, info, tertiary, warn, danger, neutral, success }

extension EtToneColors on EtTone {
  /// Container pair for a tone (public so feature widgets can reuse the exact
  /// same M3 roles instead of duplicating the mapping).
  (Color bg, Color fg) resolve(EtPalette p) => switch (this) {
    EtTone.accent => (p.accentQuiet, p.accentOnTint),
    EtTone.info => (p.infoQuiet, p.infoOnTint),
    EtTone.tertiary => (p.scheme.tertiaryContainer, p.scheme.onTertiaryContainer),
    EtTone.warn => (p.warnQuiet, p.warnOnTint),
    EtTone.danger => (p.dangerQuiet, p.dangerOnTint),
    EtTone.neutral => (p.neutralQuiet, p.text2),
    EtTone.success => (p.successContainer, p.onSuccessContainer),
  };
}

/// M3-style status chip (tonal container, 8dp corner, label typography).
class EtBadge extends StatelessWidget {
  const EtBadge({
    super.key,
    required this.label,
    this.tone = EtTone.neutral,
    this.icon,
  });

  final String label;
  final EtTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = tone.resolve(context.et);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: EtSpace.x2, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(EtRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: EtText.ui(
              size: EtType.micro,
              weight: FontWeight.w500,
              color: fg,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// Inline status banner (M3 container tone + icon + optional actions).
class EtBanner extends StatelessWidget {
  const EtBanner({
    super.key,
    required this.title,
    required this.tone,
    this.message,
    this.icon,
    this.actions = const [],
  });

  final String title;
  final String? message;
  final EtTone tone;
  final IconData? icon;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = tone.resolve(context.et);
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(EtRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsets.all(EtSpace.x4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon ??
                  switch (tone) {
                    EtTone.warn => Symbols.warning,
                    EtTone.danger => Symbols.error,
                    EtTone.success => Symbols.check_circle,
                    EtTone.info => Symbols.info,
                    EtTone.tertiary => Symbols.info,
                    EtTone.accent => Symbols.info,
                    EtTone.neutral => Symbols.info,
                  },
              color: fg,
              size: 20,
            ),
            const SizedBox(width: EtSpace.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: EtText.ui(
                      size: EtType.bodySm,
                      weight: FontWeight.w500,
                      color: fg,
                    ),
                  ),
                  if (message != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      message!,
                      style: EtText.ui(size: EtType.caption, color: fg),
                    ),
                  ],
                ],
              ),
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(width: EtSpace.x2),
              Row(mainAxisSize: MainAxisSize.min, children: actions),
            ],
          ],
        ),
      ),
    );
  }
}

/// Primary action. M3 filled button; `tonal` for the secondary/escape action.
class EtPrimaryButton extends StatelessWidget {
  const EtPrimaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.loading = false,
    this.danger = false,
    this.tonal = false,
    this.expanded = true,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool loading;
  final bool danger;
  final bool tonal;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final scheme = context.etScheme;
    final enabled = onPressed != null && !loading;
    final disabled = onPressed == null && !loading;
    final foreground = disabled
        ? scheme.onSurface.withValues(alpha: 0.38)
        : danger
        ? scheme.onError
        : tonal
        ? scheme.onSecondaryContainer
        : scheme.onPrimary;

    // M3 busy buttons keep their label and get an inline progress indicator;
    // a spinner-only button loses the announcement of what is happening.
    final Widget child = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: foreground),
          )
        else if (icon != null)
          Icon(icon, size: 18, color: foreground),
        if (loading || icon != null) const SizedBox(width: EtSpace.x2),
        Text(
          label,
          style: EtText.ui(
            size: EtType.bodySm,
            weight: FontWeight.w500,
            color: foreground,
          ),
        ),
      ],
    );

    final style = FilledButton.styleFrom(
      minimumSize: Size(expanded ? 64 : 0, 48),
      padding: const EdgeInsets.symmetric(horizontal: EtSpace.x6),
      shape: const StadiumBorder(),
      backgroundColor: danger ? scheme.error : null,
      foregroundColor: danger ? scheme.onError : null,
      disabledBackgroundColor: scheme.onSurface.withValues(alpha: 0.12),
      disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.38),
      textStyle: Theme.of(context).textTheme.labelLarge,
    );

    final button = tonal
        ? FilledButton.tonal(
            onPressed: enabled ? onPressed : null,
            style: style,
            child: child,
          )
        : FilledButton(
            onPressed: enabled ? onPressed : null,
            style: style,
            child: child,
          );

    return SizedBox(
      width: expanded ? double.infinity : null,
      height: 48,
      child: button,
    );
  }
}

class EtKpi extends StatelessWidget {
  const EtKpi({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.icon,
    this.trailing,
    this.valueColor,
    this.alignEnd = false,
  });

  final String label;
  final String value;
  final String? unit;
  final IconData? icon;
  final Widget? trailing;
  final Color? valueColor;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final p = context.et;
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: p.text2),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: EtText.ui(size: EtType.caption, color: p.text2),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: EtText.mono(
                size: EtType.headline,
                weight: FontWeight.w400,
                color: valueColor ?? p.text,
                height: 1.2,
              ),
            ),
            if (unit != null) ...[
              const SizedBox(width: 4),
              Text(
                unit!,
                style: EtText.ui(size: EtType.caption, color: p.text2),
              ),
            ],
            ?trailing,
          ],
        ),
      ],
    );
  }
}

/// Peer row as an M3 two-line `ListTile`: status icon, hostname + IP, path and
/// right-aligned latency. Offline peers stay visible (neutral + last seen).
class EtPeerRow extends StatelessWidget {
  const EtPeerRow({super.key, required this.peer, this.onTap});

  final Peer peer;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.et;
    final latency = peer.latencyMs;
    final latencyColor = !peer.online
        ? p.textDisabled
        : latency == null
        ? p.text2
        : latency <= 40
        ? p.success
        : latency <= 90
        ? p.warn
        : p.danger;

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: EtSpace.x2),
      leading: EtAvatar(name: peer.hostname, size: 40),
      title: Row(
        children: [
          Flexible(
            child: Text(
              peer.hostname,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: EtText.ui(
                size: EtType.bodySm,
                weight: FontWeight.w500,
                color: peer.online ? p.text : p.text2,
              ),
            ),
          ),
          if (!peer.online) ...[
            const SizedBox(width: EtSpace.x2),
            EtBadge(
              label: peer.lastSeen == null
                  ? 'offline'
                  : 'offline ${_ago(peer.lastSeen!)}',
              tone: EtTone.neutral,
            ),
          ],
        ],
      ),
      subtitle: Row(
        children: [
          Text(peer.ipv4, style: EtText.mono(size: EtType.caption, color: p.text2)),
          if (peer.online && peer.path != 'direct') ...[
            Text(' · ', style: EtText.ui(size: EtType.caption, color: p.text2)),
            Flexible(
              child: Text(
                peer.pathLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: EtText.ui(
                  size: EtType.caption,
                  color: peer.path == 'relay' ? p.warn : p.text2,
                ),
              ),
            ),
          ],
        ],
      ),
      trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: EtSpace.x2, vertical: 4),
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                latencyColor.withValues(alpha: 0.14),
                p.scheme.surfaceContainerHigh,
              ),
              borderRadius: BorderRadius.circular(EtRadius.pill),
            ),
            child: Text(
              latency == null || !peer.online ? '—' : '$latency ms',
              textAlign: TextAlign.right,
              style: EtText.mono(size: EtType.caption, color: latencyColor),
            ),
          ),
    );
  }

  static String _ago(DateTime at) {
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    return '${d.inDays}d';
  }
}

/// One-level disclosure. M3 `ExpansionTile`: basic is expanded, the expert
/// sections are collapsed. Never nest a second disclosure inside.
class EtSection extends StatefulWidget {
  const EtSection({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.leading,
    this.initiallyExpanded = false,
    this.children = const [],
    this.trailing,
    this.radius = EtRadius.card,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;

  /// Expressive leading widget (avatar, icon badge...). Takes precedence over
  /// [icon] when both are given.
  final Widget? leading;
  final bool initiallyExpanded;
  final List<Widget> children;
  final Widget? trailing;
  final double radius;

  @override
  State<EtSection> createState() => _EtSectionState();
}

class _EtSectionState extends State<EtSection> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final p = context.et;
    return Card(
      elevation: 1,
      margin: EdgeInsets.zero,
      semanticContainer: false,
      color: p.surface1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(widget.radius),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: widget.initiallyExpanded,
        onExpansionChanged: (value) => setState(() => _expanded = value),
        shape: const Border(),
        collapsedShape: const Border(),
        backgroundColor: Colors.transparent,
        collapsedBackgroundColor: Colors.transparent,
        tilePadding: const EdgeInsets.symmetric(horizontal: EtSpace.x4),
        childrenPadding: const EdgeInsets.fromLTRB(
          EtSpace.x4,
          EtSpace.x2,
          EtSpace.x4,
          EtSpace.x4,
        ),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        leading: widget.leading ??
            (widget.icon == null ? null : Icon(widget.icon, color: p.text2)),
        title: Text(
          widget.title,
          style: EtText.ui(
            size: EtType.title,
            weight: FontWeight.w600,
            color: p.text,
          ),
        ),
        subtitle: widget.subtitle == null
            ? null
            : Text(
                widget.subtitle!,
                style: EtText.ui(size: EtType.caption, color: p.text2),
              ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ?widget.trailing,
            const SizedBox(width: EtSpace.x2),
            AnimatedRotation(
              turns: _expanded ? 0.5 : 0,
              duration: context.etReducedMotion
                  ? Duration.zero
                  : EtDuration.fast,
              curve: EtCurves.standard,
              child: Icon(Symbols.expand_more, color: p.text2),
            ),
          ],
        ),
        children: widget.children,
      ),
    );
  }
}

/// Labelled field using the M3 outlined text field. The label is always
/// visible (floating label), errors stay attached to the field.
class EtTextField extends StatelessWidget {
  const EtTextField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.helper,
    this.error,
    this.mono = false,
    this.obscure = false,
    this.keyboardType,
    this.maxLines = 1,
    this.onChanged,
    this.suffix,
    this.enabled = true,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final String? helper;
  final String? error;
  final bool mono;
  final bool obscure;
  final TextInputType? keyboardType;
  final int maxLines;
  final ValueChanged<String>? onChanged;
  final Widget? suffix;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final p = context.et;
    final style = mono
        ? EtText.mono(size: EtType.bodySm, color: p.text)
        : EtText.ui(size: EtType.bodySm, color: p.text);
    return Padding(
      padding: const EdgeInsets.only(top: EtSpace.x2),
      child: TextFormField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        maxLines: obscure ? 1 : maxLines,
        enabled: enabled,
        onChanged: onChanged,
        style: style,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          helperText: helper,
          helperMaxLines: 2,
          errorText: error,
          errorMaxLines: 3,
          suffixIcon: suffix,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

/// M3 switch row (`SwitchListTile`).
class EtSwitchRow extends StatelessWidget {
  const EtSwitchRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      value: value,
      onChanged: enabled ? onChanged : null,
      contentPadding: EdgeInsets.zero,
      dense: true,
    );
  }
}

class EtEmptyState extends StatelessWidget {
  const EtEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final p = context.et;
    final reduced = context.etReducedMotion;
    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: reduced ? 1 : 0, end: 1),
        duration: reduced ? Duration.zero : EtDuration.base,
        curve: EtCurves.enter,
        builder: (context, t, child) => Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 10),
            child: child,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(EtSpace.x6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(EtSpace.x4),
                decoration: BoxDecoration(
                  color: p.neutralQuiet,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 30, color: p.text2),
              ),
            const SizedBox(height: EtSpace.x4),
            Text(
              title,
              textAlign: TextAlign.center,
              style: EtText.ui(
                size: EtType.title,
                weight: FontWeight.w500,
                color: p.text,
              ),
            ),
            const SizedBox(height: EtSpace.x2),
            Text(
              message,
              textAlign: TextAlign.center,
              style: EtText.ui(size: EtType.bodySm, color: p.text2),
            ),
              if (action != null) ...[
                const SizedBox(height: EtSpace.x5),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Streaming area chart for rx/tx, using M3 primary/tertiary roles.
class EtSpeedGraph extends StatefulWidget {
  const EtSpeedGraph({super.key, required this.history, this.height = 84});

  final List<TrafficSample> history;
  final double height;

  @override
  State<EtSpeedGraph> createState() => _EtSpeedGraphState();
}

class _EtSpeedGraphState extends State<EtSpeedGraph>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: EtDuration.loopPulse,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.etReducedMotion) {
      _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.et;
    return Semantics(
      label: widget.history.isEmpty
          ? 'No traffic yet'
          : 'Traffic, last ${widget.history.length} seconds, receive and send',
      child: SizedBox(
        height: widget.height,
        child: widget.history.isEmpty
            ? Center(
                child: Text(
                  'Waiting for traffic…',
                  style: EtText.ui(size: EtType.caption, color: p.text2),
                ),
              )
            : AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) => CustomPaint(
                  painter: _SpeedGraphPainter(
                    history: widget.history,
                    rxColor: p.accent,
                    txColor: p.scheme.tertiary,
                    grid: p.border,
                    pulse: context.etReducedMotion ? 0 : _pulse.value,
                  ),
                  size: Size.infinite,
                ),
              ),
      ),
    );
  }
}

class _SpeedGraphPainter extends CustomPainter {
  _SpeedGraphPainter({
    required this.history,
    required this.rxColor,
    required this.txColor,
    required this.grid,
    this.pulse = 0,
  });

  final List<TrafficSample> history;
  final Color rxColor;
  final Color txColor;
  final Color grid;

  /// 0..1 phase of the "live" halo drawn at the newest sample.
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final maxValue = history.fold<int>(
      1,
      (m, s) => math.max(m, math.max(s.rxBps, s.txBps)),
    );
    final dx = size.width / math.max(1, history.length - 1);

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 1; i <= 2; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    Path pathFor(int Function(TrafficSample) pick) {
      final path = Path();
      for (var i = 0; i < history.length; i++) {
        final x = i * dx;
        final y = size.height - (pick(history[i]) / maxValue) * size.height;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      return path;
    }

    void drawSeries(int Function(TrafficSample) pick, Color color) {
      final line = pathFor(pick);
      final area = Path.from(line)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: 0.16),
              color.withValues(alpha: 0.0),
            ],
          ).createShader(Offset.zero & size),
      );
      canvas.drawPath(
        line,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
      // Highlight the most recent sample.
      final last = history.last;
      final lastX = (history.length - 1) * dx;
      final lastY = size.height - (pick(last) / maxValue) * size.height;
      canvas.drawCircle(Offset(lastX, lastY), 3, Paint()..color = color);
      // Breathing halo marks the live edge without animating the whole line.
      final wave = (math.sin(pulse * math.pi * 2) + 1) / 2;
      canvas.drawCircle(
        Offset(lastX, lastY),
        5 + wave * 6,
        Paint()
          ..color = color.withValues(alpha: (1 - wave) * 0.30)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
    }

    drawSeries((s) => s.txBps, txColor);
    drawSeries((s) => s.rxBps, rxColor);
  }

  @override
  bool shouldRepaint(_SpeedGraphPainter old) =>
      old.history != history ||
      old.rxColor != rxColor ||
      old.txColor != txColor ||
      old.pulse != pulse;
}

/// Legend for [EtSpeedGraph]; rates are mono so they align.
class EtTrafficLegend extends StatelessWidget {
  const EtTrafficLegend({super.key, required this.rxBps, required this.txBps});

  final int rxBps;
  final int txBps;

  @override
  Widget build(BuildContext context) {
    final p = context.et;
    Widget item(IconData icon, Color color, String label, int value) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: EtText.ui(size: EtType.caption, color: p.text2),
        ),
        const SizedBox(width: 6),
        Text(
          formatRate(value),
          style: EtText.mono(size: EtType.caption, color: p.text),
        ),
      ],
    );
    return Row(
      children: [
        item(Symbols.arrow_downward, p.success, 'Down', rxBps),
        const SizedBox(width: EtSpace.x5),
        item(Symbols.arrow_upward, p.scheme.tertiary, 'Up', txBps),
      ],
    );
  }
}



/// Expressive avatar: initials on a tinted circle. Colour is decorative and
/// stable per name; the text always uses onSurface for contrast.
class EtAvatar extends StatelessWidget {
  const EtAvatar({super.key, required this.name, this.size = 40});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.et;
    final accent = EtAccent.byIndex(name.codeUnits.fold<int>(0, (a, b) => a + b));
    final initials = _initials(name);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Color.alphaBlend(
          accent.withValues(alpha: p.isDark ? 0.30 : 0.20),
          p.scheme.surfaceContainerHigh,
        ),
      ),
      child: Text(
        initials,
        style: EtText.ui(
          size: size * 0.38,
          weight: FontWeight.w700,
          color: p.scheme.onSurface,
        ),
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.split(RegExp(r'[-_.\s]+')).where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.take(2).toString().toUpperCase();
    return (parts[0].characters.take(1).toString() + parts[1].characters.take(1).toString())
        .toUpperCase();
  }
}

/// Tonal icon badge used by section headers and activity rows: an expressive
/// squircle instead of a bare glyph.
class EtIconBadge extends StatelessWidget {
  const EtIconBadge({
    super.key,
    required this.icon,
    this.tone = EtTone.accent,
    this.size = 40,
  });

  final IconData icon;
  final EtTone tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = tone.resolve(context.et);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(size * 0.34),
      ),
      child: Icon(icon, size: size * 0.5, color: fg),
    );
  }
}

/// Expressive connection orb: the hero's single visual anchor. Rings pulse while
/// connecting/connected; the animation freezes to a static state under
/// reduced-motion. Purely decorative — the hero text carries the meaning.
class EtConnectionOrb extends StatefulWidget {
  const EtConnectionOrb({super.key, required this.state, this.size = 132});

  final EtSignalState state;
  final double size;

  @override
  State<EtConnectionOrb> createState() => _EtConnectionOrbState();
}

class _EtConnectionOrbState extends State<EtConnectionOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: EtDuration.loopRing,
  );

  bool get _animates =>
      !context.etReducedMotion &&
      (widget.state == EtSignalState.connected ||
          widget.state == EtSignalState.connecting);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Context-dependent (reduced motion) — must not run in initState.
    _sync();
  }

  @override
  void didUpdateWidget(EtConnectionOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (_animates) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.et;
    final (icon, color) = switch (widget.state) {
      EtSignalState.connected => (Symbols.shield, p.success),
      EtSignalState.connecting => (Symbols.sync, p.accent),
      EtSignalState.degraded => (Symbols.warning, p.warn),
      EtSignalState.disconnected => (Symbols.link_off, p.danger),
      EtSignalState.off => (Symbols.shield, p.neutral),
    };
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            painter: _OrbPainter(
              color: color,
              progress: _controller.value,
              animating: _animates,
              surface: p.scheme.surfaceContainerLowest,
              outline: p.scheme.outlineVariant,
            ),
            child: Center(
              child: Container(
                width: widget.size * 0.46,
                height: widget.size * 0.46,
                decoration: BoxDecoration(
                  color: p.scheme.surface.withValues(alpha: 0.72),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: widget.size * 0.22, color: color),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  const _OrbPainter({
    required this.color,
    required this.progress,
    required this.animating,
    required this.surface,
    required this.outline,
  });

  final Color color;
  final double progress;
  final bool animating;
  final Color surface;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final base = size.width / 2;
    // Soft glow.
    canvas.drawCircle(
      center,
      base * 0.78,
      Paint()
        ..shader = RadialGradient(
          colors: [color.withValues(alpha: animating ? 0.34 : 0.20), color.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: center, radius: base)),
    );
    // Rings: two static halos plus one travelling ring.
    for (var i = 0; i < 3; i++) {
      final t = ((progress + i / 3) % 1.0);
      final radius = base * (0.52 + t * 0.46);
      final alpha = animating ? (1 - t) * 0.42 : 0.16 - i * 0.04;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = color.withValues(alpha: alpha.clamp(0.0, 1.0)),
      );
    }
    canvas.drawCircle(
      center,
      base * 0.50,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = outline,
    );
  }

  @override
  bool shouldRepaint(_OrbPainter old) =>
      old.progress != progress || old.color != color || old.animating != animating;
}

/// Expressive tonal statistic tile (bento block on Home).
class EtStatTile extends StatelessWidget {
  const EtStatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.tone = EtTone.accent,
    this.unit,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final EtTone tone;
  final String? unit;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = tone.resolve(context.et);
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(EtSpace.x3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: fg),
                  const Spacer(),
                  if (onTap != null)
                    Icon(
                      Symbols.chevron_right,
                      size: 16,
                      color: fg.withValues(alpha: 0.7),
                    ),
                ],
              ),
              const SizedBox(height: EtSpace.x2),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: EtText.mono(
                        size: EtType.title,
                        weight: FontWeight.w500,
                        color: fg,
                        height: 1.2,
                      ),
                    ),
                  ),
                  if (unit != null) ...[
                    const SizedBox(width: 2),
                    Text(unit!, style: EtText.ui(size: EtType.micro, color: fg)),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: EtText.ui(size: EtType.micro, color: fg, height: 1.2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens the standard M3 bottom sheet.
Future<T?> showEtSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: builder(context),
    ),
  );
}
