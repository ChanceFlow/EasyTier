import '../../core/models/models.dart';

/// Field identifiers shared by the form, the inline errors and the error
/// summary. They mirror the [NetworkConfig] field names so a summary row can
/// name the exact field it points at.
abstract final class ConfigField {
  static const instanceName = 'instanceName';
  static const hostname = 'hostname';
  static const networkName = 'networkName';
  static const networkSecret = 'networkSecret';
  static const virtualIpv4 = 'virtualIpv4';
  static const networkLength = 'networkLength';
  static const peerUrls = 'peerUrls';
  static const listenerUrls = 'listenerUrls';
  static const mtu = 'mtu';
  static const devName = 'devName';
  static const proxyCidrs = 'proxyCidrs';
  static const portForwards = 'portForwards';
  static const aclRules = 'aclRules';
}

/// The four disclosure sections, as indices. Used to auto-open the section that
/// holds an invalid field when the user submits an invalid form.
abstract final class ConfigSectionIndex {
  static const basic = 0;
  static const advanced = 1;
  static const portForward = 2;
  static const acl = 3;
}

/// Canonical order of the fields in the error summary. The summary follows the
/// visual order, top to bottom.
const List<String> kConfigFieldOrder = [
  ConfigField.instanceName,
  ConfigField.hostname,
  ConfigField.networkName,
  ConfigField.networkSecret,
  ConfigField.virtualIpv4,
  ConfigField.networkLength,
  ConfigField.peerUrls,
  ConfigField.listenerUrls,
  ConfigField.mtu,
  ConfigField.devName,
  ConfigField.proxyCidrs,
  ConfigField.portForwards,
  ConfigField.aclRules,
];

/// Human labels used in the summary ("Virtual IPv4: segment 4 …").
const Map<String, String> kConfigFieldLabels = {
  ConfigField.instanceName: 'Instance name',
  ConfigField.hostname: 'Hostname',
  ConfigField.networkName: 'Network name',
  ConfigField.networkSecret: 'Network secret',
  ConfigField.virtualIpv4: 'Virtual IPv4',
  ConfigField.networkLength: 'Prefix length',
  ConfigField.peerUrls: 'Peer URLs',
  ConfigField.listenerUrls: 'Listener URLs',
  ConfigField.mtu: 'MTU',
  ConfigField.devName: 'Device name',
  ConfigField.proxyCidrs: 'Proxy networks',
  ConfigField.portForwards: 'Port forwards',
  ConfigField.aclRules: 'ACL rules',
};

/// The section a field belongs to, so submitting can reveal where the error is.
const Map<String, int> kConfigFieldSection = {
  ConfigField.instanceName: ConfigSectionIndex.basic,
  ConfigField.hostname: ConfigSectionIndex.basic,
  ConfigField.networkName: ConfigSectionIndex.basic,
  ConfigField.networkSecret: ConfigSectionIndex.basic,
  ConfigField.virtualIpv4: ConfigSectionIndex.basic,
  ConfigField.networkLength: ConfigSectionIndex.basic,
  ConfigField.peerUrls: ConfigSectionIndex.basic,
  ConfigField.listenerUrls: ConfigSectionIndex.basic,
  ConfigField.mtu: ConfigSectionIndex.advanced,
  ConfigField.devName: ConfigSectionIndex.advanced,
  ConfigField.proxyCidrs: ConfigSectionIndex.portForward,
  ConfigField.portForwards: ConfigSectionIndex.portForward,
  ConfigField.aclRules: ConfigSectionIndex.acl,
};

const List<String> kUrlSchemes = ['tcp', 'udp', 'wg', 'ws', 'wss'];

// ---------------------------------------------------------------------------
// Scalar fields.
// ---------------------------------------------------------------------------

