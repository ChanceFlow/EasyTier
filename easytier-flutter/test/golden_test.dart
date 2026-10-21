@Tags(['golden'])
library;

import 'package:easytier_flutter/core/ui/et_shell.dart' show EtDestination;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app.dart';

/// Golden coverage for the five destinations on phone + the desktop shell.
///
/// Regenerate: `flutter test --update-goldens test/golden_test.dart`
/// Review the PNGs in `test/goldens/` — they are the design review artifact.
/// All data is deterministic (mock clock + fixed seed), so a diff means the UI
/// changed, not the data.
void main() {
  setUpAll(loadEtFonts);
  testWidgets('home — connected (phone)', (tester) async {
    await pumpPhoneApp(tester);
    await expectAppGolden(tester, 'home_phone_connected');
  });

  testWidgets('home — stopped (phone)', (tester) async {
    await pumpPhoneApp(tester, connect: false);
    await expectAppGolden(tester, 'home_phone_stopped');
  });

  testWidgets('devices (phone)', (tester) async {
    await pumpPhoneApp(tester);
    await openDestination(tester, EtDestination.devices);
    await expectAppGolden(tester, 'devices_phone');
  });

  testWidgets('config (phone)', (tester) async {
    await pumpPhoneApp(tester);
    await openDestination(tester, EtDestination.config);
    await expectAppGolden(tester, 'config_phone');
  });

  testWidgets('activity (phone)', (tester) async {
    await pumpPhoneApp(tester);
    await openDestination(tester, EtDestination.activity);
    await expectAppGolden(tester, 'activity_phone');
  });

  testWidgets('settings (phone)', (tester) async {
    await pumpPhoneApp(tester);
    await openDestination(tester, EtDestination.settings);
    await expectAppGolden(tester, 'settings_phone');
  });

  testWidgets('light theme — home connected (phone)', (tester) async {
    final state = await pumpPhoneApp(tester);
    state.setThemeMode(ThemeMode.light);
    await pumpFrames(tester);
    await expectAppGolden(tester, 'home_phone_light');
  });

  testWidgets('home — connected (desktop rail)', (tester) async {
    await pumpDesktopApp(tester);
    await expectAppGolden(tester, 'home_desktop_connected');
  });

  testWidgets('config (desktop)', (tester) async {
    await pumpDesktopApp(tester);
    await openDestination(tester, EtDestination.config);
    await expectAppGolden(tester, 'config_desktop');
  });

}
