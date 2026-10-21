import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';
import 'package:flutter/services.dart';

import '../../core/models/models.dart';
import '../../core/theme/theme.dart';
import '../../core/ui/ui.dart';

/// Shareable invitation text for the current network. Secrets are opt-in so a
/// screenshot/text can be shared without leaking the key by accident.
class ShareNetworkSheet extends StatefulWidget {
  const ShareNetworkSheet({super.key, required this.config});

  final NetworkConfig config;

  @override
  State<ShareNetworkSheet> createState() => _ShareNetworkSheetState();
}

class _ShareNetworkSheetState extends State<ShareNetworkSheet> {
  bool _includeSecret = false;

  String get _invite {
    final config = widget.config;
    final buffer = StringBuffer()
      ..writeln('Join my EasyTier network')
      ..writeln()
      ..writeln('Network: ${config.networkName}')
      ..writeln('Instance: ${config.instanceName}');
    if (_includeSecret) {
      buffer.writeln(
        'Secret: ${config.networkSecret.isEmpty ? '(none)' : config.networkSecret}',
      );
    } else {
      buffer.writeln('Secret: ask me privately');
    }
    if (config.listenerUrls.isNotEmpty) {
      buffer.writeln('Peer: ${config.listenerUrls.first}');
    }
    return buffer.toString().trimRight();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _invite));
    if (!mounted) return;
    EtHaptics.selection();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Invitation copied to clipboard.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.et;
    final theme = Theme.of(context);
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
          Row(
            children: [
              const EtIconBadge(icon: Symbols.share, tone: EtTone.accent, size: 36),
              const SizedBox(width: EtSpace.x3),
              Expanded(
                child: Text(
                  I18n.t('Share network'),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: EtSpace.x2),
          Text(
            'Send this to a device that should join “${widget.config.networkName}”.',
            style: theme.textTheme.bodyMedium?.copyWith(color: p.text2),
          ),
          const SizedBox(height: EtSpace.x3),
          SwitchListTile(
            key: const Key('share-include-secret'),
            contentPadding: EdgeInsets.zero,
            value: _includeSecret,
            onChanged: (value) => setState(() => _includeSecret = value),
            title: Text(I18n.t('Include network secret')),
            subtitle: Text(
              'Only share with people you trust.',
              style: theme.textTheme.bodySmall?.copyWith(color: p.text2),
            ),
          ),
          const SizedBox(height: EtSpace.x2),
          EtSurface(
            color: p.sunken,
            radius: EtRadius.card,
            padding: const EdgeInsets.all(EtSpace.x4),
            child: SelectableText(
              _invite,
              style: EtText.mono(
                size: EtType.bodySm,
                height: 1.6,
                color: p.text,
              ),
            ),
          ),
          const SizedBox(height: EtSpace.x4),
          FilledButton.icon(
            key: const Key('share-copy'),
            onPressed: _copy,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: const StadiumBorder(),
            ),
            icon: const Icon(Symbols.content_copy, size: 18),
            label: Text(I18n.t('Copy invitation')),
          ),
        ],
      ),
    );
  }
}