String? validateInstanceName(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return 'Instance name is required.';
  if (value.length > 64) {
    return 'Instance name is ${value.length} characters — the maximum is 64.';
  }
  if (!RegExp(r'[A-Za-z0-9]').hasMatch(value[0])) {
    return 'Instance name must start with a letter or digit.';
  }
  final bad = RegExp(r'[^A-Za-z0-9._-]').firstMatch(value);
  if (bad != null) {
    return 'Instance name cannot contain “${bad[0]}” — use letters, digits, dot, '
        'dash or underscore.';
  }
  return null;
}

String? validateHostname(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return 'Hostname is required.';
  if (value.length > 64) {
    return 'Hostname is ${value.length} characters — the maximum is 64.';
  }
  final space = RegExp(r'\s').firstMatch(value);
  if (space != null) return 'Hostname cannot contain spaces.';
  final bad = RegExp(r'[^A-Za-z0-9._-]').firstMatch(value);
  if (bad != null) {
    return 'Hostname cannot contain “${bad[0]}” — use letters, digits, dot, dash '
        'or underscore.';
  }
  return null;
}

String? validateNetworkName(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return 'Network name is required.';
  if (value.length > 128) {
    return 'Network name is ${value.length} characters — the maximum is 128.';
  }
  return null;
}

String? validateNetworkSecret(String raw) {
  if (raw.isEmpty) return null;
  if (raw.trim() != raw) return 'Network secret cannot start or end with a space.';
  if (RegExp(r'\s').hasMatch(raw)) return 'Network secret cannot contain spaces.';
  if (raw.length > 128) {
    return 'Network secret is ${raw.length} characters — the maximum is 128.';
  }
  return null;
}

String? validatePrefixLength(int value) {
  const allowed = [8, 16, 24, 32];
  if (allowed.contains(value)) return null;
  return 'Prefix length must be 8, 16, 24 or 32 — got $value.';
}

String? validateMtuText(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return null;
  final number = int.tryParse(value);
  if (number == null) return 'MTU “$value” is not an integer.';
  if (number < 576 || number > 9000) return 'MTU $number is outside 576–9000.';
  return null;
}

String? validateDeviceName(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return null;
  if (value.length > 15) {
    return 'Device name is ${value.length} characters — Linux interface names '
        'allow at most 15.';
  }
  final bad = RegExp(r'[^A-Za-z0-9_.-]').firstMatch(value);
  if (bad != null) {
    return 'Device name cannot contain “${bad[0]}” — use letters, digits, dot, '
        'dash or underscore.';
  }
  return null;
}

// ---------------------------------------------------------------------------
// IPv4 / CIDR / URL primitives. Every message names the offending segment.
// ---------------------------------------------------------------------------

String? _ipv4Problem(String raw) {
  final value = raw.trim();
  if (value.contains(':')) {
    return '“$value” is an IPv6 address — this field takes IPv4.';
  }
  final parts = value.split('.');
  if (parts.length != 4) {
    return '“$value” has ${parts.length} segment${parts.length == 1 ? '' : 's'} '
        '— IPv4 needs exactly 4.';
  }
  for (var i = 0; i < parts.length; i++) {
    final part = parts[i];
    if (part.isEmpty) return 'Segment ${i + 1} is empty — every segment needs a number.';
    final number = int.tryParse(part);
    if (number == null) return 'Segment ${i + 1} “$part” is not a number.';
    if (number < 0 || number > 255) {
      return 'Segment ${i + 1} “$part” is outside 0–255.';
    }
    if (part.length > 1 && part.startsWith('0')) {
      return 'Segment ${i + 1} “$part” has a leading zero.';
    }
  }
  return null;
}

String? validateVirtualIpv4(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return 'An address is required when DHCP is off.';
  return _ipv4Problem(value);
}

