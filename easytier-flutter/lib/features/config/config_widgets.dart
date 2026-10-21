import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';

import '../../core/models/models.dart';
import '../../core/theme/theme.dart';
import '../../core/ui/ui.dart';

/// Small, config-specific building blocks. Everything here is either a layout
/// helper or a thin composition of Material 3 primitives — no custom-drawn
/// chrome, no external labels competing with the M3 floating label.

/// Vertical stack with the M3 spacing rhythm.
class ConfigStack extends StatelessWidget {
  const ConfigStack({super.key, required this.children, this.gap = EtSpace.x4});

  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(height: gap),
          children[i],
        ],
      ],
    );
  }
}

/// Two-column field pairs on wide screens, one column on phones. The two
/// columns share the row so labels stay aligned; focus order is row-major and
/// therefore still matches visual order.
class ConfigTwoColumn extends StatelessWidget {
  const ConfigTwoColumn({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    if (!wide || children.length < 2) return ConfigStack(children: children);

    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += 2) {
      final hasSecond = i + 1 < children.length;
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: children[i]),
            const SizedBox(width: EtSpace.x4),
            Expanded(
              child: hasSecond ? children[i + 1] : const SizedBox.shrink(),
            ),
          ],
        ),
      );
    }
    return ConfigStack(children: rows);
  }
}

/// M3 sub-section caption inside a section. Not a disclosure control: the
/// config screen has exactly one disclosure level (the [EtSection] card).
class ConfigSubhead extends StatelessWidget {
  const ConfigSubhead({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: EtSpace.x2),
      child: Text(
        label,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class ConfigChoice<T> {
  const ConfigChoice({required this.value, required this.label});

  final T value;
  final String label;
}

/// M3 outlined select (`DropdownButtonFormField`). The floating label is the
/// only label — the old private dropdown drew an external label above a boxed
/// control, which produced the double-label / border-through-text defect.
class ConfigSelectField<T> extends StatelessWidget {
  const ConfigSelectField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.helper,
    this.error,
    this.enabled = true,
    this.mono = true,
  });

  final String label;
  final T value;
  final List<ConfigChoice<T>> options;
  final ValueChanged<T>? onChanged;
  final String? helper;
  final String? error;
  final bool enabled;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final style = mono
        ? EtText.mono(size: EtType.bodySm)
        : EtText.ui(size: EtType.bodySm);
    // A config edited outside this UI may hold a value that is not one of the
    // documented choices; surface it instead of tripping the dropdown
    // assertion.
    final choices = <ConfigChoice<T>>[
      ...options,
      if (!options.any((option) => option.value == value))
        ConfigChoice<T>(value: value, label: '$value'),
    ];
    return DropdownButtonFormField<T>(
      key: ValueKey<T>(value),
      initialValue: value,
      isExpanded: true,
      style: style,
      icon: const Icon(Symbols.expand_more),
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        helperMaxLines: 2,
        errorText: error,
        errorMaxLines: 3,
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final option in choices)
          DropdownMenuItem<T>(
            value: option.value,
            child: Text(option.label),
          ),
      ],
      onChanged: enabled
          ? (next) {
              if (next != null) onChanged?.call(next);
            }
          : null,
    );
  }
}

/// M3 `SegmentedButton` with a caption label, used for enum choices in the add
/// sheets (protocol / action / chain).
class ConfigSegmentedField<T> extends StatelessWidget {
  const ConfigSegmentedField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final T value;
  final List<ConfigChoice<T>> options;
  final ValueChanged<T>? onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final active = enabled && onChanged != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: EtSpace.x2),
        Align(
          alignment: Alignment.centerLeft,
          child: SegmentedButton<T>(
            segments: [
              for (final option in options)
                ButtonSegment<T>(
                  value: option.value,
                  label: Text(option.label, maxLines: 1),
                ),
            ],
            selected: {value},
            showSelectedIcon: false,
            onSelectionChanged: active
                ? (selection) => onChanged?.call(selection.first)
                : null,
          ),
        ),
      ],
    );
  }
}

