import '../../core/models/models.dart';

/// Canonical EasyTier TOML — the exact schema read by the Rust
/// `TomlConfigLoader` and written by `FfiCoreClient`.
///
/// This is deliberately separate from `NetworkConfig.debugToml()` (a
/// human-readable readback). The config source editor must use *this* format so
/// its text can be pasted into a real EasyTier config and parsed by the core.
class TomlIssue {
  const TomlIssue(this.line, this.message);

  final int line;
  final String message;
}

class TomlParseResult {
  const TomlParseResult({
    this.config,
    this.instanceId,
    this.errors = const [],
    this.warnings = const [],
    this.unsupported = const [],
  });

  final NetworkConfig? config;

  /// `instance_id` from the source (managed by the client, not the UI model).
  final String? instanceId;

  final List<TomlIssue> errors;
  final List<TomlIssue> warnings;

  /// Keys/tables the client model cannot represent. Applying such a source
  /// would silently drop them, so the editor blocks Apply while non-empty.
  final List<TomlIssue> unsupported;

  bool get ok => errors.isEmpty && config != null;
  bool get hasUnsupportedFields => unsupported.isNotEmpty;
}

const Map<String, int> _chainTypes = {'inbound': 1, 'outbound': 2, 'forward': 3};
const Map<String, int> _actions = {'allow': 1, 'deny': 2, 'drop': 2};
const Map<String, int> _protocols = {
  'tcp': 1,
  'udp': 2,
  'icmp': 3,
  'icmpv6': 4,
  'any': 5,
};

/// Serialises the modelled subset in the canonical schema the core accepts.
String encodeConfigToml(NetworkConfig config, {required String instanceId}) {
  final b = StringBuffer();
  void line(String value) => b.writeln(value);
  void blank() => b.writeln();

  line('instance_name = ${_str(config.instanceName)}');
  line('instance_id = ${_str(instanceId)}');
  line('hostname = ${_str(config.hostname)}');
  line('dhcp = ${config.dhcp}');
  if (!config.dhcp && config.virtualIpv4.trim().isNotEmpty) {
    line('ipv4 = ${_str('${config.virtualIpv4.trim()}/${config.networkLength}')}');
  }
  line('listeners = [${config.listenerUrls.map(_str).join(', ')}]');

  for (final peer in config.peerUrls) {
    if (peer.trim().isEmpty) continue;
    blank();
    line('[[peer]]');
    line('uri = ${_str(peer.trim())}');
  }
  for (final cidr in config.proxyCidrs) {
    if (cidr.trim().isEmpty) continue;
    blank();
    line('[[proxy_network]]');
    line('cidr = ${_str(cidr.trim())}');
  }
  for (final forward in config.portForwards) {
    blank();
    line('[[port_forward]]');
    line('bind_addr = ${_str(forward.local)}');
    line('dst_addr = ${_str(forward.remote)}');
    line('proto = ${_str(forward.proto.toLowerCase())}');
  }

  blank();
  line('[network_identity]');
  line('network_name = ${_str(config.networkName)}');
  line('network_secret = ${_str(config.networkSecret)}');

  blank();
  line('[flags]');
  line('enable_encryption = ${!config.disableEncryption}');
  line('enable_ipv6 = ${!config.disableIpv6}');
  line('latency_first = ${config.latencyFirst}');
  line('multi_thread = ${config.multiThread}');
  line('use_smoltcp = ${config.useSmoltcp}');
  line('bind_device = ${config.bindDevice}');
  line('no_tun = ${config.noTun}');
  line('private_mode = ${config.enablePrivateMode}');
  line('accept_dns = ${config.enableMagicDns}');
  line('disable_p2p = ${config.disableP2p}');
  line('p2p_only = ${config.p2pOnly}');
  line('relay_all_peer_rpc = ${config.relayAllPeerRpc}');
  line('enable_exit_node = ${config.enableExitNode}');
  if (config.mtu != null && config.mtu! > 0) line('mtu = ${config.mtu}');
  if (config.devName.trim().isNotEmpty) {
    line('dev_name = ${_str(config.devName.trim())}');
  }

  final rulesByChain = <String, List<AclRule>>{};
  for (final rule in config.aclRules) {
    rulesByChain
        .putIfAbsent(rule.chain.trim().toLowerCase(), () => <AclRule>[])
        .add(rule);
  }
  for (final entry in rulesByChain.entries) {
    blank();
    line('[[acl.acl_v1.chains]]');
    line('name = ${_str('${entry.key}-rules')}');
    line('chain_type = ${_chainTypes[entry.key] ?? 1}');
    line('enabled = true');
    line('default_action = 1');
    for (var i = 0; i < entry.value.length; i++) {
      final rule = entry.value[i];
      final comment = rule.comment.trim();
      line('[[acl.acl_v1.chains.rules]]');
      line('name = ${_str(comment.isEmpty ? '${entry.key}-rule-${i + 1}' : comment)}');
      if (comment.isNotEmpty) line('description = ${_str(comment)}');
      line('priority = ${(entry.value.length - i).clamp(0, 65535)}');
      line('enabled = true');
      line('action = ${_actions[rule.action.trim().toLowerCase()] ?? 1}');
      line('protocol = ${_protocols[rule.protocol.trim().toLowerCase()] ?? 5}');
      line(
        'source_ips = [${_str(rule.source.trim().isEmpty ? '0.0.0.0/0' : rule.source.trim())}]',
      );
      line(
        'destination_ips = [${_str(rule.destination.trim().isEmpty ? '0.0.0.0/0' : rule.destination.trim())}]',
      );
      final ports = rule.ports
          .split(',')
          .map((port) => port.trim())
          .where((port) => port.isNotEmpty)
          .toList();
      if (ports.isNotEmpty) line('ports = [${ports.map(_str).join(', ')}]');
    }
  }
  return b.toString();
}

