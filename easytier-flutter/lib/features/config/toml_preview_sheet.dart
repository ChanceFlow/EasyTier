import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/models.dart';
import '../../core/theme/theme.dart';
import '../../core/ui/ui.dart';

/// Read-only preview of the configuration as human-readable TOML. It is
/// explicitly labelled as a UI readback: the core owns the authoritative
/// serialization. Rendered in the platform monospace on an M3 `surfaceContainer` block.
class TomlPreviewSheet extends StatelessWidget {
  const TomlPreviewSheet({super.key, required this.config});

  final NetworkConfig config;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final p = context.et;
    final toml = config.debugToml();
    return Padding(
      padding: const EdgeInsets.fromLTRB(EtSpace.x6, 0, EtSpace.x6, EtSpace.x6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const EtIconBadge(
                icon: Symbols.code,
                tone: EtTone.tertiary,
                size: 36,
              ),
              const SizedBox(width: EtSpace.x3),
              Expanded(
                child: Text(
                  'Effective configuration',
                  style: theme.textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: EtSpace.x2),
          Text(
            'UI readback only — the core serializes the authoritative TOML when '
            'the network runs.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: EtSpace.x4),
          // Expressive data well: the lowest tonal surface, platform mono, and
          // internal horizontal scrolling so long tokens never wrap mid-value.
          EtSurface(
            color: p.sunken,
            radius: EtRadius.card,
            padding: const EdgeInsets.all(EtSpace.x4),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: SingleChildScrollView(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SelectableText(
                    toml,
                    style: EtText.mono(
                      size: EtType.bodySm,
                      color: scheme.onSurface,
                      height: 1.6,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: EtSpace.x4),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Secret is redacted.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _copy(context, toml),
                icon: const Icon(Symbols.content_copy, size: 18),
                label: const Text('Copy'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _copy(BuildContext context, String toml) async {
    await Clipboard.setData(ClipboardData(text: toml));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('TOML copied to clipboard.')),
    );
  }
}
