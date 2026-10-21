import 'dart:convert';

import '../../core/models/models.dart';

/// A problem found while parsing the TOML source editor. [line] is 1-based.
class TomlIssue {
  const TomlIssue(this.line, this.message);

  final int line;
  final String message;
}

class TomlParseResult {
  const TomlParseResult({
    this.config,
    this.errors = const [],
    this.warnings = const [],
  });

  /// Non-null only when [errors] is empty.
  final NetworkConfig? config;

  /// Fatal problems: the source cannot be applied.
  final List<TomlIssue> errors;

  /// Non-fatal problems: unknown keys/sections were ignored or normalised.
  final List<TomlIssue> warnings;

  bool get ok => errors.isEmpty && config != null;
}

/// Serialises the editable subset of [NetworkConfig] as EasyTier-style TOML.
///
/// The Rust bridge owns the authoritative serialisation; this text exists so the
/// client can offer a real source-file workflow (edit → parse → apply to the
/// form draft). Every key emitted here round-trips through
/// [parseNetworkConfigToml].
String networkConfigToToml(NetworkConfig config) {
  final b = StringBuffer()
    ..writeln('# EasyTier network configuration')
    ..writeln('# Edited in the client source editor; applied to the draft, then saved.')
    ..writeln()
    ..writeln('instance_name = ${_str(config.instanceName)}')
    ..writeln('hostname = ${_str(config.hostname)}')
    ..writeln('network_name = ${_str(config.networkName)}')
    ..writeln('network_secret = ${_str(config.networkSecret)}')
    ..writeln('dhcp = ${config.dhcp}');
  if (config.virtualIpv4.isNotEmpty) {
    b.writeln('ipv4 = ${_str('${config.virtualIpv4}/${config.networkLength}')}');
  }
  b
    ..writeln('listeners = ${_arr(config.listenerUrls)}')
    ..writeln('peers = ${_arr(config.peerUrls)}')
    ..writeln()
    ..writeln('disable_encryption = ${config.disableEncryption}')
    ..writeln('disable_ipv6 = ${config.disableIpv6}')
    ..writeln('latency_first = ${config.latencyFirst}')
    ..writeln('multi_thread = ${config.multiThread}')
    ..writeln('use_smoltcp = ${config.useSmoltcp}')
    ..writeln('bind_device = ${config.bindDevice}')
    ..writeln('no_tun = ${config.noTun}')
    ..writeln('enable_private_mode = ${config.enablePrivateMode}')
    ..writeln('enable_magic_dns = ${config.enableMagicDns}')
    ..writeln('disable_p2p = ${config.disableP2p}')
    ..writeln('p2p_only = ${config.p2pOnly}')
    ..writeln('relay_all_peer_rpc = ${config.relayAllPeerRpc}')
    ..writeln('enable_exit_node = ${config.enableExitNode}');
  if (config.mtu != null) b.writeln('mtu = ${config.mtu}');
  if (config.devName.isNotEmpty) {
    b.writeln('dev_name = ${_str(config.devName)}');
  }
  if (config.proxyCidrs.isNotEmpty) {
    b.writeln('proxy_networks = ${_arr(config.proxyCidrs)}');
  }
  for (final forward in config.portForwards) {
    b
      ..writeln()
      ..writeln('[[port_forward]]')
      ..writeln('proto = ${_str(forward.proto)}')
      ..writeln('local = ${_str(forward.local)}')
      ..writeln('remote = ${_str(forward.remote)}');
  }
  for (final rule in config.aclRules) {
    b
      ..writeln()
      ..writeln('[[acl_rule]]')
      ..writeln('action = ${_str(rule.action)}')
      ..writeln('protocol = ${_str(rule.protocol)}')
      ..writeln('chain = ${_str(rule.chain)}')
      ..writeln('source = ${_str(rule.source)}')
      ..writeln('destination = ${_str(rule.destination)}');
    if (rule.ports.isNotEmpty) b.writeln('ports = ${_str(rule.ports)}');
    if (rule.comment.isNotEmpty) b.writeln('comment = ${_str(rule.comment)}');
  }
  return b.toString();
}

String _str(String value) => jsonEncode(value);

String _arr(List<String> values) => '[${values.map(_str).join(', ')}]';

