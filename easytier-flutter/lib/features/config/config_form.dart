import 'package:flutter/widgets.dart';

import '../../core/models/models.dart';
import 'config_validation.dart';

/// The editable draft of one [NetworkConfig].
///
/// Text fields live in [TextEditingController]s so typing never rebuilds the
/// model mid-keystroke; booleans, enums and the list fields live in [values].
/// [config] recombines both into a fresh [NetworkConfig] — the live state is
/// never mutated, which keeps "Reset" and "unsaved changes" honest.
class ConfigForm {
  ConfigForm(NetworkConfig initial) : values = initial {
    reseed(initial);
  }

  /// Boolean, enum and list fields. Its text fields are stale on purpose: the
  /// controllers below are the only source of truth for text.
  NetworkConfig values;

  final TextEditingController instanceName = TextEditingController();
  final TextEditingController hostname = TextEditingController();
  final TextEditingController networkName = TextEditingController();
  final TextEditingController networkSecret = TextEditingController();
  final TextEditingController virtualIpv4 = TextEditingController();
  final TextEditingController peerUrls = TextEditingController();
  final TextEditingController listenerUrls = TextEditingController();
  final TextEditingController mtu = TextEditingController();
  final TextEditingController devName = TextEditingController();
  final TextEditingController proxyCidrs = TextEditingController();

  bool _disposed = false;

  NetworkConfig get config => NetworkConfig(
    instanceName: instanceName.text.trim(),
    hostname: hostname.text.trim(),
    networkName: networkName.text.trim(),
    networkSecret: networkSecret.text,
    dhcp: values.dhcp,
    virtualIpv4: virtualIpv4.text.trim(),
    networkLength: values.networkLength,
    peerUrls: _lines(peerUrls.text),
    listenerUrls: _lines(listenerUrls.text),
    disableEncryption: values.disableEncryption,
    disableIpv6: values.disableIpv6,
    mtu: _parseMtu(),
    latencyFirst: values.latencyFirst,
    multiThread: values.multiThread,
    devName: devName.text.trim(),
    useSmoltcp: values.useSmoltcp,
    bindDevice: values.bindDevice,
    noTun: values.noTun,
    enablePrivateMode: values.enablePrivateMode,
    enableMagicDns: values.enableMagicDns,
    disableP2p: values.disableP2p,
    p2pOnly: values.p2pOnly,
    relayAllPeerRpc: values.relayAllPeerRpc,
    enableExitNode: values.enableExitNode,
    proxyCidrs: _lines(proxyCidrs.text),
    portForwards: values.portForwards,
    aclRules: values.aclRules,
  );

  /// Replaces the draft with [next], keeping the same controller instances so
  /// field focus and undo history are not thrown away unnecessarily.
  void reseed(NetworkConfig next) {
    values = next;
    instanceName.text = next.instanceName;
    hostname.text = next.hostname;
    networkName.text = next.networkName;
    networkSecret.text = next.networkSecret;
    virtualIpv4.text = next.virtualIpv4;
    peerUrls.text = next.peerUrls.join('\n');
    listenerUrls.text = next.listenerUrls.join('\n');
    mtu.text = next.mtu?.toString() ?? '';
    devName.text = next.devName;
    proxyCidrs.text = next.proxyCidrs.join('\n');
  }

  /// Applies a change to a non-text field (switch, dropdown, list row).
  void updateValues(NetworkConfig next) {
    values = next;
  }

  Map<String, String> validate() =>
      validateNetworkConfigFields(config, mtuText: mtu.text);

  int? _parseMtu() {
    final text = mtu.text.trim();
    if (text.isEmpty) return null;
    return int.tryParse(text);
  }

  /// Disposing is idempotent: a retired draft may be disposed by the next
  /// frame after the widget tree has detached from its controllers.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    instanceName.dispose();
    hostname.dispose();
    networkName.dispose();
    networkSecret.dispose();
    virtualIpv4.dispose();
    peerUrls.dispose();
    listenerUrls.dispose();
    mtu.dispose();
    devName.dispose();
    proxyCidrs.dispose();
  }
}

List<String> _lines(String text) => text
    .split('\n')
    .map((line) => line.trim())
    .where((line) => line.isNotEmpty)
    .toList(growable: false);
