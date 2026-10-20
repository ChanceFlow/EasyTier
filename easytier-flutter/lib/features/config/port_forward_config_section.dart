import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../../core/theme/theme.dart';
import '../../core/ui/ui.dart';
import 'config_form.dart';
import 'config_validation.dart';
import 'config_widgets.dart';

/// Port forward: proxy networks plus the published local→remote forwards.
/// Rows are M3 `ListTile`s; they are added through a validated bottom sheet, so
/// a stored row is always valid. The list-level error covers a configuration
/// edited elsewhere.
class PortForwardConfigSection extends StatelessWidget {
  const PortForwardConfigSection({
    super.key,
    required this.form,
    required this.errors,
    required this.enabled,
    required this.onTextChanged,
    required this.onValuesChanged,
    required this.onAdd,
    required this.onDelete,
  });

  final ConfigForm form;
  final Map<String, String> errors;
  final bool enabled;
  final ValueChanged<String> onTextChanged;
  final ValueChanged<NetworkConfig> onValuesChanged;
  final VoidCallback onAdd;
  final ValueChanged<int> onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final forwards = form.values.portForwards;

    return ConfigStack(
      children: [
        Text(
          'Expose a local port to an address inside the mesh. Rules only apply '
          'while the tunnel is up.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        EtTextField(
          key: const Key('config-field-proxy-cidrs'),
          label: 'Proxy networks (CIDR)',
          controller: form.proxyCidrs,
          mono: true,
          maxLines: 2,
          enabled: enabled,
          hint: '192.168.1.0/24',
          helper: 'Subnets advertised through a peer. One CIDR per line; leave '
              'empty to advertise nothing.',
          error: errors[ConfigField.proxyCidrs],
          onChanged: (_) => onTextChanged(ConfigField.proxyCidrs),
        ),
        ConfigListHeader(
          title: 'Port forwards',
          addLabel: 'Add port forward',
          count: forwards.length,
          onAdd: enabled ? onAdd : null,
        ),
        if (forwards.isEmpty)
          const EtBanner(
            tone: EtTone.neutral,
            icon: Symbols.swap_horiz,
            title: 'No port forwards',
            message: 'Add a rule to publish a local service on the mesh.',
          )
        else
          Column(
            children: [
              for (var i = 0; i < forwards.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                _PortForwardTile(
                  rule: forwards[i],
                  enabled: enabled,
                  onDelete: () => onDelete(i),
                ),
              ],
            ],
          ),
        if (errors[ConfigField.portForwards] != null)
          ConfigErrorText(message: errors[ConfigField.portForwards]!),
      ],
    );
  }
}

class _PortForwardTile extends StatelessWidget {
  const _PortForwardTile({
    required this.rule,
    required this.enabled,
    required this.onDelete,
  });

  final PortForward rule;
  final bool enabled;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      minLeadingWidth: 0,
      horizontalTitleGap: EtSpace.x3,
      leading: EtBadge(
        label: rule.proto.toUpperCase(),
        tone: rule.proto == 'udp' ? EtTone.accent : EtTone.info,
      ),
      title: Wrap(
        spacing: EtSpace.x2,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            rule.local,
            style: EtText.mono(size: EtType.bodySm, color: scheme.onSurface),
          ),
          Icon(
            Symbols.arrow_forward,
            size: 16,
            color: scheme.onSurfaceVariant,
          ),
          Text(
            rule.remote,
            style: EtText.mono(
              size: EtType.bodySm,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Symbols.delete),
        tooltip: 'Delete port forward',
        onPressed: enabled ? onDelete : null,
      ),
    );
  }
}