/// Parses the TOML produced by [networkConfigToToml] (and hand-written files
/// using the same keys). Missing keys keep [base]'s values; unknown keys are
/// reported as warnings and ignored.
TomlParseResult parseNetworkConfigToml(
  String source, {
  required NetworkConfig base,
}) {
  final errors = <TomlIssue>[];
  final warnings = <TomlIssue>[];

  // Working copy of every field, seeded from the current draft.
  var instanceName = base.instanceName;
  var hostname = base.hostname;
  var networkName = base.networkName;
  var networkSecret = base.networkSecret;
  var dhcp = base.dhcp;
  var virtualIpv4 = base.virtualIpv4;
  var networkLength = base.networkLength;
  var listeners = base.listenerUrls;
  var peers = base.peerUrls;
  var disableEncryption = base.disableEncryption;
  var disableIpv6 = base.disableIpv6;
  var latencyFirst = base.latencyFirst;
  var multiThread = base.multiThread;
  var useSmoltcp = base.useSmoltcp;
  var bindDevice = base.bindDevice;
  var noTun = base.noTun;
  var enablePrivateMode = base.enablePrivateMode;
  var enableMagicDns = base.enableMagicDns;
  var disableP2p = base.disableP2p;
  var p2pOnly = base.p2pOnly;
  var relayAllPeerRpc = base.relayAllPeerRpc;
  var enableExitNode = base.enableExitNode;
  var mtu = base.mtu;
  var devName = base.devName;
  var proxyCidrs = base.proxyCidrs;
  final portForwards = <PortForward>[...base.portForwards];
  final aclRules = <AclRule>[...base.aclRules];

  // Section state: null when reading top-level keys.
  String? section;
  Map<String, Object> sectionValues = {};
  // Sections replace the base draft's lists (round-trip), rather than append.
  var sawPortForward = false;
  var sawAclRule = false;

  void flushSection(int line) {
    if (section == null) return;
    if (section == 'port_forward') {
      final proto = sectionValues['proto'];
      final local = sectionValues['local'];
      final remote = sectionValues['remote'];
      if (proto is! String || local is! String || remote is! String) {
        errors.add(TomlIssue(
          line,
          'Each [[port_forward]] needs proto, local and remote strings.',
        ));
      } else {
        portForwards.add(PortForward(proto: proto, local: local, remote: remote));
      }
    } else if (section == 'acl_rule') {
      final action = sectionValues['action'];
      final protocol = sectionValues['protocol'];
      final chain = sectionValues['chain'];
      if (action is! String || protocol is! String || chain is! String) {
        errors.add(TomlIssue(
          line,
          'Each [[acl_rule]] needs action, protocol and chain strings.',
        ));
      } else {
        aclRules.add(AclRule(
          action: action,
          protocol: protocol,
          chain: chain,
          source: sectionValues['source'] as String? ?? '0.0.0.0/0',
          destination: sectionValues['destination'] as String? ?? '0.0.0.0/0',
          ports: sectionValues['ports'] as String? ?? '',
          comment: sectionValues['comment'] as String? ?? '',
        ));
      }
    }
    section = null;
    sectionValues = {};
  }

  final lines = source.split('\n');
  for (var index = 0; index < lines.length; index++) {
    final lineNo = index + 1;
    final raw = _stripComment(lines[index]).trim();
    if (raw.isEmpty) continue;

    if (raw.startsWith('[[') && raw.endsWith(']]')) {
      flushSection(lineNo);
      final name = raw.substring(2, raw.length - 2).trim();
      if (name == 'port_forward' && !sawPortForward) {
        sawPortForward = true;
        portForwards.clear();
      } else if (name == 'acl_rule' && !sawAclRule) {
        sawAclRule = true;
        aclRules.clear();
      }
      if (name != 'port_forward' && name != 'acl_rule') {
        errors.add(TomlIssue(lineNo, 'Unsupported table [[$name]].'));
        // Keep consuming its keys as unknown so one bad table does not cascade.
        section = 'unknown';
        sectionValues = {};
      } else {
        section = name;
        sectionValues = {};
      }
      continue;
    }
    if (raw.startsWith('[')) {
      errors.add(TomlIssue(lineNo, 'Table headers are not supported; use [[port_forward]] or [[acl_rule]].'));
      continue;
    }

    final eq = _indexOfTopLevel(raw, '=');
    if (eq < 0) {
      errors.add(TomlIssue(lineNo, 'Expected key = value.'));
      continue;
    }
    final key = raw.substring(0, eq).trim();
    var valueText = raw.substring(eq + 1).trim();
    if (key.isEmpty) {
      errors.add(TomlIssue(lineNo, 'Missing key before "=".'));
      continue;
    }

    // Multi-line arrays: keep reading until brackets balance outside strings.
    if (valueText.startsWith('[') && !_bracketsBalanced(valueText)) {
      final buffer = StringBuffer(valueText);
      var closed = false;
      while (index + 1 < lines.length) {
        index++;
        final next = _stripComment(lines[index]).trim();
        buffer.write(' $next');
        if (_bracketsBalanced(buffer.toString())) {
          closed = true;
          break;
        }
      }
      if (!closed) {
        errors.add(TomlIssue(lineNo, 'Unterminated array for "$key".'));
        continue;
      }
      valueText = buffer.toString();
    }

    Object? value;
    try {
      value = _parseValue(valueText);
    } on FormatException catch (error) {
      errors.add(TomlIssue(lineNo, '$key: ${error.message}'));
      continue;
    }

    if (section == 'unknown') continue;
    if (section != null) {
      sectionValues[key] = value!;
      continue;
    }

    void assignString(String target, void Function(String) set) {
      if (value is String) {
        set(value);
      } else {
        errors.add(TomlIssue(lineNo, '$target must be a quoted string.'));
      }
    }

    void assignBool(String target, void Function(bool) set) {
      if (value is bool) {
        set(value);
      } else {
        errors.add(TomlIssue(lineNo, '$target must be true or false.'));
      }
    }

    switch (key) {
      case 'instance_name':
        assignString(key, (v) => instanceName = v);
      case 'hostname':
        assignString(key, (v) => hostname = v);
      case 'network_name':
        assignString(key, (v) => networkName = v);
      case 'network_secret':
        assignString(key, (v) => networkSecret = v);
      case 'dhcp':
        assignBool(key, (v) => dhcp = v);
      case 'ipv4':
        if (value is String) {
          final slash = value.lastIndexOf('/');
          if (slash <= 0) {
            errors.add(TomlIssue(lineNo, 'ipv4 must look like "10.144.0.2/24".'));
          } else {
            virtualIpv4 = value.substring(0, slash);
            final parsed = int.tryParse(value.substring(slash + 1));
            if (parsed == null) {
              errors.add(TomlIssue(lineNo, 'ipv4 prefix must be a number.'));
            } else {
              networkLength = parsed;
            }
          }
        } else {
          errors.add(TomlIssue(lineNo, 'ipv4 must be a quoted string.'));
        }
      case 'listeners':
        if (value is List<String>) {
          listeners = value;
        } else {
          errors.add(TomlIssue(lineNo, 'listeners must be an array of strings.'));
        }
      case 'peers':
        if (value is List<String>) {
          peers = value;
        } else {
          errors.add(TomlIssue(lineNo, 'peers must be an array of strings.'));
        }
      case 'disable_encryption':
        assignBool(key, (v) => disableEncryption = v);
      case 'disable_ipv6':
        assignBool(key, (v) => disableIpv6 = v);
      case 'latency_first':
        assignBool(key, (v) => latencyFirst = v);
      case 'multi_thread':
        assignBool(key, (v) => multiThread = v);
      case 'use_smoltcp':
        assignBool(key, (v) => useSmoltcp = v);
      case 'bind_device':
        assignBool(key, (v) => bindDevice = v);
      case 'no_tun':
        assignBool(key, (v) => noTun = v);
      case 'enable_private_mode':
        assignBool(key, (v) => enablePrivateMode = v);
      case 'enable_magic_dns':
        assignBool(key, (v) => enableMagicDns = v);
      case 'disable_p2p':
        assignBool(key, (v) => disableP2p = v);
      case 'p2p_only':
        assignBool(key, (v) => p2pOnly = v);
      case 'relay_all_peer_rpc':
        assignBool(key, (v) => relayAllPeerRpc = v);
      case 'enable_exit_node':
        assignBool(key, (v) => enableExitNode = v);
      case 'mtu':
        if (value is int && value > 0) {
          mtu = value;
        } else if (value is int && value <= 0) {
          mtu = null;
        } else {
          errors.add(TomlIssue(lineNo, 'mtu must be an integer.'));
        }
      case 'dev_name':
        assignString(key, (v) => devName = v);
      case 'proxy_networks':
        if (value is List<String>) {
          proxyCidrs = value;
        } else {
          errors.add(TomlIssue(lineNo, 'proxy_networks must be an array of strings.'));
        }
      default:
        warnings.add(TomlIssue(lineNo, 'Unknown key "$key" was ignored.'));
    }
  }
  flushSection(lines.length);

  if (errors.isNotEmpty) {
    return TomlParseResult(errors: errors, warnings: warnings);
  }
  return TomlParseResult(
    config: NetworkConfig(
      instanceName: instanceName,
      hostname: hostname,
      networkName: networkName,
      networkSecret: networkSecret,
      dhcp: dhcp,
      virtualIpv4: virtualIpv4,
      networkLength: networkLength,
      peerUrls: peers,
      listenerUrls: listeners,
      disableEncryption: disableEncryption,
      disableIpv6: disableIpv6,
      mtu: mtu,
      latencyFirst: latencyFirst,
      multiThread: multiThread,
      devName: devName,
      useSmoltcp: useSmoltcp,
      bindDevice: bindDevice,
      noTun: noTun,
      enablePrivateMode: enablePrivateMode,
      enableMagicDns: enableMagicDns,
      disableP2p: disableP2p,
      p2pOnly: p2pOnly,
      relayAllPeerRpc: relayAllPeerRpc,
      enableExitNode: enableExitNode,
      proxyCidrs: proxyCidrs,
      portForwards: portForwards,
      aclRules: aclRules,
    ),
    warnings: warnings,
  );
}

