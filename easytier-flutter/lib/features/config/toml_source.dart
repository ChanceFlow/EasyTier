import '../../core/config/canonical_toml.dart';
import '../../core/models/models.dart';

export '../../core/config/canonical_toml.dart'
    show TomlIssue, TomlParseResult, encodeConfigToml, parseConfigToml;

/// Backwards-compatible wrapper used by the source editor/tests.
String networkConfigToToml(
  NetworkConfig config, {
  String instanceId = '00000000-0000-0000-0000-000000000000',
}) =>
    encodeConfigToml(config, instanceId: instanceId);

TomlParseResult parseNetworkConfigToml(
  String source, {
  required NetworkConfig base,
}) =>
    parseConfigToml(source, base: base);
