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

  testWidgets('settings lists clean commercial M3 groups and version metadata',
      (tester) async {
    await pumpPhoneApp(tester);
    await openDestination(tester, EtDestination.settings);

    for (final title in [
      'Appearance',
      'Core & Networking',
      'About',
    ]) {
      expect(_inSettings(find.text(title)), findsOneWidget,
          reason: 'missing section $title');
    }

    final page = tester.widget<EtPage>(_inSettings(find.byType(EtPage)));
    expect(page.title, 'Settings');
    expect(page.subtitle, 'Preferences & core runtime');

    expect(_inSettings(find.text('2.6.4+9')), findsOneWidget);
    expect(_inSettings(find.text('2.7.0-mock')), findsOneWidget);
    expect(_inSettings(find.text('Normal (in-process)')), findsOneWidget);
    expect(_inSettings(find.text('Documentation')), findsOneWidget);
    expect(_inSettings(find.text('Source repository')), findsOneWidget);
  });

  testWidgets('appearance segmented pill applies the theme immediately',
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

  testWidgets('language segmented pill stores the locale', (tester) async {
    final state = await pumpPhoneApp(tester);
    await openDestination(tester, EtDestination.settings);

    await tester.tap(_inSettings(find.text('中文')));
    await pumpFrames(tester, frames: 12);
    expect(state.locale.languageCode, 'zh');

    await tester.tap(_inSettings(find.text('English')));
    await pumpFrames(tester, frames: 12);
    expect(state.locale.languageCode, 'en');
  });

  testWidgets('config server row opens bottom sheet and persists server URL',
      (tester) async {
    final state = await pumpPhoneApp(tester);
    await openDestination(tester, EtDestination.settings);

    expect(_inSettings(find.text('Off')), findsOneWidget);

    final row = find.byKey(const Key('settings-config-server-row'));
    await tester.ensureVisible(row);
    await pumpFrames(tester);
    await tester.tap(row);
    await pumpFrames(tester, frames: 12);

    final input = find.byKey(const Key('settings-config-server-input'));
    expect(input, findsOneWidget);
    await tester.enterText(input, 'https://config.easytier.cn');
    await pumpFrames(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await pumpFrames(tester, frames: 12);

    expect(state.configServerUrl, 'https://config.easytier.cn');
    expect(_inSettings(find.text('Configured')), findsOneWidget);
    expect(_inSettings(find.text('https://config.easytier.cn')), findsOneWidget);
  });

  testWidgets('log level menu updates state logLevel preference',
      (tester) async {
    final state = await pumpPhoneApp(tester);
    await openDestination(tester, EtDestination.settings);

    expect(state.logLevel, 'info');
    final row = find.byKey(const Key('settings-log-level-row'));
    await tester.ensureVisible(row);
    await pumpFrames(tester);
    await tester.tap(row);
    await pumpFrames(tester, frames: 12);

    await tester.tap(find.text('debug').last);
    await pumpFrames(tester, frames: 12);

    expect(state.logLevel, 'debug');
    expect(_inSettings(find.text('debug')), findsOneWidget);
  });

  testWidgets('Settings never overflows at 320px', (tester) async {
    tester.view.physicalSize = const Size(320, 640) * 2.0;
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

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
}