/// Parses the canonical TOML above. Missing fields keep [base]'s values;
/// unknown **keys** are warnings, unknown **tables** or unmodelled fields are
/// collected in [TomlParseResult.unsupported] so the UI can block Apply.
TomlParseResult parseConfigToml(String source, {required NetworkConfig base}) {
  final errors = <TomlIssue>[];
  final warnings = <TomlIssue>[];
  final unsupported = <TomlIssue>[];

  var instanceName = base.instanceName;
  var hostname = base.hostname;
  var networkName = base.networkName;
  var networkSecret = base.networkSecret;
  var dhcp = base.dhcp;
  var virtualIpv4 = base.virtualIpv4;
  var networkLength = base.networkLength;
  var listeners = base.listenerUrls;
  var peers = <String>[];
  var proxyCidrs = <String>[];
  final portForwards = <PortForward>[];
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
  String? instanceId;
  var sawPeers = false;
  var sawProxy = false;
  var sawPortForward = false;

  final aclRules = <AclRule>[];
  String? chain;
  Map<String, Object> chainValues = {};
  Map<String, Object> ruleValues = {};
  int? ruleLine;

  void flushRule() {
    if (ruleValues.isEmpty) return;
    final action = ruleValues['action'];
    final protocol = ruleValues['protocol'];
    if (action is! int || protocol is! int) {
      errors.add(TomlIssue(ruleLine ?? 0, 'ACL rule needs integer action and protocol.'));
      ruleValues = {};
      return;
    }
    final src = _firstString(ruleValues['source_ips']) ?? '0.0.0.0/0';
    final dst = _firstString(ruleValues['destination_ips']) ?? '0.0.0.0/0';
    final ports = _stringList(ruleValues['ports']).join(',');
    aclRules.add(AclRule(
      action: _reverse(_actions, action) ?? 'allow',
      protocol: _reverse(_protocols, protocol) ?? 'any',
      chain: chain ?? 'inbound',
      source: src,
      destination: dst,
      ports: ports,
      comment: (ruleValues['description'] as String?) ??
          (ruleValues['comment'] as String?) ??
          '',
    ));
    ruleValues = {};
  }



  void flushPortForward(int lineNo) {
    final bind = chainValues['bind_addr'] ?? chainValues['local'];
    final dst = chainValues['dst_addr'] ?? chainValues['remote'];
    final proto = chainValues['proto'];
    if (bind is! String || dst is! String) {
      errors.add(TomlIssue(lineNo, 'Each [[port_forward]] needs bind_addr and dst_addr.'));
    } else {
      portForwards.add(PortForward(
        proto: (proto as String?)?.toLowerCase() ?? 'tcp',
        local: bind,
        remote: dst,
      ));
    }
    chainValues = {};
  }

  String? section;
  final lines = source.split('\n');
  for (var index = 0; index < lines.length; index++) {
    final lineNo = index + 1;
    final raw = _stripComment(lines[index]).trim();
    if (raw.isEmpty) continue;

    if (raw.startsWith('[[') && raw.endsWith(']]')) {
      final name = raw.substring(2, raw.length - 2).trim();
      if (section == 'port_forward') flushPortForward(lineNo);
      if (section == 'acl_rules') flushRule();
      switch (name) {
        case 'acl.acl_v1.chains':
          chain = null;
          chainValues = {};
          section = 'acl_chains';
        case 'acl.acl_v1.chains.rules':
          section = 'acl_rules';
        case 'peer':
          section = 'peer';
          if (!sawPeers) {
            sawPeers = true;
            peers = [];
          }
          chainValues = {};
        case 'proxy_network':
          section = 'proxy_network';
          if (!sawProxy) {
            sawProxy = true;
            proxyCidrs = [];
          }
          chainValues = {};
        case 'port_forward':
          section = 'port_forward';
          if (!sawPortForward) {
            sawPortForward = true;
            portForwards.clear();
          }
          chainValues = {};
        default:
          section = 'unknown';
          unsupported.add(TomlIssue(lineNo, 'Table [[$name]] is not editable yet.'));
      }
      continue;
    }
    if (raw.startsWith('[') && raw.endsWith(']')) {
      final name = raw.substring(1, raw.length - 1).trim();
      if (section == 'port_forward') flushPortForward(lineNo);
      if (section == 'acl_rules') flushRule();
      section = switch (name) {
        'network_identity' => 'identity',
        'flags' => 'flags',
        'acl' => 'acl_root',
        _ => 'unknown',
      };
      if (section == 'unknown') {
        unsupported.add(TomlIssue(lineNo, 'Table [$name] is not editable yet.'));
      }
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
    if (valueText.startsWith('[') && !_balanced(valueText)) {
      final buf = StringBuffer(valueText);
      var closed = false;
      while (index + 1 < lines.length) {
        index++;
        final next = _stripComment(lines[index]).trim();
        buf.write(' $next');
        if (_balanced(buf.toString())) {
          closed = true;
          break;
        }
      }
      if (!closed) {
        errors.add(TomlIssue(lineNo, 'Unterminated array for "$key".'));
        continue;
      }
      valueText = buf.toString();
    }

    Object? value;
    try {
      value = _parseValue(valueText);
    } on FormatException catch (error) {
      errors.add(TomlIssue(lineNo, '$key: ${error.message}'));
      continue;
    }

    switch (section) {
      case 'identity':
        if (key == 'network_name' && value is String) {
          networkName = value;
        } else if (key == 'network_secret' && value is String) {
          networkSecret = value;
        } else {
          warnings.add(TomlIssue(lineNo, 'Ignored [network_identity] key "$key".'));
        }
      case 'flags':
        switch (key) {
          case 'enable_encryption' when value is bool:
            disableEncryption = !value;
          case 'enable_ipv6' when value is bool:
            disableIpv6 = !value;
          case 'latency_first' when value is bool:
            latencyFirst = value;
          case 'multi_thread' when value is bool:
            multiThread = value;
          case 'use_smoltcp' when value is bool:
            useSmoltcp = value;
          case 'bind_device' when value is bool:
            bindDevice = value;
          case 'no_tun' when value is bool:
            noTun = value;
          case 'private_mode' when value is bool:
            enablePrivateMode = value;
          case 'accept_dns' when value is bool:
            enableMagicDns = value;
          case 'disable_p2p' when value is bool:
            disableP2p = value;
          case 'p2p_only' when value is bool:
            p2pOnly = value;
          case 'relay_all_peer_rpc' when value is bool:
            relayAllPeerRpc = value;
          case 'enable_exit_node' when value is bool:
            enableExitNode = value;
          case 'mtu' when value is int:
            mtu = value > 0 ? value : null;
          case 'dev_name' when value is String:
            devName = value;
          default:
            warnings.add(TomlIssue(lineNo, 'Ignored [flags] key "$key".'));
        }
      case 'peer':
        if (key == 'uri' && value is String) {
          peers.add(value);
        } else {
          warnings.add(TomlIssue(lineNo, 'Ignored [[peer]] key "$key".'));
        }
      case 'proxy_network':
        if (key == 'cidr' && value is String) {
          proxyCidrs.add(value);
        } else {
          warnings.add(TomlIssue(lineNo, 'Ignored [[proxy_network]] key "$key".'));
        }
      case 'port_forward':
        chainValues[key] = value!;
      case 'acl_chains':
        if (key == 'chain_type' && value is int) {
          chain = _reverse(_chainTypes, value);
        } else if (key == 'name' || key == 'enabled' || key == 'default_action') {
          // Metadata the UI derives; not modelled.
        } else {
          warnings.add(TomlIssue(lineNo, 'Ignored ACL chain key "$key".'));
        }
      case 'acl_rules':
        if (key == 'name' || key == 'priority' || key == 'enabled') {
          // Derived by the encoder.
        } else {
          ruleValues[key] = value!;
          ruleLine ??= lineNo;
        }
      case 'unknown':
        break;
      case 'acl_root':
        unsupported.add(TomlIssue(lineNo, 'ACL table "$key" is not editable yet.'));
      default:
        switch (key) {
          case 'instance_name':
            if (value is String) instanceName = value;
          case 'instance_id':
            if (value is String) instanceId = value;
          case 'hostname':
            if (value is String) hostname = value;
          case 'dhcp':
            if (value is bool) dhcp = value;
          case 'ipv4':
            if (value is String) {
              final slash = value.lastIndexOf('/');
              if (slash <= 0) {
                errors.add(TomlIssue(lineNo, 'ipv4 must look like "10.144.0.2/24".'));
              } else {
                virtualIpv4 = value.substring(0, slash);
                networkLength = int.tryParse(value.substring(slash + 1)) ?? networkLength;
              }
            } else {
              errors.add(TomlIssue(lineNo, 'ipv4 must be a string.'));
            }
          case 'listeners':
            if (value is List<String>) {
              listeners = value;
            } else {
              errors.add(TomlIssue(lineNo, 'listeners must be an array of strings.'));
            }
          case 'mtu':
            if (value is int) {
              mtu = value > 0 ? value : null;
            } else {
              errors.add(TomlIssue(lineNo, 'mtu must be an integer.'));
            }
          case 'dev_name':
            if (value is String) devName = value;
          default:
            unsupported.add(TomlIssue(lineNo, 'Key "$key" is not editable yet.'));
        }
    }
  }
  if (section == 'port_forward') flushPortForward(lines.length);
  if (section == 'acl_rules') flushRule();

  if (errors.isNotEmpty) {
    return TomlParseResult(errors: errors, warnings: warnings, unsupported: unsupported);
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
      peerUrls: sawPeers ? peers : base.peerUrls,
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
      proxyCidrs: sawProxy ? proxyCidrs : base.proxyCidrs,
      portForwards: sawPortForward ? portForwards : base.portForwards,
      aclRules: aclRules.isEmpty ? base.aclRules : aclRules,
    ),
    instanceId: instanceId,
    warnings: warnings,
    unsupported: unsupported,
  );
}

