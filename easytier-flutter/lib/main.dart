import 'package:flutter/material.dart';

import 'app.dart';
import 'core/client/client_factory.dart';
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
  final client = await createCoreClient();

  final vpnService = createPlatformVpnService();
  final vpn = vpnService is UnsupportedVpnService
      ? null
      : VpnController(service: vpnService);

  runApp(EasytierApp(state: AppState(client: client, vpn: vpn)));
}
