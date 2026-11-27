import 'package:flutter/material.dart';

import 'app.dart';
import 'core/client/client_factory.dart';
import 'core/platform/app_directories.dart';
import 'core/state/app_state.dart';
import 'core/system_ui.dart';
import 'core/vpn/vpn_controller.dart';
import 'core/vpn/vpn_service.dart';

/// Entry point.
///
/// The transport is chosen in `createCoreClient`:
///  * default → `MockCoreClient` (UI runs without a Rust toolchain);
///  * `--dart-define=EASYTIER_USE_FFI=true` or `EASYTIER_USE_FFI=1` →
///    `FfiCoreClient` over the `easytier-ffi` C ABI.
///
/// On Android a `VpnController` is attached to AppState; it owns the
/// `VpnService` tunnel and hands the fd to the core. Other platforms get no
/// controller (the future desktop path creates its own TUN device).
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  enableEtEdgeToEdge();

  // The core persists configurations itself, but inside a mobile sandbox only
  // the host knows where that may write. Asking first keeps the saved network
  // list across restarts; without it the client used an unwritable temp path
  // and looked like it had no networks at all.
  final configDirectory = await AppDirectories.configDirectory();
  final client = await createCoreClient(configDirectory: configDirectory);

  final vpnService = createPlatformVpnService();
  final vpn = vpnService is UnsupportedVpnService
      ? null
      : VpnController(service: vpnService);

  runApp(EasytierApp(state: AppState(client: client, vpn: vpn)));
}
