import 'package:flutter/material.dart';

import '../../core/theme/theme.dart';
import '../../core/ui/ui.dart';

/// Commercial M3 settings section: a quiet, single-line section label above a
/// grouped card. Never puts a second icon badge on the section header so the
/// card's leading icon column stays clean and uncrowded.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    super.key,
    required this.title,
    required this.children,
    this.trailing,
  });

  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.et;
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            EtSpace.x4,
            EtSpace.x1,
            EtSpace.x4,
            EtSpace.x2,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: text.labelMedium?.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: p.text2,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
        ),
        EtSurface(
          padding: const EdgeInsets.symmetric(vertical: EtSpace.x1),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ],
    );
  }
}

/// Standard commercial M3 settings row: one 36dp tonal icon squircle on the
/// left, crisp title + optional 1-line subtitle, and a compact trailing value
/// or control on the right.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.tone = EtTone.accent,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final EtTone tone;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final p = context.et;
    final text = Theme.of(context).textTheme;

    return ListTile(
      onTap: onTap,
      dense: false,
      visualDensity: const VisualDensity(vertical: -1),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: EtSpace.x4,
        vertical: 2,
      ),
      leading: Builder(
        builder: (context) {
          final (_, fg) = (destructive ? EtTone.danger : tone).resolve(p);
          return Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: p.scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 19, color: fg),
          );
        },
      ),
      title: Text(
        title,
        style: text.bodyLarge?.copyWith(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: destructive ? p.danger : p.text,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall?.copyWith(color: p.text2),
            ),
      trailing: trailing,
    );
  }
}

/// Settings row with an inline compact segmented pill selector. Automatically
/// wraps the selector below the title on ultra-narrow (<300dp) viewports so
/// 320px screens never overflow while normal phones stay single-row.
class SettingsSegmentedRow<T> extends StatelessWidget {
  const SettingsSegmentedRow({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
    this.tone = EtTone.accent,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final EtTone tone;
  final T value;
  final List<(T value, String label)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.et;
    final text = Theme.of(context).textTheme;
    final pill = SettingsSegmentedPill<T>(
      value: value,
      options: options,
      onChanged: onChanged,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 310;
        if (narrow) {
          return Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: EtSpace.x4,
              vertical: EtSpace.x2,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    EtIconBadge(icon: icon, tone: tone, size: 36),
                    const SizedBox(width: EtSpace.x3),
                    Expanded(
                      child: Text(
                        title,
                        style: text.bodyLarge?.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: p.text,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: EtSpace.x2),
                Align(alignment: Alignment.centerRight, child: pill),
              ],
            ),
          );
        }

        return SettingsRow(
          icon: icon,
          tone: tone,
          title: title,
          subtitle: subtitle,
          trailing: pill,
        );
      },
    );
  }
}

/// Sleek stadium pill segmented control (34dp height) for 2–3 inline options.
class SettingsSegmentedPill<T> extends StatelessWidget {
  const SettingsSegmentedPill({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final T value;
  final List<(T value, String label)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.et;
    final scheme = p.scheme;

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(EtRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (optionValue, label) in options)
            _SegmentPillItem(
              label: label,
              selected: optionValue == value,
              onTap: () {
                if (optionValue != value) onChanged(optionValue);
              },
            ),
        ],
      ),
    );
  }
}

class _SegmentPillItem extends StatelessWidget {
  const _SegmentPillItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.et.scheme;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(EtRadius.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(EtRadius.pill),
        onTap: () {
          EtHaptics.selection();
          onTap();
        },
        child: AnimatedContainer(
          duration: context.etReducedMotion ? Duration.zero : EtDuration.fast,
          curve: EtCurves.standard,
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? scheme.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(EtRadius.pill),
          ),
          child: Text(
            label,
            style: EtText.ui(
              size: EtType.caption,
              weight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected
                  ? scheme.onPrimaryContainer
                  : scheme.onSurfaceVariant,
              height: 1.15,
            ),
          ),
        ),
      ),
    );
  }
}

/// Mono value chip: machine data on a `surfaceContainerHighest` pill.
class SettingsMonoChip extends StatelessWidget {
  const SettingsMonoChip({super.key, required this.text, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = context.et;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: EtSpace.x3,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: p.scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(EtRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: context.etReducedMotion ? Duration.zero : EtDuration.fast,
            switchInCurve: EtCurves.enter,
            switchOutCurve: EtCurves.exit,
            child: Text(
              text,
              key: ValueKey<String>(text),
              style: EtText.mono(
                size: EtType.caption,
                weight: FontWeight.w500,
                color: p.text,
              ),
            ),
          ),
          if (icon != null) ...[
            const SizedBox(width: 4),
            Icon(icon, size: 14, color: p.text2),
          ],
        ],
      ),
    );
  }
}

/// Indented hairline divider aligned with the row title (past the 36dp leading
/// icon badge + 16dp horizontal padding + 16dp gap = 68dp).
class SettingsDivider extends StatelessWidget {
  const SettingsDivider({super.key});

  @override
  Widget build(BuildContext context) => Divider(
        height: 1,
        indent: 68,
        endIndent: EtSpace.x4,
        color: context.et.border.withValues(alpha: 0.6),
      );
}
