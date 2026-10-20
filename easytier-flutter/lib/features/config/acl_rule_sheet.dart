import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../../core/theme/theme.dart';
import '../../core/ui/ui.dart';
import 'config_validation.dart';
import 'config_widgets.dart';

/// M3 bottom sheet used to add one [AclRule]. Defaults are the permissive rule
/// (`allow 0.0.0.0/0 → 0.0.0.0/0`), so adding a rule is a deliberate act.
class AclRuleSheet extends StatefulWidget {
  const AclRuleSheet({super.key});

  @override
  State<AclRuleSheet> createState() => _AclRuleSheetState();
}

class _AclRuleSheetState extends State<AclRuleSheet> {
  String _action = 'allow';
  String _chain = 'inbound';
  String _protocol = 'tcp';
  final _source = TextEditingController(text: '0.0.0.0/0');
  final _destination = TextEditingController(text: '0.0.0.0/0');
  final _ports = TextEditingController();
  final _comment = TextEditingController();
  Map<String, String> _errors = const {};

  @override
  void dispose() {
    _source.dispose();
    _destination.dispose();
    _ports.dispose();
    _comment.dispose();
    super.dispose();
  }

  void _submit() {
    final rule = AclRule(
      action: _action,
      protocol: _protocol,
      chain: _chain,
      source: _source.text.trim(),
      destination: _destination.text.trim(),
      ports: _ports.text.trim(),
      comment: _comment.text.trim(),
    );
    final errors = validateAclRuleFields(rule);
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      return;
    }
    Navigator.of(context).pop(rule);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(EtSpace.x6, 0, EtSpace.x6, EtSpace.x6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Add ACL rule', style: theme.textTheme.titleLarge),
          const SizedBox(height: EtSpace.x1),
          Text(
            'Rules run top to bottom per chain; the first match wins.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: EtSpace.x6),
          ConfigTwoColumn(
            children: [
              ConfigSegmentedField<String>(
                label: 'Action',
                value: _action,
                options: const [
                  ConfigChoice(value: 'allow', label: 'Allow'),
                  ConfigChoice(value: 'deny', label: 'Deny'),
                ],
                onChanged: (next) => setState(() => _action = next),
              ),
              ConfigSegmentedField<String>(
                label: 'Chain',
                value: _chain,
                options: const [
                  ConfigChoice(value: 'inbound', label: 'Inbound'),
                  ConfigChoice(value: 'outbound', label: 'Outbound'),
                ],
                onChanged: (next) => setState(() => _chain = next),
              ),
            ],
          ),
          const SizedBox(height: EtSpace.x5),
          ConfigSelectField<String>(
            label: 'Protocol',
            value: _protocol,
            options: const [
              ConfigChoice(value: 'tcp', label: 'tcp'),
              ConfigChoice(value: 'udp', label: 'udp'),
              ConfigChoice(value: 'icmp', label: 'icmp'),
              ConfigChoice(value: 'any', label: 'any'),
            ],
            onChanged: (next) => setState(() => _protocol = next),
          ),
          const SizedBox(height: EtSpace.x5),
          ConfigTwoColumn(
            children: [
              EtTextField(
                key: const Key('acl-source'),
                label: 'Source CIDR',
                controller: _source,
                mono: true,
                hint: '0.0.0.0/0',
                helper: 'Any source is 0.0.0.0/0.',
                error: _errors['source'],
                onChanged: (_) {
                  if (_errors.containsKey('source')) {
                    setState(() => _errors = Map.of(_errors)..remove('source'));
                  }
                },
              ),
              EtTextField(
                key: const Key('acl-destination'),
                label: 'Destination CIDR',
                controller: _destination,
                mono: true,
                hint: '10.144.0.0/24',
                helper: 'Any destination is 0.0.0.0/0.',
                error: _errors['destination'],
                onChanged: (_) {
                  if (_errors.containsKey('destination')) {
                    setState(
                      () => _errors = Map.of(_errors)..remove('destination'),
                    );
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: EtSpace.x4),
          ConfigTwoColumn(
            children: [
              EtTextField(
                key: const Key('acl-ports'),
                label: 'Ports',
                controller: _ports,
                mono: true,
                hint: '80,443,8000-8100',
                helper: 'Empty means any port.',
                error: _errors['ports'],
                onChanged: (_) {
                  if (_errors.containsKey('ports')) {
                    setState(() => _errors = Map.of(_errors)..remove('ports'));
                  }
                },
              ),
              EtTextField(
                key: const Key('acl-comment'),
                label: 'Comment',
                controller: _comment,
                hint: 'Optional note',
                onChanged: (_) {},
              ),
            ],
          ),
          const SizedBox(height: EtSpace.x6),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: EtSpace.x2),
              FilledButton(onPressed: _submit, child: const Text('Add')),
            ],
          ),
        ],
      ),
    );
  }
}
