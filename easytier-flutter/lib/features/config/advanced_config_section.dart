import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';

import '../../core/models/models.dart';
import '../../core/ui/ui.dart';
import 'config_form.dart';
import 'config_validation.dart';
import 'config_widgets.dart';

/// Advanced: datapath, routing and privacy switches plus the two scalar fields
/// that only experts touch (MTU, TUN device name). Every field is present; the
/// grouping is a caption, not a second disclosure level.
class AdvancedConfigSection extends StatelessWidget {
  const AdvancedConfigSection({
    super.key,
    required this.form,
    required this.errors,
    required this.enabled,
    required this.onTextChanged,
    required this.onValuesChanged,
  });

  final ConfigForm form;
  final Map<String, String> errors;
  final bool enabled;
  final ValueChanged<String> onTextChanged;
  final ValueChanged<NetworkConfig> onValuesChanged;

  @override
  Widget build(BuildContext context) {
    final values = form.values;

    Widget toggle({
      required String id,
      required String title,
      required String subtitle,
      required bool value,
      required NetworkConfig Function(bool) apply,
    }) {
      return EtSwitchRow(
        key: Key('config-switch-$id'),
        title: title,
        subtitle: subtitle,
        value: value,
        enabled: enabled,
        onChanged: (next) => onValuesChanged(apply(next)),
      );
    }

    return ConfigStack(
      children: [
        ConfigSubhead(label: I18n.t('Transport')),
        ConfigTwoColumn(
          children: [
            toggle(
              id: 'multi-thread',
              title: 'Multi-thread',
              subtitle: 'Run the data plane on a thread pool.',
              value: values.multiThread,
              apply: (next) => values.copyWith(multiThread: next),
            ),
            toggle(
              id: 'disable-encryption',
              title: I18n.t('Disable encryption'),
              subtitle: 'Plaintext transport. Only for closed test labs.',
              value: values.disableEncryption,
              apply: (next) => values.copyWith(disableEncryption: next),
            ),
            toggle(
              id: 'disable-ipv6',
              title: I18n.t('Disable IPv6'),
              subtitle: I18n.t('Do not assign or route IPv6 addresses.'),
              value: values.disableIpv6,
              apply: (next) => values.copyWith(disableIpv6: next),
            ),
            toggle(
              id: 'use-smoltcp',
              title: 'Use smoltcp',
              subtitle: 'Userspace TCP stack; no kernel driver needed.',
              value: values.useSmoltcp,
              apply: (next) => values.copyWith(useSmoltcp: next),
            ),
            toggle(
              id: 'no-tun',
              title: 'No TUN',
              subtitle: 'Run without creating a TUN device.',
              value: values.noTun,
              apply: (next) => values.copyWith(noTun: next),
            ),
            toggle(
              id: 'bind-device',
              title: I18n.t('Bind to device'),
              subtitle: 'Pin the tunnel to the physical interface.',
              value: values.bindDevice,
              apply: (next) => values.copyWith(bindDevice: next),
            ),
          ],
        ),
        ConfigTwoColumn(
          children: [
            EtTextField(
              key: const Key('config-field-mtu'),
              label: I18n.t('MTU'),
              controller: form.mtu,
              mono: true,
              enabled: enabled,
              keyboardType: TextInputType.number,
              hint: 'Leave empty for the core default',
              helper: '576–9000. Empty keeps the default.',
              error: errors[ConfigField.mtu],
              onChanged: (_) => onTextChanged(ConfigField.mtu),
            ),
            EtTextField(
              key: const Key('config-field-dev-name'),
              label: 'TUN device name',
              controller: form.devName,
              mono: true,
              enabled: enabled,
              hint: 'Auto',
              helper: 'Optional. Linux allows up to 15 characters.',
              error: errors[ConfigField.devName],
              onChanged: (_) => onTextChanged(ConfigField.devName),
            ),
          ],
        ),
        ConfigSubhead(label: I18n.t('Routing')),
        ConfigTwoColumn(
          children: [
            toggle(
              id: 'latency-first',
              title: 'Latency first',
              subtitle: 'Prefer the fastest path over the highest throughput.',
              value: values.latencyFirst,
              apply: (next) => values.copyWith(latencyFirst: next),
            ),
            toggle(
              id: 'disable-p2p',
              title: I18n.t('Disable P2P'),
              subtitle: 'Relay everything through the selected peer.',
              value: values.disableP2p,
              apply: (next) => values.copyWith(disableP2p: next),
            ),
            toggle(
              id: 'p2p-only',
              title: 'P2P only',
              subtitle: 'Never relay through another peer.',
              value: values.p2pOnly,
              apply: (next) => values.copyWith(p2pOnly: next),
            ),
            toggle(
              id: 'relay-all-peer-rpc',
              title: 'Relay all peer RPC',
              subtitle: 'Forward peer RPC through this node.',
              value: values.relayAllPeerRpc,
              apply: (next) => values.copyWith(relayAllPeerRpc: next),
            ),
            toggle(
              id: 'enable-exit-node',
              title: 'Exit node',
              subtitle: 'Offer this node as a default route for peers.',
              value: values.enableExitNode,
              apply: (next) => values.copyWith(enableExitNode: next),
            ),
          ],
        ),
        const ConfigSubhead(label: 'Privacy & DNS'),
        ConfigTwoColumn(
          children: [
            toggle(
              id: 'enable-private-mode',
              title: 'Private mode',
              subtitle: 'Restrict the instance to peers of this network.',
              value: values.enablePrivateMode,
              apply: (next) => values.copyWith(enablePrivateMode: next),
            ),
            toggle(
              id: 'enable-magic-dns',
              title: 'Magic DNS',
              subtitle: 'Resolve peer hostnames through the mesh DNS.',
              value: values.enableMagicDns,
              apply: (next) => values.copyWith(enableMagicDns: next),
            ),
          ],
        ),
      ],
    );
  }
}