/// Removes a `#` comment that is not inside a quoted string.
String _stripComment(String line) {
  var inString = false;
  var quote = '';
  var escaped = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (ch == r'\') {
        escaped = true;
      } else if (ch == quote) {
        inString = false;
      }
    } else if (ch == '"' || ch == "'") {
      inString = true;
      quote = ch;
    } else if (ch == '#') {
      return line.substring(0, i);
    }
  }
  return line;
}

int _indexOfTopLevel(String text, String needle) {
  var inString = false;
  var quote = '';
  var escaped = false;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (ch == r'\') {
        escaped = true;
      } else if (ch == quote) {
        inString = false;
      }
    } else if (ch == '"' || ch == "'") {
      inString = true;
      quote = ch;
    } else if (text.startsWith(needle, i)) {
      return i;
    }
  }
  return -1;
}

bool _bracketsBalanced(String text) {
  var depth = 0;
  var inString = false;
  var quote = '';
  var escaped = false;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (ch == r'\') {
        escaped = true;
      } else if (ch == quote) {
        inString = false;
      }
    } else if (ch == '"' || ch == "'") {
      inString = true;
      quote = ch;
    } else if (ch == '[') {
      depth++;
    } else if (ch == ']') {
      depth--;
    }
  }
  return depth == 0 && !inString;
}

