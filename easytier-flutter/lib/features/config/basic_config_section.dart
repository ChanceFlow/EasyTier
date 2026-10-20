import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../../core/ui/ui.dart';
import 'config_form.dart';
import 'config_validation.dart';
import 'config_widgets.dart';

/// Basic: identity, network name/secret, addressing and the peer/listener URL
/// lists. The first section, expanded by default.
class BasicConfigSection extends StatelessWidget {
  const BasicConfigSection({
    super.key,
    required this.form,
    required this.errors,
    required this.enabled,
    required this.revealSecret,
    required this.onToggleRevealSecret,
    required this.onTextChanged,
    required this.onValuesChanged,
  });

  final ConfigForm form;
  final Map<String, String> errors;
  final bool enabled;
  final bool revealSecret;
  final VoidCallback onToggleRevealSecret;
  final ValueChanged<String> onTextChanged;
  final ValueChanged<NetworkConfig> onValuesChanged;

  @override
  Widget build(BuildContext context) {
    final values = form.values;
    return ConfigStack(
      children: [
        ConfigTwoColumn(
          children: [
            EtTextField(
              key: const Key('config-field-instance-name'),
              label: 'Instance name',
              controller: form.instanceName,
              mono: true,
              enabled: enabled,
              hint: 'office-mesh',
              helper: 'Identifier for this configuration on the device.',
              error: errors[ConfigField.instanceName],
              onChanged: (_) => onTextChanged(ConfigField.instanceName),
            ),
            EtTextField(
              key: const Key('config-field-hostname'),
              label: 'Hostname',
              controller: form.hostname,
              mono: true,
              enabled: enabled,
              hint: 'chance-desktop',
              helper: 'Shown to peers in Devices.',
              error: errors[ConfigField.hostname],
              onChanged: (_) => onTextChanged(ConfigField.hostname),
            ),
          ],
        ),
        ConfigTwoColumn(
          children: [
            EtTextField(
              key: const Key('config-field-network-name'),
              label: 'Network name',
              controller: form.networkName,
              enabled: enabled,
              hint: 'EasyTier Home',
              helper: 'Every peer that should join this mesh uses the same name.',
              error: errors[ConfigField.networkName],
              onChanged: (_) => onTextChanged(ConfigField.networkName),
            ),
            EtTextField(
              key: const Key('config-field-network-secret'),
              label: 'Network secret',
              controller: form.networkSecret,
              mono: true,
              obscure: !revealSecret,
              enabled: enabled,
              hint: 'Shared secret',
              helper: 'Shared by every peer. Stored locally, never uploaded.',
              error: errors[ConfigField.networkSecret],
              suffix: EtIconButton(
                icon: revealSecret
                    ? Symbols.visibility_off
                    : Symbols.visibility,
                tooltip: revealSecret ? 'Hide network secret' : 'Reveal network secret',
                onPressed: onToggleRevealSecret,
              ),
              onChanged: (_) => onTextChanged(ConfigField.networkSecret),
            ),
          ],
        ),
        EtSwitchRow(
          key: const Key('config-switch-dhcp'),
          title: 'DHCP',
          subtitle: 'Ask the network for a virtual IPv4 address.',
          value: values.dhcp,
          enabled: enabled,
          onChanged: (next) => onValuesChanged(values.copyWith(dhcp: next)),
        ),
        if (!values.dhcp)
          ConfigTwoColumn(
            children: [
              EtTextField(
                key: const Key('config-field-virtual-ipv4'),
                label: 'Virtual IPv4',
                controller: form.virtualIpv4,
                mono: true,
                enabled: enabled,
                keyboardType: TextInputType.number,
                hint: '10.144.0.17',
                helper: 'Static address inside the mesh subnet.',
                error: errors[ConfigField.virtualIpv4],
                onChanged: (_) => onTextChanged(ConfigField.virtualIpv4),
              ),
              ConfigSelectField<int>(
                key: const Key('config-field-prefix-length'),
                label: 'Prefix length',
                value: values.networkLength,
                enabled: enabled,
                helper: 'Size of the mesh subnet.',
                error: errors[ConfigField.networkLength],
                options: const [
                  ConfigChoice(value: 8, label: '/8'),
                  ConfigChoice(value: 16, label: '/16'),
                  ConfigChoice(value: 24, label: '/24'),
                  ConfigChoice(value: 32, label: '/32'),
                ],
                onChanged: (next) => onValuesChanged(
                  values.copyWith(networkLength: next),
                ),
              ),
            ],
          ),
        EtTextField(
          key: const Key('config-field-peer-urls'),
          label: 'Peer URLs',
          controller: form.peerUrls,
          mono: true,
          maxLines: 3,
          enabled: enabled,
          hint: 'tcp://public.easytier.top:11010',
          helper: 'One URL per line. Leave empty to depend on public relays only.',
          error: errors[ConfigField.peerUrls],
          onChanged: (_) => onTextChanged(ConfigField.peerUrls),
        ),
        EtTextField(
          key: const Key('config-field-listener-urls'),
          label: 'Listener URLs',
          controller: form.listenerUrls,
          mono: true,
          maxLines: 3,
          enabled: enabled,
          hint: 'tcp://0.0.0.0:11010',
          helper: 'Where other peers can reach this device. One URL per line.',
          error: errors[ConfigField.listenerUrls],
          onChanged: (_) => onTextChanged(ConfigField.listenerUrls),
        ),
      ],
    );
  }
}
