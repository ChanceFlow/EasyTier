import 'dart:io';

import 'package:easytier_flutter/app.dart';
import 'package:easytier_flutter/core/client/mock_core_client.dart';
import 'package:easytier_flutter/core/models/models.dart';
import 'package:easytier_flutter/core/state/app_state.dart';
import 'package:easytier_flutter/core/ui/et_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads the bundled brand fonts into the test engine. Without this, widget
/// tests render every glyph with Ahem (blocks) and goldens are useless for
/// typography review.
Future<void> loadEtFonts() async {
  final families = <String, List<String>>{
    // Test-only fixtures: the app itself uses system fonts, but flutter_test
    // has no system font, so goldens would render Ahem boxes without these.
    // Merged with the Noto CJK subset: the test engine has no system font
    // fallback chain, so CJK glyphs would tofu in goldens otherwise.
    'Roboto': [
      'test/fixtures/fonts/roboto-regular-cjk.ttf',
      'test/fixtures/fonts/roboto-medium-cjk.ttf',
      'test/fixtures/fonts/roboto-bold-cjk.ttf',
    ],
    // EtText.mono resolves to the platform monospace family; register the
    // fixture under that family name for the test engine (Android target).
    'monospace': [
      'test/fixtures/fonts/robotomono-regular.ttf',
      'test/fixtures/fonts/robotomono-medium.ttf',
      'test/fixtures/fonts/robotomono-semibold.ttf',
    ],
    'Noto Sans SC': ['test/fixtures/fonts/noto-sans-sc-subset.ttf'],
    // Flutter's own M3 components (SegmentedButton check, dropdown arrows…)
    // use the built-in Material Icons font; the test harness does not load it.
    'MaterialIcons': ['test/fixtures/fonts/material-icons.otf'],
  };

  // Material Symbols ships as a package font (`fontPackage: material_symbols_icons`),
  // so the family the engine looks up is the package-prefixed name. Widget tests
  // do not auto-load package assets; register both spellings from the pub cache.
  final symbolsFont = _findPubCacheFont('material_symbols_icons', 'MaterialSymbolsOutlined.ttf');
  if (symbolsFont != null) {
    families['MaterialSymbolsOutlined'] = [symbolsFont];
    families['packages/material_symbols_icons/MaterialSymbolsOutlined'] = [symbolsFont];
  }

  for (final entry in families.entries) {
    final loader = FontLoader(entry.key);
    for (final path in entry.value) {
      final bytes = await File(path).readAsBytes();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }
}

/// Locates a file inside the material_symbols_icons package in the pub cache.
String? _findPubCacheFont(String package, String fileName) {
  final roots = <String>[
    ?Platform.environment['PUB_CACHE'],
    '${Platform.environment['HOME'] ?? ''}/.pub-cache',
    '/home/chance/Projects/.pub-cache',
  ];
  for (final root in roots) {
    final hosted = Directory('$root/hosted/pub.dev');
    if (!hosted.existsSync()) continue;
    for (final entry in hosted.listSync()) {
      if (!entry.path.contains(package)) continue;
      final candidate = File('${entry.path}/lib/fonts/$fileName');
      if (candidate.existsSync()) return candidate.path;
    }
  }
  return null;
}

/// A booted app on a phone-sized surface, connected, with deterministic data.
Future<AppState> pumpPhoneApp(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double pixelRatio = 2.0,
  bool connect = true,
}) async {
  return _pumpApp(tester, size: size, pixelRatio: pixelRatio, connect: connect);
}

Future<AppState> pumpDesktopApp(
  WidgetTester tester, {
  Size size = const Size(1280, 820),
  bool connect = true,
}) async {
  return _pumpApp(tester, size: size, pixelRatio: 1.0, connect: connect);
}

Future<AppState> _pumpApp(
  WidgetTester tester, {
  required Size size,
  required double pixelRatio,
  required bool connect,
}) async {
  tester.view.physicalSize = size * pixelRatio;
  tester.view.devicePixelRatio = pixelRatio;
  addTearDown(tester.view.reset);

  final state = AppState(
    client: MockCoreClient(
      startDelay: Duration.zero,
      clock: () => DateTime(2026, 10, 20, 12, 0, 0),
    ),
    // No polling timer: widget tests assert "no pending timers" at the end.
    pollInterval: null,
  );
  // Goldens are deterministic: the test VM reports light system brightness,
  // so the default shots pin the mode explicitly.
  state.setThemeMode(ThemeMode.dark);
  addTearDown(state.dispose);
  await tester.pumpWidget(
    RepaintBoundary(
      key: const Key('golden-root'),
      child: EasytierApp(state: state),
    ),
  );
  await pumpFrames(tester);
  if (connect) {
    // Start the async work, let the fake clock run, then await.
    final pending = state.connect();
    await pumpFrames(tester, frames: 12);
    await pending;
    await pumpFrames(tester);
  }
  return state;
}

/// Golden matcher for the whole app surface.
Future<void> expectAppGolden(WidgetTester tester, String name) async {
  await expectLater(
    find.byKey(const Key('golden-root')),
    matchesGoldenFile('goldens/$name.png'),
  );
}

/// Bounded frame pumping. `pumpAndSettle` is forbidden in this project:
/// screens may contain indeterminate progress indicators (intentionally —
/// they are honest loading states), which never settle.
Future<void> pumpFrames(WidgetTester tester, {int frames = 8, Duration step = const Duration(milliseconds: 40)}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(step);
  }
}

/// Navigator the tests can tap through the five destinations.
Future<void> openDestination(WidgetTester tester, EtDestination destination) async {
  final label = destination.label;
  final finder = find.descendant(
    of: find.byType(NavigationBar),
    matching: find.text(label),
  );
  final railFinder = find.descendant(
    of: find.byType(NavigationRail),
    matching: find.text(label),
  );
  await tester.tap(finder.evaluate().isNotEmpty ? finder.first : railFinder.first);
  await pumpFrames(tester);
}

/// Convenience for asserting mobile-only UI thresholds in reviews.
double contrastRatio(Color a, Color b) {
  final l1 = a.computeLuminance();
  final l2 = b.computeLuminance();
  final hi = l1 > l2 ? l1 : l2;
  final lo = l1 > l2 ? l2 : l1;
  return (hi + 0.05) / (lo + 0.05);
}

/// Guards the data model against accidental divergence between mock and FFI.
void expectStatusShape(InstanceStatus status) {
  expect(status.phase, isA<ConnectionPhase>());
  for (final peer in status.peers) {
    expect(peer.ipv4, isNotEmpty);
  }
}

// Imported here so test files that only use the helpers still resolve the
// navigation type without importing et_shell directly.