Object? _parseValue(String text) {
  final value = text.trim();
  if (value.isEmpty) throw const FormatException('Missing value.');
  if (value == 'true') return true;
  if (value == 'false') return false;
  final intValue = int.tryParse(value);
  if (intValue != null) return intValue;
  if (value.startsWith('"') || value.startsWith("'")) {
    return _parseString(value);
  }
  if (value.startsWith('[')) {
    return _parseStringArray(value);
  }
  throw FormatException('Unsupported value "$value".');
}

String _parseString(String text) {
  final quote = text[0];
  final b = StringBuffer();
  var i = 1;
  var escaped = false;
  for (; i < text.length; i++) {
    final ch = text[i];
    if (quote == '"' && escaped) {
      switch (ch) {
        case 'n':
          b.write('\n');
        case 't':
          b.write('\t');
        case 'r':
          b.write('\r');
        case '"':
          b.write('"');
        case r'\':
          b.write(r'\');
        default:
          b.write(ch);
      }
      escaped = false;
      continue;
    }
    if (quote == '"' && ch == r'\') {
      escaped = true;
      continue;
    }
    if (ch == quote) {
      final rest = text.substring(i + 1).trim();
      if (rest.isNotEmpty) {
        throw const FormatException('Unexpected characters after string.');
      }
      return b.toString();
    }
    b.write(ch);
  }
  throw const FormatException('Unterminated string.');
}

List<String> _parseStringArray(String text) {
  final values = <String>[];
  var i = 1;
  void skipSpace() {
    while (i < text.length && (text[i] == ' ' || text[i] == '\t' || text[i] == '\n')) {
      i++;
    }
  }

  skipSpace();
  if (i < text.length && text[i] == ']') {
    final rest = text.substring(i + 1).trim();
    if (rest.isNotEmpty) throw const FormatException('Unexpected characters after array.');
    return values;
  }
  while (i < text.length) {
    skipSpace();
    if (i >= text.length) break;
    if (text[i] == ',') {
      i++;
      continue;
    }
    if (text[i] == ']') {
      final rest = text.substring(i + 1).trim();
      if (rest.isNotEmpty) throw const FormatException('Unexpected characters after array.');
      return values;
    }
    if (text[i] != '"' && text[i] != "'") {
      throw const FormatException('Arrays must contain quoted strings.');
    }
    final quote = text[i];
    final start = i;
    i++;
    var escaped = false;
    while (i < text.length) {
      final ch = text[i];
      if (quote == '"' && escaped) {
        escaped = false;
      } else if (quote == '"' && ch == r'\') {
        escaped = true;
      } else if (ch == quote) {
        break;
      }
      i++;
    }
    if (i >= text.length) throw const FormatException('Unterminated string in array.');
    values.add(_parseString(text.substring(start, i + 1)));
    i++;
  }
  throw const FormatException('Unterminated array.');
}