/// Error attached to a whole list (port forwards, ACL rules) rather than to a
/// single text field. Mirrors the M3 field error style.
class ConfigErrorText extends StatelessWidget {
  const ConfigErrorText({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Symbols.error, size: 16, color: scheme.error),
        const SizedBox(width: EtSpace.x2),
        Expanded(
          child: Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
          ),
        ),
      ],
    );
  }
}

/// Section-internal list header: M3 title style, count, and the single add
/// action.
class ConfigListHeader extends StatelessWidget {
  const ConfigListHeader({
    super.key,
    required this.title,
    required this.addLabel,
    this.onAdd,
    this.count,
  });

  final String title;
  final String addLabel;
  final VoidCallback? onAdd;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(color: scheme.onSurface),
          ),
        ),
        if ((count ?? 0) > 0) ...[
          const SizedBox(width: EtSpace.x2),
          Text(
            '$count',
            style: EtText.mono(
              size: EtType.caption,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
        const Spacer(),
        TextButton.icon(
          onPressed: onAdd,
          icon: const Icon(Symbols.add, size: 18),
          label: Text(addLabel),
        ),
      ],
    );
  }
}

/// Expressive instance cards. The selected network is a tinted card with a
/// name avatar, the instance name, a network chip and an "Active" badge; with
/// more than one network the strip lets the reader switch the edited config.
class ConfigInstanceCards extends StatelessWidget {
  const ConfigInstanceCards({
    super.key,
    required this.instances,
    required this.activeId,
    required this.enabled,
    required this.onSelect,
  });

  final List<NetworkInstance> instances;
  final String activeId;
  final bool enabled;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    if (instances.isEmpty) return const SizedBox.shrink();
    if (instances.length == 1) {
      // A single network does not need a full-width strip; keep the card
      // compact and left-aligned on wide windows.
      return Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ConfigInstanceCard(instance: instances.single, active: true),
        ),
      );
    }
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: instances.length,
        separatorBuilder: (_, _) => const SizedBox(width: EtSpace.x3),
        itemBuilder: (context, index) {
          final instance = instances[index];
          final active = instance.id == activeId;
          return SizedBox(
            width: 280,
            child: ConfigInstanceCard(
              instance: instance,
              active: active,
              onTap: enabled && !active ? () => onSelect(instance.id) : null,
            ),
          );
        },
      ),
    );
  }
}

/// One network config card. Tap target is the whole card; the trailing chevron
/// only appears when switching is possible.
class ConfigInstanceCard extends StatelessWidget {
  const ConfigInstanceCard({
    super.key,
    required this.instance,
    required this.active,
    this.onTap,
  });

  final NetworkInstance instance;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.et;
    final text = Theme.of(context).textTheme;
    final tinted = Color.alphaBlend(
      p.scheme.primary.withValues(alpha: p.isDark ? 0.18 : 0.10),
      p.scheme.surfaceContainerLow,
    );
    return EtSurface(
      onTap: onTap,
      color: active ? tinted : p.scheme.surfaceContainerLow,
      borderColor: active
          ? p.scheme.primary.withValues(alpha: 0.32)
          : null,
      padding: const EdgeInsets.fromLTRB(
        EtSpace.x3,
        EtSpace.x3,
        EtSpace.x3,
        EtSpace.x3,
      ),
      child: Row(
        children: [
          EtAvatar(name: instance.config.instanceName, size: 44),
          const SizedBox(width: EtSpace.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  instance.config.instanceName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: p.text,
                  ),
                ),
                const SizedBox(height: EtSpace.x1),
                Wrap(
                  spacing: EtSpace.x2,
                  runSpacing: EtSpace.x1,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    EtBadge(
                      label: instance.config.networkName,
                      tone: EtTone.accent,
                      icon: Symbols.lan,
                    ),
                    if (active)
                      EtBadge(
                        label: I18n.t('Active'),
                        tone: EtTone.success,
                        icon: Symbols.check_circle,
                      )
                    else
                      EtBadge(label: instance.source, tone: EtTone.neutral),
                  ],
                ),
              ],
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: EtSpace.x1),
            Icon(Symbols.chevron_right, color: p.text2),
          ],
        ],
      ),
    );
  }
}
