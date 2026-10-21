import 'package:easytier_flutter/core/ui/et_shell.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_app.dart';

void main() {
  setUpAll(loadEtFonts);

  testWidgets('switching to 中文 localizes the shell and main screens',
      (tester) async {
    final state = await pumpPhoneApp(tester);
    await openDestination(tester, EtDestination.settings);

    await tester.tap(find.text('中文'));
    await pumpFrames(tester, frames: 16);
    expect(state.locale.languageCode, 'zh');

    // Shell labels + Settings chrome are Chinese.
    expect(find.text('设置'), findsWidgets);
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('外观'), findsOneWidget);
    expect(find.text('核心与网络'), findsOneWidget);
    expect(find.text('关于'), findsOneWidget);

    // Home is Chinese too.
    await tester.tap(find.text('首页'));
    await pumpFrames(tester, frames: 16);
    expect(find.text('延迟'), findsOneWidget);

    // Switching back restores English immediately.
    await tester.tap(find.text('设置'));
    await pumpFrames(tester, frames: 12);
    await tester.tap(find.text('English'));
    await pumpFrames(tester, frames: 16);
    expect(state.locale.languageCode, 'en');
    expect(find.text('Appearance'), findsOneWidget);
  });
}