String? _cidrProblem(String raw, {required bool requirePrefix}) {
  final value = raw.trim();
  if (value.isEmpty) return 'the value is empty.';
  final slash = value.indexOf('/');
  final address = slash < 0 ? value : value.substring(0, slash);
  final prefix = slash < 0 ? null : value.substring(slash + 1);

  final addressProblem = _ipv4Problem(address);
  if (addressProblem != null) return addressProblem;

  if (prefix == null) {
    if (!requirePrefix) return null;
    return 'missing prefix length — expected a CIDR such as 192.168.1.0/24.';
  }
  if (prefix.isEmpty) return 'the prefix is missing after “/”.';
  final number = int.tryParse(prefix);
  if (number == null) return 'Prefix “$prefix” is not a number.';
  if (number < 0 || number > 32) return 'Prefix “$prefix” is outside 0–32.';
  return null;
}

String? validateCidrLines(
  List<String> values, {
  required String label,
  required bool requirePrefix,
}) {
  for (var i = 0; i < values.length; i++) {
    final problem = _cidrProblem(values[i], requirePrefix: requirePrefix);
    if (problem != null) return 'Line ${i + 1} ($label): $problem';
  }
  return null;
}

String? _urlProblem(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return 'the line is empty.';

  final schemeMatch = RegExp(r'^([A-Za-z][A-Za-z0-9+.-]*)://').firstMatch(value);
  if (schemeMatch == null) {
    return 'expected scheme://host:port, for example tcp://public.easytier.top:11010.';
  }
  final scheme = schemeMatch[1]!.toLowerCase();
  if (!kUrlSchemes.contains(scheme)) {
    return 'scheme “$scheme” is not supported — use ${kUrlSchemes.join(', ')}.';
  }

  final rest = value.substring(schemeMatch.end).split('/').first;
  final colon = rest.lastIndexOf(':');
  if (colon <= 0) return 'missing host and port — expected host:port after the scheme.';

  final host = rest.substring(0, colon);
  final portText = rest.substring(colon + 1);
  if (host.isEmpty) return 'missing host.';
  if (host.contains(':')) {
    return 'IPv6 hosts are not supported here — use an IPv4 address or DNS name.';
  }
  final badHost = RegExp(r'[^A-Za-z0-9.-]').firstMatch(host);
  if (badHost != null) {
    return 'host “$host” contains “${badHost[0]}” — use letters, digits, dot or dash.';
  }

  final port = int.tryParse(portText);
  if (port == null) return 'port “$portText” is not a number.';
  if (port < 1 || port > 65535) return 'port “$portText” is outside 1–65535.';
  return null;
}

String? validateUrlLines(List<String> urls) {
  for (var i = 0; i < urls.length; i++) {
    final problem = _urlProblem(urls[i]);
    if (problem != null) return 'Line ${i + 1}: $problem';
  }
  return null;
}

/// A `host:port` pair, as used by port forwarding.
String? validateHostPort(String raw, {required String label}) {
  final value = raw.trim();
  if (value.isEmpty) return '$label address is required.';
  final colon = value.lastIndexOf(':');
  if (colon <= 0) return '$label address “$value” needs host:port, for example 127.0.0.1:8080.';

  final host = value.substring(0, colon);
  final portText = value.substring(colon + 1);
  final hostProblem = _ipv4Problem(host);
  if (hostProblem != null) return '$label host: $hostProblem';
  final port = int.tryParse(portText);
  if (port == null) return '$label port “$portText” is not a number.';
  if (port < 1 || port > 65535) return '$label port “$portText” is outside 1–65535.';
  return null;
}

