import 'dart:io';

import 'ffi/ffi_core_client.dart';
import 'mock_core_client.dart';
import 'core_client.dart';

/// Selects the transport at boot.
///
/// Default is the mock core so the app runs on any machine without a Rust
/// toolchain (design review, widget tests, demos). The real transport is opt-in:
///
/// ```bash
/// flutter run --dart-define=EASYTIER_USE_FFI=true
/// # or
/// EASYTIER_USE_FFI=1 flutter run
/// ```
///
/// When FFI is requested but the native library cannot be loaded, the app falls
/// back to the mock and prints the loader diagnostics to stderr instead of
/// crashing on launch — the UI then shows a clearly labelled mock state rather
/// than pretending to be a working tunnel.
Future<CoreClient> createCoreClient({String? configDirectory}) async {
  final requested = const bool.fromEnvironment('EASYTIER_USE_FFI') ||
      _envFlag('EASYTIER_USE_FFI');
  if (!requested) return MockCoreClient();

  final client = FfiCoreClient(configDirectory: configDirectory);
  try {
    await client.init();
    return client;
  } catch (error) {
    stderr.writeln('EasyTier: native core unavailable, falling back to mock.\n$error');
    await client.dispose();
    return MockCoreClient();
  }
}

bool _envFlag(String name) {
  final value = Platform.environment[name]?.toLowerCase();
  return value == '1' || value == 'true' || value == 'yes';
}
