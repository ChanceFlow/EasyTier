import 'package:easytier_flutter/core/ui/et_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_app.dart';

void main() {
  setUpAll(loadEtFonts);

  testWidgets('source editor imports TOML from the clipboard', (tester) async {
    final clipboard = <String, Object?>{};
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        switch (call.method) {
          case 'Clipboard.setData':
            clipboard['text'] = (call.arguments as Map)['text'];
          case 'Clipboard.getData':
            return {'text': clipboard['text']};
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await pumpPhoneApp(tester);
    await openDestination(tester, EtDestination.config);
    await tester.tap(find.byTooltip('Edit TOML source'));
    await pumpFrames(tester, frames: 16);

    clipboard['text'] = 'network_name = "Imported Net"\nmtu = 1300\n';
    await tester.tap(find.byKey(const Key('source-import')));
    await pumpFrames(tester, frames: 16);

    final field = tester.widget<TextField>(
      find.byKey(const Key('source-editor-field')),
    );
    expect(field.controller!.text, contains('Imported Net'));
    expect(find.text('Valid TOML'), findsOneWidget);
  });

  testWidgets('share sheet copies an invitation with optional secret',
      (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await pumpPhoneApp(tester);
    await openDestination(tester, EtDestination.config);
    await tester.tap(find.byKey(const Key('config-overflow')));
    await pumpFrames(tester, frames: 12);
    await tester.tap(find.text('Share network…').last);
    await pumpFrames(tester, frames: 16);

    expect(find.text('Share network'), findsOneWidget);
    expect(find.textContaining('Network: EasyTier Home'), findsOneWidget);
    expect(find.textContaining('ask me privately'), findsOneWidget);

    await tester.tap(find.byKey(const Key('share-include-secret')));
    await pumpFrames(tester, frames: 12);
    expect(find.textContaining('Secret: correct-horse-battery'), findsOneWidget);

    await tester.tap(find.byKey(const Key('share-copy')));
    await pumpFrames(tester, frames: 12);
    expect(copied, contains('correct-horse-battery'));
  });
}