/// Port list syntax: `80`, `80,443`, `8000-8100`. Empty means any port.
String? validatePortSpec(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return null;
  final entries = value.split(',');
  for (var i = 0; i < entries.length; i++) {
    final entry = entries[i].trim();
    if (entry.isEmpty) {
      return 'Entry ${i + 1} is empty — remove the extra comma.';
    }
    final bounds = entry.split('-');
    if (bounds.length > 2) return 'Entry “$entry” has more than one dash.';
    final numbers = <int>[];
    for (final bound in bounds) {
      final text = bound.trim();
      final number = int.tryParse(text);
      if (number == null) return 'Port “$text” is not a number.';
      if (number < 1 || number > 65535) return 'Port $number is outside 1–65535.';
      numbers.add(number);
    }
    if (numbers.length == 2 && numbers[0] > numbers[1]) {
      return 'Port range “$entry” starts after it ends.';
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// Port forwards and ACL rules.
// ---------------------------------------------------------------------------

Map<String, String> validatePortForwardFields(
  PortForward rule, {
  required List<PortForward> existing,
  int? skipIndex,
}) {
  final errors = <String, String>{};
  if (rule.proto != 'tcp' && rule.proto != 'udp') {
    errors['proto'] = 'Protocol must be tcp or udp.';
  }
  final local = validateHostPort(rule.local, label: 'Local');
  if (local != null) errors['local'] = local;
  final remote = validateHostPort(rule.remote, label: 'Remote');
  if (remote != null) errors['remote'] = remote;

  if (errors.isEmpty) {
    for (var i = 0; i < existing.length; i++) {
      if (i == skipIndex) continue;
      final other = existing[i];
      if (other.proto == rule.proto && other.local == rule.local) {
        errors['local'] = 'Local ${rule.local} is already forwarded over '
            '${rule.proto.toUpperCase()}.';
        break;
      }
    }
  }
  return errors;
}

Map<String, String> validateAclRuleFields(AclRule rule) {
  final errors = <String, String>{};
  if (rule.action != 'allow' && rule.action != 'deny') {
    errors['action'] = 'Action must be allow or deny.';
  }
  if (rule.chain != 'inbound' && rule.chain != 'outbound') {
    errors['chain'] = 'Chain must be inbound or outbound.';
  }
  const protocols = ['tcp', 'udp', 'icmp', 'any'];
  if (!protocols.contains(rule.protocol)) {
    errors['protocol'] = 'Protocol must be tcp, udp, icmp or any.';
  }

  final sourceProblem = _cidrProblem(rule.source, requirePrefix: false);
  if (sourceProblem != null) errors['source'] = 'Source: $sourceProblem';
  final destinationProblem = _cidrProblem(rule.destination, requirePrefix: false);
  if (destinationProblem != null) {
    errors['destination'] = 'Destination: $destinationProblem';
  }

  final portProblem = validatePortSpec(rule.ports);
  if (portProblem != null) {
    errors['ports'] = portProblem;
  } else if (rule.ports.trim().isNotEmpty && rule.protocol == 'icmp') {
    errors['ports'] = 'ICMP rules do not use ports — leave the port list empty.';
  }
  return errors;
}

// ---------------------------------------------------------------------------
// Whole-form validation.
// ---------------------------------------------------------------------------

/// Validates the draft as a whole. [mtuText] is passed separately because an
/// unparsable MTU has no `int?` to inspect in [NetworkConfig] — it must still
/// surface as an error instead of silently falling back to the default.
Map<String, String> validateNetworkConfigFields(
  NetworkConfig config, {
  String? mtuText,
}) {
  final errors = <String, String>{};
  void check(String field, String? message) {
    if (message != null) errors[field] = message;
  }

  check(ConfigField.instanceName, validateInstanceName(config.instanceName));
  check(ConfigField.hostname, validateHostname(config.hostname));
  check(ConfigField.networkName, validateNetworkName(config.networkName));
  check(ConfigField.networkSecret, validateNetworkSecret(config.networkSecret));

  if (!config.dhcp) {
    check(ConfigField.virtualIpv4, validateVirtualIpv4(config.virtualIpv4));
    check(ConfigField.networkLength, validatePrefixLength(config.networkLength));
  }

  check(ConfigField.peerUrls, validateUrlLines(config.peerUrls));
  check(ConfigField.listenerUrls, validateUrlLines(config.listenerUrls));
  check(
    ConfigField.mtu,
    validateMtuText(mtuText ?? (config.mtu?.toString() ?? '')),
  );
  check(ConfigField.devName, validateDeviceName(config.devName));
  check(
    ConfigField.proxyCidrs,
    validateCidrLines(
      config.proxyCidrs,
      label: 'proxy network',
      requirePrefix: true,
    ),
  );

  if (!errors.containsKey(ConfigField.portForwards)) {
    for (var i = 0; i < config.portForwards.length; i++) {
      final fields = validatePortForwardFields(
        config.portForwards[i],
        existing: config.portForwards,
        skipIndex: i,
      );
      if (fields.isNotEmpty) {
        errors[ConfigField.portForwards] =
            'Rule ${i + 1}: ${fields.values.first}';
        break;
      }
    }
  }

  if (!errors.containsKey(ConfigField.aclRules)) {
    for (var i = 0; i < config.aclRules.length; i++) {
      final fields = validateAclRuleFields(config.aclRules[i]);
      if (fields.isNotEmpty) {
        errors[ConfigField.aclRules] = 'Rule ${i + 1}: ${fields.values.first}';
        break;
      }
    }
  }

  return errors;
}

/// Maps a core-level validation message back onto a field when the message is
/// recognisable ("Network name is required." → network name field).
String? fieldForCoreError(String message) {
  final lower = message.toLowerCase();
  if (lower.contains('network name')) return ConfigField.networkName;
  if (lower.contains('instance name')) return ConfigField.instanceName;
  if (lower.contains('virtual ipv4') || lower.contains('static mode')) {
    return ConfigField.virtualIpv4;
  }
  if (lower.contains('prefix length')) return ConfigField.networkLength;
  if (lower.contains('network secret')) return ConfigField.networkSecret;
  return null;
}

// ---------------------------------------------------------------------------
// Structural equality, used to derive the dirty state from the draft.
// ---------------------------------------------------------------------------

bool configEquals(NetworkConfig a, NetworkConfig b) =>
    a.instanceName == b.instanceName &&
    a.hostname == b.hostname &&
    a.networkName == b.networkName &&
    a.networkSecret == b.networkSecret &&
    a.dhcp == b.dhcp &&
    a.virtualIpv4 == b.virtualIpv4 &&
    a.networkLength == b.networkLength &&
    _listEquals(a.peerUrls, b.peerUrls) &&
    _listEquals(a.listenerUrls, b.listenerUrls) &&
    a.disableEncryption == b.disableEncryption &&
    a.disableIpv6 == b.disableIpv6 &&
    a.mtu == b.mtu &&
    a.latencyFirst == b.latencyFirst &&
    a.multiThread == b.multiThread &&
    a.devName == b.devName &&
    a.useSmoltcp == b.useSmoltcp &&
    a.bindDevice == b.bindDevice &&
    a.noTun == b.noTun &&
    a.enablePrivateMode == b.enablePrivateMode &&
    a.enableMagicDns == b.enableMagicDns &&
    a.disableP2p == b.disableP2p &&
    a.p2pOnly == b.p2pOnly &&
    a.relayAllPeerRpc == b.relayAllPeerRpc &&
    a.enableExitNode == b.enableExitNode &&
    _listEquals(a.proxyCidrs, b.proxyCidrs) &&
    _portForwardsEqual(a.portForwards, b.portForwards) &&
    _aclRulesEqual(a.aclRules, b.aclRules);

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _portForwardsEqual(List<PortForward> a, List<PortForward> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].proto != b[i].proto ||
        a[i].local != b[i].local ||
        a[i].remote != b[i].remote) {
      return false;
    }
  }
  return true;
}

bool _aclRulesEqual(List<AclRule> a, List<AclRule> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].action != b[i].action ||
        a[i].protocol != b[i].protocol ||
        a[i].chain != b[i].chain ||
        a[i].source != b[i].source ||
        a[i].destination != b[i].destination ||
        a[i].ports != b[i].ports ||
        a[i].comment != b[i].comment) {
      return false;
    }
  }
  return true;
}
