import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../../core/theme/theme.dart';
import '../../core/ui/ui.dart';
import 'config_validation.dart';
import 'config_widgets.dart';

/// M3 bottom sheet used to add one [PortForward]. Validation is specific and
/// inline; the sheet only pops a value when the rule is valid.
class PortForwardSheet extends StatefulWidget {
  const PortForwardSheet({super.key, required this.existing});

  final List<PortForward> existing;

  @override
  State<PortForwardSheet> createState() => _PortForwardSheetState();
}

class _PortForwardSheetState extends State<PortForwardSheet> {
  String _proto = 'tcp';
  final _local = TextEditingController();
  final _remote = TextEditingController();
  Map<String, String> _errors = const {};

  @override
  void dispose() {
    _local.dispose();
    _remote.dispose();
    super.dispose();
  }

  void _submit() {
    final rule = PortForward(
      proto: _proto,
      local: _local.text.trim(),
      remote: _remote.text.trim(),
    );
    final errors = validatePortForwardFields(rule, existing: widget.existing);
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
          Text('Add port forward', style: theme.textTheme.titleLarge),
          const SizedBox(height: EtSpace.x1),
          Text(
            'The core listens on the local address and forwards to the remote '
            'address inside the mesh.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: EtSpace.x6),
          ConfigSegmentedField<String>(
            label: 'Protocol',
            value: _proto,
            options: const [
              ConfigChoice(value: 'tcp', label: 'TCP'),
              ConfigChoice(value: 'udp', label: 'UDP'),
            ],
            onChanged: (next) => setState(() => _proto = next),
          ),
          const SizedBox(height: EtSpace.x5),
          EtTextField(
            key: const Key('port-forward-local'),
            label: 'Local address',
            controller: _local,
            mono: true,
            hint: '127.0.0.1:8080',
            helper: 'Host and port to listen on.',
            error: _errors['local'],
            onChanged: (_) {
              if (_errors.containsKey('local')) {
                setState(() => _errors = Map.of(_errors)..remove('local'));
              }
            },
          ),
          const SizedBox(height: EtSpace.x4),
          EtTextField(
            key: const Key('port-forward-remote'),
            label: 'Remote address',
            controller: _remote,
            mono: true,
            hint: '10.144.0.2:80',
            helper: 'Peer address and port to forward to.',
            error: _errors['remote'],
            onChanged: (_) {
              if (_errors.containsKey('remote')) {
                setState(() => _errors = Map.of(_errors)..remove('remote'));
              }
            },
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
