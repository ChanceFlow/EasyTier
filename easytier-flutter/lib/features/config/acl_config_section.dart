import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';

import '../../core/models/models.dart';
import '../../core/theme/theme.dart';
import '../../core/ui/ui.dart';
import 'config_form.dart';
import 'config_validation.dart';
import 'config_widgets.dart';

/// ACL: allow/deny rules per chain, rendered as M3 `ListTile`s. Rows are added
/// through a validated sheet and cannot be edited in place yet (delete +
/// re-add is the v1 flow).
class AclConfigSection extends StatelessWidget {
  const AclConfigSection({
    super.key,
    required this.form,
    required this.errors,
    required this.enabled,
    required this.onValuesChanged,
    required this.onAdd,
    required this.onDelete,
  });

  final ConfigForm form;
  final Map<String, String> errors;
  final bool enabled;
  final ValueChanged<NetworkConfig> onValuesChanged;
  final VoidCallback onAdd;
  final ValueChanged<int> onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final rules = form.values.aclRules;

    return ConfigStack(
      children: [
        Text(
          'Rules run top to bottom per chain; the first match wins. Traffic that '
          'matches no rule is allowed.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        ConfigListHeader(
          title: I18n.t('ACL rules'),
          addLabel: I18n.t('Add ACL rule'),
          count: rules.length,
          onAdd: enabled ? onAdd : null,
        ),
        if (rules.isEmpty)
          EtBanner(
            tone: EtTone.neutral,
            icon: Symbols.shield,
            title: 'No ACL rules',
            message: I18n.t('Both chains currently allow all traffic.'),
          )
        else
          Column(
            children: [
              for (var i = 0; i < rules.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                _AclRuleTile(
                  rule: rules[i],
                  enabled: enabled,
                  onDelete: () => onDelete(i),
                ),
              ],
            ],
          ),
        if (errors[ConfigField.aclRules] != null)
          ConfigErrorText(message: errors[ConfigField.aclRules]!),
      ],
    );
  }
}

class _AclRuleTile extends StatelessWidget {
  const _AclRuleTile({
    required this.rule,
    required this.enabled,
    required this.onDelete,
  });

  final AclRule rule;
  final bool enabled;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final allow = rule.action == 'allow';
    final details = <String>[
      if (rule.ports.isNotEmpty) 'Ports ${rule.ports}',
      if (rule.comment.isNotEmpty) rule.comment,
    ];

    return ListTile(
      contentPadding: EdgeInsets.zero,
      minLeadingWidth: 0,
      horizontalTitleGap: EtSpace.x3,
      isThreeLine: details.isNotEmpty,
      leading: EtBadge(
        label: rule.action.toUpperCase(),
        tone: allow ? EtTone.accent : EtTone.danger,
      ),
      title: Wrap(
        spacing: EtSpace.x2,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          EtBadge(label: rule.chain, tone: EtTone.neutral),
          Text(
            rule.protocol.toUpperCase(),
            style: EtText.mono(
              size: EtType.caption,
              color: scheme.onSurfaceVariant,
            ),
          ),
          Text(
            rule.source,
            style: EtText.mono(size: EtType.bodySm, color: scheme.onSurface),
          ),
          Icon(
            Symbols.arrow_forward,
            size: 16,
            color: scheme.onSurfaceVariant,
          ),
          Text(
            rule.destination,
            style: EtText.mono(
              size: EtType.bodySm,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      subtitle: details.isEmpty
          ? null
          : Text(
              details.join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
      trailing: IconButton(
        icon: const Icon(Symbols.delete),
        tooltip: I18n.t('Delete ACL rule'),
        onPressed: enabled ? onDelete : null,
      ),
    );
  }
}
