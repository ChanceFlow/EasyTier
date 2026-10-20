import 'package:flutter/material.dart';

import '../../core/theme/theme.dart';
import '../../core/ui/ui.dart';

/// Expressive settings group: a tonal `EtIconBadge`, a `titleMedium` heading and
/// an optional subtitle above a calm M3 card. Settings apply immediately, so a
/// group never owns a Save button.
///
/// [glow] adds a quiet `EtGradient.surfaceGlow` band behind the heading — used
/// once on About as its expressive accent, not on every group.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    super.key,
    required this.icon,
    required this.title,
    this.tone = EtTone.accent,
    this.subtitle,
    this.children = const [],
    this.glow = false,
    this.meta,
  });

  final IconData icon;
  final String title;
  final EtTone tone;
  final String? subtitle;
  final List<Widget> children;
  final bool glow;
  final Widget? meta;

  @override
  Widget build(BuildContext context) {
    final p = context.et;
    final text = Theme.of(context).textTheme;
    final destructive = tone == EtTone.danger;

    Widget header = Row(
      children: [
        EtIconBadge(icon: icon, tone: tone, size: 36),
        const SizedBox(width: EtSpace.x3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: text.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: destructive ? p.danger : p.text,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: text.bodySmall?.copyWith(color: p.text2),
                ),
              ],
            ],
          ),
        ),
        ?meta,
      ],
    );

    if (glow) {
      header = Container(
        padding: const EdgeInsets.symmetric(
          horizontal: EtSpace.x3,
          vertical: EtSpace.x2,
        ),
        decoration: BoxDecoration(
          gradient: EtGradient.surfaceGlow(p),
          borderRadius: BorderRadius.circular(EtRadius.lg),
        ),
        child: header,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            EtSpace.x4,
            EtSpace.x2,
            EtSpace.x4,
            EtSpace.x2,
          ),
          child: header,
        ),
        EtSurface(
          padding: const EdgeInsets.symmetric(vertical: EtSpace.x2),
          borderColor: destructive
              ? p.danger.withValues(alpha: 0.35)
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ],
    );
  }
}

/// One settings row: tonal icon badge, label/helper, optional value or control.
/// Built on the M3 `ListTile`, so state layers, semantics and 48dp targets come
/// from Material instead of hand-rolled rows.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.tone = EtTone.accent,
    this.subtitle,
    this.trailing,
    this.footer,
    this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final EtTone tone;
  final String? subtitle;

  /// Right-hand value/control: mono chip, badge or text.
  final Widget? trailing;

  /// Extra line under the helper (e.g. the mode badge), so a long value never
  /// squeezes the label on narrow screens.
  final Widget? footer;

  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final p = context.et;
    final text = Theme.of(context).textTheme;
    final subtitleWidget = (subtitle == null && footer == null)
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (subtitle != null)
                Text(subtitle!, style: text.bodySmall?.copyWith(color: p.text2)),
              if (footer != null) ...[
                if (subtitle != null) const SizedBox(height: EtSpace.x1),
                footer!,
              ],
            ],
          );

    return ListTile(
      onTap: onTap,
      minVerticalPadding: EtSpace.x2,
      contentPadding: const EdgeInsets.symmetric(horizontal: EtSpace.x4),
      leading: EtIconBadge(
        icon: icon,
        tone: destructive ? EtTone.danger : tone,
        size: 32,
      ),
      title: Text(
        title,
        style: text.bodyLarge?.copyWith(
          fontWeight: FontWeight.w500,
          color: destructive ? p.danger : p.text,
        ),
      ),
      subtitle: subtitleWidget,
      trailing: trailing,
    );
  }
}

/// Label for an inline control (Theme, Language): the same tonal badge as a row
/// so the whole card keeps one leading-icon line.
class SettingsFieldLabel extends StatelessWidget {
  const SettingsFieldLabel({
    super.key,
    required this.icon,
    required this.title,
    this.tone = EtTone.accent,
  });

  final IconData icon;
  final String title;
  final EtTone tone;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        EtIconBadge(icon: icon, tone: tone, size: 32),
        const SizedBox(width: EtSpace.x4),
        Expanded(
          child: Text(
            title,
            style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}

/// Mono value chip: machine data on a `surfaceContainerHighest` pill.
class SettingsMonoChip extends StatelessWidget {
  const SettingsMonoChip({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.et;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: EtSpace.x3,
        vertical: EtSpace.x1,
      ),
      decoration: BoxDecoration(
        color: p.scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(EtRadius.pill),
      ),
      child: Text(
        text,
        style: EtText.mono(size: EtType.caption, color: p.text2),
      ),
    );
  }
}

/// Hairline between rows/groups inside an expressive card.
class SettingsDivider extends StatelessWidget {
  const SettingsDivider({super.key});

  @override
  Widget build(BuildContext context) => const Divider(
        height: 1,
        indent: EtSpace.x4,
        endIndent: EtSpace.x4,
      );
}