String _str(String value) => _jsonEncode(value);

String _jsonEncode(String value) {
  final b = StringBuffer('"');
  for (final ch in value.codeUnits) {
    switch (ch) {
      case 0x22:
        b.write(r'\"');
      case 0x5C:
        b.write(r'\\');
      case 0x0A:
        b.write(r'\n');
      case 0x0D:
        b.write(r'\r');
      case 0x09:
        b.write(r'\t');
      default:
        b.writeCharCode(ch);
    }
  }
  b.write('"');
  return b.toString();
}

String? _reverse(Map<String, int> map, int value) {
  for (final entry in map.entries) {
    if (entry.value == value) return entry.key;
  }
  return null;
}

String? _firstString(Object? value) {
  if (value is String) return value;
  if (value is List && value.isNotEmpty) return value.first.toString();
  return null;
}

List<String> _stringList(Object? value) {
  if (value is List) return value.map((e) => e.toString()).toList();
  if (value is String && value.isNotEmpty) return [value];
  return const [];
}

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

bool _balanced(String text) {
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
  if (value.startsWith('"') || value.startsWith("'")) return _parseString(value);
  if (value.startsWith('[')) return _parseStringArray(value);
  throw FormatException('Unsupported value "$value".');
}

String _parseString(String text) {
  final quote = text[0];
  final b = StringBuffer();
  var escaped = false;
  for (var i = 1; i < text.length; i++) {
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
      if (rest.isNotEmpty) throw const FormatException('Unexpected characters after string.');
      return b.toString();
    }
    b.write(ch);
  }
  throw const FormatException('Unterminated string.');
}

List<String> _parseStringArray(String text) {
  final values = <String>[];
  var i = 1;


  while (i < text.length) {
    while (i < text.length && ' \t\n,'.contains(text[i])) {
      i++;
    }
    if (i >= text.length) break;
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
