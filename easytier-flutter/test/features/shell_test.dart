import 'package:easytier_flutter/core/ui/et_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_app.dart';

void main() {
  setUpAll(loadEtFonts);
  testWidgets('phone shell exposes exactly five destinations', (tester) async {
    await pumpPhoneApp(tester, connect: false);

    expect(find.byType(NavigationBar), findsOneWidget);
    for (final destination in EtDestination.values) {
      expect(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(destination.label),
        ),
        findsOneWidget,
        reason: '${destination.label} tab missing',
      );
    }
    expect(find.byType(NavigationBar), findsOneWidget);
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.selectedIndex, EtDestination.home.index);
  });

  testWidgets('switching destination updates the shell selection', (tester) async {
    await pumpPhoneApp(tester, connect: false);

    await openDestination(tester, EtDestination.devices);
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.selectedIndex, EtDestination.devices.index);

    await openDestination(tester, EtDestination.settings);
    final bar2 = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar2.selectedIndex, EtDestination.settings.index);
  });

  testWidgets('desktop shell uses a rail instead of the bottom bar', (tester) async {
    await pumpDesktopApp(tester, connect: true);

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });
}
