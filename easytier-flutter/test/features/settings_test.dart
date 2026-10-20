import 'package:easytier_flutter/core/client/mock_core_client.dart';
import 'package:easytier_flutter/core/models/models.dart';
import 'package:easytier_flutter/core/state/app_state.dart';
import 'package:easytier_flutter/core/theme/theme.dart';
import 'package:easytier_flutter/core/ui/et_shell.dart';
import 'package:easytier_flutter/features/settings/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_app.dart';

Finder _inSettings(Finder finder) => find.descendant(
      of: find.byType(SettingsPage),
      matching: finder,
    );

void main() {
  setUpAll(loadEtFonts);
  testWidgets('settings lists every group and the active instance name',
      (tester) async {
    await pumpPhoneApp(tester);
    await openDestination(tester, EtDestination.settings);

    for (final title in [
      'Appearance',
      'Language',
      'Core',
      'Config server',
      'Logs',
      'About',
      'Danger zone',
    ]) {
      expect(_inSettings(find.text(title)), findsOneWidget,
          reason: 'missing section $title');
    }

    final page = tester.widget<EtPage>(_inSettings(find.byType(EtPage)));
    expect(page.title, 'Settings');
    expect(page.subtitle, 'office-mesh');
    // The core version is read from the client and shown in Core and About.
    expect(_inSettings(find.text('2.7.0-mock')), findsNWidgets(2));
    expect(_inSettings(find.text('Normal (in-process)')), findsOneWidget);
    expect(_inSettings(find.text('UI language (coming in M2)')), findsOneWidget);
  });

  testWidgets('appearance segmented control applies the theme immediately',
      (tester) async {
    final state = await pumpPhoneApp(tester);
    await openDestination(tester, EtDestination.settings);

    MaterialApp app() => tester.widget<MaterialApp>(find.byType(MaterialApp));

    expect(state.themeMode, ThemeMode.dark);
    expect(app().themeMode, ThemeMode.dark);

    await tester.tap(_inSettings(find.text('Light')));
    await pumpFrames(tester, frames: 12);
    expect(state.themeMode, ThemeMode.light);
    expect(app().themeMode, ThemeMode.light);
    expect(
      Theme.of(tester.element(_inSettings(find.text('Appearance')))).brightness,
      Brightness.light,
    );

    await tester.tap(_inSettings(find.text('System')));
    await pumpFrames(tester, frames: 12);
    expect(state.themeMode, ThemeMode.system);
    expect(app().themeMode, ThemeMode.system);
  });

  testWidgets('language segmented control stores the locale', (tester) async {
    final state = await pumpPhoneApp(tester);
    await openDestination(tester, EtDestination.settings);

    await tester.tap(_inSettings(find.text('中文')));
    await pumpFrames(tester, frames: 12);
    expect(state.locale.languageCode, 'zh');

    await tester.tap(_inSettings(find.text('English')));
    await pumpFrames(tester, frames: 12);
    expect(state.locale.languageCode, 'en');
  });

  testWidgets('unavailable rows are honest: disabled with an M2 tooltip',
      (tester) async {
    await pumpPhoneApp(tester);
    await openDestination(tester, EtDestination.settings);

    // Config server "Connect": disabled button with a tooltip and a visible badge.
    expect(find.byTooltip('M2'), findsOneWidget);
    expect(_inSettings(find.text('M2')), findsAtLeastNWidgets(1));

    // Docs and repo link placeholders are disabled too, never fake links.
    expect(find.byTooltip('Coming in M2'), findsNWidgets(2));
    expect(_inSettings(find.text('Documentation')), findsOneWidget);
    expect(_inSettings(find.text('Source repository')), findsOneWidget);
  });

  testWidgets('log level stays a local preference', (tester) async {
    await pumpPhoneApp(tester);
    await openDestination(tester, EtDestination.settings);

    // Log level is an M3 DropdownMenu; assert the field's text rather than the
    // popup's menu-item widgets.
    final menu = _inSettings(
      find.byWidgetPredicate((widget) => widget is DropdownMenu),
    );
    expect(menu, findsOneWidget);
    expect(
      tester.widget<TextField>(_inSettings(find.byType(TextField)).last)
          .controller!
          .text,
      'info',
    );

    await tester.ensureVisible(menu);
    await pumpFrames(tester);
    await tester.tap(
      find.descendant(of: menu, matching: find.byIcon(Icons.arrow_drop_down)),
    );
    await pumpFrames(tester, frames: 12);
    await tester.tap(find.text('debug').last);
    await pumpFrames(tester, frames: 16);

    expect(
      tester.widget<TextField>(_inSettings(find.byType(TextField)).last)
          .controller!
          .text,
      'debug',
    );
  });

  testWidgets('Settings never overflows at 320px', (tester) async {
    tester.view.physicalSize = const Size(320, 640) * 2.0;
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    // Scoped harness: the real settings page composition without the shell, so
    // an offstage tab cannot fail this check.
    final state = AppState(
      client: MockCoreClient(startDelay: Duration.zero),
      pollInterval: null,
    );
    addTearDown(state.dispose);
    state.instances = const [
      NetworkInstance(
        id: 'inst-1',
        config: NetworkConfig(
          instanceName: 'office-mesh',
          hostname: 'chance-desktop',
          networkName: 'EasyTier Home',
        ),
      ),
    ];
    state.activeId = 'inst-1';

    await tester.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildEtTheme(brightness: Brightness.dark),
          home: const SettingsPage(),
        ),
      ),
    );
    await pumpFrames(tester);

    expect(tester.takeException(), isNull);
    expect(_inSettings(find.text('Appearance')), findsOneWidget);
  });

  testWidgets('deleting the active network confirms first, then removes it',
      (tester) async {
    final state = await pumpPhoneApp(tester);
    await openDestination(tester, EtDestination.settings);

    expect(state.instances, hasLength(1));

    await tester.ensureVisible(_inSettings(find.text('Delete this network')));
    await pumpFrames(tester);
    await tester.tap(_inSettings(find.text('Delete this network')));
    await pumpFrames(tester);
    expect(find.text('Delete this network?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await pumpFrames(tester);
    expect(find.text('Delete this network?'), findsNothing);
    expect(state.instances, hasLength(1));

    await tester.ensureVisible(_inSettings(find.text('Delete this network')));
    await pumpFrames(tester);
    await tester.tap(_inSettings(find.text('Delete this network')));
    await pumpFrames(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await pumpFrames(tester, frames: 12);

    expect(state.instances, isEmpty);
    expect(find.text('Network deleted'), findsOneWidget);
    expect(_inSettings(find.text('Danger zone')), findsNothing);
    expect(
      tester.widget<EtPage>(_inSettings(find.byType(EtPage))).subtitle,
      'No network',
    );

    // Let the snackbar's dismissal timer run out before letting the test end.
    await tester.pump(const Duration(seconds: 5));
    await pumpFrames(tester);
  });
}
