import 'package:easytier_flutter/core/ui/et_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_app.dart';

void main() {
  setUpAll(loadEtFonts);

  testWidgets('client logs list, filter and clear', (tester) async {
    final state = await pumpPhoneApp(tester);
    await state.connect();
    await pumpFrames(tester, frames: 16);

    expect(state.logs.entries, isNotEmpty);
    expect(
      state.logs.entries.any((e) => e.message.contains('Connecting to')),
      isTrue,
    );

    await openDestination(tester, EtDestination.settings);
    final row = find.byKey(const Key('settings-logs-row'));
    await tester.ensureVisible(row);
    await pumpFrames(tester);
    await tester.tap(row);
    await pumpFrames(tester, frames: 40);

    expect(find.text('Client logs'), findsWidgets);
    expect(find.textContaining('Connecting to EasyTier Home'), findsWidgets);

    // Errors-only filter hides the info lines.
    await tester.tap(find.byKey(const Key('logs-filter-error')));
    await pumpFrames(tester, frames: 12);
    expect(find.text('No logs yet'), findsOneWidget);

    await tester.tap(find.byKey(const Key('logs-filter-all')));
    await pumpFrames(tester, frames: 12);
    await tester.tap(find.byKey(const Key('logs-clear')));
    await pumpFrames(tester, frames: 12);
    expect(find.text('No logs yet'), findsOneWidget);
    expect(state.logs.entries, isEmpty);
  });
}
