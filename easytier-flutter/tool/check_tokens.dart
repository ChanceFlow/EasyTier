// Executable proof that the EasyTier Flutter token layer is genuine Material 3
// and that every colour pair the UI actually renders clears WCAG 2.1 AA.
//
// This is the Flutter counterpart of `design-system/easytier/check-contrast.py`
// for the web console. It does not parse hex from the design docs: it builds the
// **real** `ColorScheme.fromSeed` for the Google-blue seed, wraps it in the real
// `EtPalette` ThemeExtension, derives the same `ThemeData` the app ships and then
// measures contrast on the values Flutter actually produces.
//
// Run it with the Flutter test harness (the only headless Dart VM in this repo
// that can load `dart:ui`, which `ColorScheme` needs):
//
//   bash /home/chance/Projects/.flutter-run.sh \
//        /home/chance/Projects/easytier/easytier-flutter test tool/check_tokens.dart
//
// Exit status: 0 = every assertion passed, 1 = at least one contrast or token
// assertion failed (the failure prints the offending pair and its ratio).
//
// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math' as math;

import 'package:easytier_flutter/core/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG 2.1 AA floor for normal-size text.
const double _textMin = 4.5;

/// WCAG 2.1 AA floor for non-text content (icons, borders, indicators, chart
/// lines) and for large text.
const double _graphicsMin = 3.0;

/// One measured foreground/background pair.
class _Pair {
  const _Pair(this.foreground, this.background, this.min, {this.note});

  final String foreground;
  final String background;
  final double min;

  /// Why the pair is held to [min] when that is not obvious from the roles.
  final String? note;
}

/// Text pairs: both sides are text-bearing roles, held to 4.5:1.
const List<_Pair> _textPairs = [
  // Filled and tonal containers that carry labels.
  _Pair('onPrimary', 'primary', _textMin),
  _Pair('onPrimaryContainer', 'primaryContainer', _textMin),
  _Pair('onSecondaryContainer', 'secondaryContainer', _textMin),
  _Pair('onTertiaryContainer', 'tertiaryContainer', _textMin),
  _Pair('onError', 'error', _textMin),
  _Pair('onErrorContainer', 'errorContainer', _textMin),
  // The M3 surface-container ladder: onSurface and onSurfaceVariant are the two
  // text roles, and every surface level is a legal background for them.
  _Pair('onSurface', 'surface', _textMin),
  _Pair('onSurface', 'surfaceContainerLowest', _textMin),
  _Pair('onSurface', 'surfaceContainerLow', _textMin),
  _Pair('onSurface', 'surfaceContainer', _textMin),
  _Pair('onSurface', 'surfaceContainerHigh', _textMin),
  _Pair('onSurface', 'surfaceContainerHighest', _textMin),
  _Pair('onSurfaceVariant', 'surface', _textMin),
  _Pair('onSurfaceVariant', 'surfaceContainerLowest', _textMin),
  _Pair('onSurfaceVariant', 'surfaceContainerLow', _textMin),
  _Pair('onSurfaceVariant', 'surfaceContainer', _textMin),
  _Pair('onSurfaceVariant', 'surfaceContainerHigh', _textMin),
  _Pair('onSurfaceVariant', 'surfaceContainerHighest', _textMin),
  // Semantic roles are also used as inline text (statuses, errors, links).
  _Pair('primary', 'surface', _textMin),
  _Pair('primary', 'surfaceContainerLow', _textMin),
  _Pair('error', 'surface', _textMin),
  _Pair('error', 'surfaceContainerLow', _textMin),
  _Pair('warning', 'surface', _textMin),
  _Pair('warning', 'surfaceContainerLow', _textMin),
  // Custom M3 extension roles added by tokens.dart (success / warning): the
  // design system allows them to tint a status label, so they are held to the
  // text floor in both themes.
  _Pair('onSuccess', 'success', _textMin),
  _Pair('success', 'surface', _textMin),
  _Pair('success', 'surfaceContainerLow', _textMin),
  _Pair('onWarning', 'warning', _textMin),
  _Pair('onSuccessContainer', 'successContainer', _textMin),
  _Pair('onWarningContainer', 'warningContainer', _textMin),
  // Snackbar content is onInverseSurface over inverseSurface.
  _Pair('onInverseSurface', 'inverseSurface', _textMin),
];

/// Non-text pairs: outlines, focus rings and status glyphs, held to 3:1.
const List<_Pair> _graphicsPairs = [
  _Pair('outline', 'surface', _graphicsMin, note: 'control boundary'),
  _Pair('outline', 'surfaceContainerLow', _graphicsMin, note: 'control boundary on a card'),
  _Pair('outline', 'surfaceContainer', _graphicsMin, note: 'control boundary on an input row'),
  _Pair('outline', 'surfaceContainerHigh', _graphicsMin, note: 'control boundary on a raised row'),
  _Pair('primary', 'surface', _graphicsMin, note: 'focus ring / selected indicator'),
  _Pair('tertiary', 'surface', _graphicsMin, note: 'secondary chart series'),
];

/// Pairs that are printed for information but never asserted.
const List<_Pair> _infoPairs = [
  _Pair('outlineVariant', 'surface', 0, note: 'decorative divider - no contract'),
];

void main() {
  test('M3 colour roles meet WCAG 2.1 AA in light and dark', () {
    final failures = <String>[];
    final allRows = <_Measured>[];

    for (final brightness in Brightness.values) {
      final scheme = ColorScheme.fromSeed(
        seedColor: EtPalette.seed,
        brightness: brightness,
      );
      final palette = EtPalette.of(scheme);
      final roles = _roleValues(scheme, palette);
      final themeLabel = brightness == Brightness.light ? 'light' : 'dark';

      print('\nM3 colour roles - $themeLabel '
          '(seed ${_hex(EtPalette.seed)}, ColorScheme.fromSeed ${brightness.name})');
      print('  ${_pad('foreground', 26)} ${_pad('background', 27)} '
          '${_pad('ratio', 7)} ${_pad('min', 5)} ${_pad('margin', 8)} status');

      for (final group in [
        ('TEXT  4.5:1', _textPairs),
        ('GRAPHICAL  3.0:1', _graphicsPairs),
      ]) {
        print('  -- ${group.$1}');
        for (final pair in group.$2) {
          final measured = _measure(themeLabel, pair, roles);
          allRows.add(measured);
          print(measured.row);
          if (!measured.passes) failures.add(measured.detail);
        }
      }

      print('  -- INFO (not asserted)');
      for (final pair in _infoPairs) {
        final measured = _measure(themeLabel, pair, roles, assertIt: false);
        print(measured.row);
      }
      final disabled = Color.alphaBlend(
        scheme.onSurface.withValues(alpha: 0.38),
        scheme.surface,
      );
      final disabledRatio = _contrast(disabled, scheme.surface);
      print('  ${_pad('disabled label', 26)} ${_pad('surface (38% onSurface)', 27)} '
          '${_pad('${disabledRatio.toStringAsFixed(2)}:1', 7)} ${_pad('-', 5)} '
          '${_pad('-', 8)} INFO  # M3 38% disabled content, WCAG-exempt');
    }

    final asserts = allRows.length;
    final passed = allRows.where((row) => row.passes).length;
    final tightest = allRows
        .where((row) => row.passes)
        .reduce((a, b) => a.margin <= b.margin ? a : b);

    print('\nRESULT: ${failures.isEmpty ? 'PASS' : 'FAIL'} '
        '- $passed/$asserts assertions across 2 themes');
    print('Tightest passing margin: ${tightest.label} = '
        '${tightest.ratio.toStringAsFixed(2)}:1 '
        '(${_signed(tightest.margin)} over its ${tightest.min.toStringAsFixed(1)} floor)');

    expect(
      failures,
      isEmpty,
      reason: 'M3 contrast gate failed (WCAG 2.1 AA):\n${failures.join('\n')}',
    );
  });

  test('EtPalette aliases M3 roles instead of re-introducing a bespoke palette', () {
    for (final brightness in Brightness.values) {
      final scheme = ColorScheme.fromSeed(
        seedColor: EtPalette.seed,
        brightness: brightness,
      );
      final palette = EtPalette.of(scheme);

      expect(palette.scheme, scheme, reason: 'EtPalette must wrap the real scheme');
      expect(palette.isDark, brightness == Brightness.dark);

      // Every app alias must resolve to an M3 role, not to a private hex value.
      final aliases = <String, Color>{
        'bg': palette.bg,
        'surface1': palette.surface1,
        'surface2': palette.surface2,
        'surface3': palette.surface3,
        'sunken': palette.sunken,
        'border': palette.border,
        'borderStrong': palette.borderStrong,
        'controlBorder': palette.controlBorder,
        'scrim': palette.scrim,
        'text': palette.text,
        'text2': palette.text2,
        'text3': palette.text3,
        'accent': palette.accent,
        'onAccent': palette.onAccent,
        'accentQuiet': palette.accentQuiet,
        'accentOnTint': palette.accentOnTint,
        'info': palette.info,
        'onInfo': palette.onInfo,
        'infoQuiet': palette.infoQuiet,
        'infoOnTint': palette.infoOnTint,
        'warn': palette.warn,
        'onWarn': palette.onWarn,
        'warnQuiet': palette.warnQuiet,
        'warnOnTint': palette.warnOnTint,
        'danger': palette.danger,
        'onDanger': palette.onDanger,
        'dangerQuiet': palette.dangerQuiet,
        'dangerOnTint': palette.dangerOnTint,
        'neutral': palette.neutral,
        'neutralQuiet': palette.neutralQuiet,
        'focus': palette.focus,
      };
      final expected = <String, Color>{
        'bg': scheme.surface,
        'surface1': scheme.surfaceContainerLow,
        'surface2': scheme.surfaceContainer,
        'surface3': scheme.surfaceContainerHigh,
        'sunken': scheme.surfaceContainerLowest,
        'border': scheme.outlineVariant,
        'borderStrong': scheme.outline,
        'controlBorder': scheme.outline,
        'scrim': scheme.scrim,
        'text': scheme.onSurface,
        'text2': scheme.onSurfaceVariant,
        'text3': scheme.onSurfaceVariant,
        'accent': scheme.primary,
        'onAccent': scheme.onPrimary,
        'accentQuiet': scheme.primaryContainer,
        'accentOnTint': scheme.onPrimaryContainer,
        'info': scheme.primary,
        'onInfo': scheme.onPrimary,
        'infoQuiet': scheme.secondaryContainer,
        'infoOnTint': scheme.onSecondaryContainer,
        'warn': palette.warning,
        'onWarn': palette.onWarning,
        'warnQuiet': palette.warningContainer,
        'warnOnTint': palette.onWarningContainer,
        'danger': scheme.error,
        'onDanger': scheme.onError,
        'dangerQuiet': scheme.errorContainer,
        'dangerOnTint': scheme.onErrorContainer,
        'neutral': scheme.onSurfaceVariant,
        'neutralQuiet': scheme.surfaceContainerHighest,
        'focus': scheme.primary,
      };

      aliases.forEach((name, value) {
        expect(value, expected[name], reason: '$name must come from the M3 scheme');
      });

      // Disabled content is the one place the M3 38% rule is allowed.
      final disabled = palette.textDisabled;
      expect(disabled.a, closeTo(0.38, 0.001),
          reason: 'M3 disabled content is onSurface at 38% opacity');
    }
  });

  test('The shipped ThemeData is Material 3 with M3 component defaults', () {
    for (final brightness in Brightness.values) {
      final theme = buildEtTheme(brightness: brightness);
      final scheme = ColorScheme.fromSeed(
        seedColor: EtPalette.seed,
        brightness: brightness,
      );

      expect(theme.useMaterial3, isTrue, reason: 'Material 3 must stay enabled');
      expect(theme.colorScheme.primary, scheme.primary);
      expect(theme.extension<EtPalette>(), isNotNull,
          reason: 'EtPalette must be registered as a ThemeExtension');
      expect(theme.scaffoldBackgroundColor, scheme.surface);
      expect(theme.appBarTheme.backgroundColor, scheme.surface,
          reason: 'M3 top app bar sits on the surface role');
      expect(theme.appBarTheme.elevation, 0);
      expect(theme.appBarTheme.scrolledUnderElevation, 3,
          reason: 'M3 level-3 tint when content scrolls under the bar');
      expect(theme.cardTheme.color, scheme.surfaceContainerLow,
          reason: 'M3 elevated card background');
      expect(theme.cardTheme.elevation, 1);
      expect(_radiusOf(theme.cardTheme.shape), 24,
          reason: 'expressive card corner radius is 24dp (EtRadius.card)');
      expect(_radiusOf(theme.dialogTheme.shape), 28,
          reason: 'M3 dialog corner radius is 28dp');
      expect(_radiusOf(theme.bottomSheetTheme.shape), 28,
          reason: 'M3 modal bottom sheet corner radius is 28dp');
      expect(theme.bottomSheetTheme.showDragHandle, isTrue);
      expect(_radiusOf(theme.inputDecorationTheme.border), 4,
          reason: 'M3 outlined text field radius is 4dp');
      expect(_radiusOf(theme.inputDecorationTheme.focusedBorder), 4);
      expect(theme.navigationBarTheme.height, 76,
          reason: 'expressive navigation bar is taller than the M3 default');
      expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);
      expect(_radiusOf(theme.snackBarTheme.shape), 4,
          reason: 'M3 snackbar corner radius is 4dp');
      expect(theme.textTheme.bodyLarge, isNotNull);

      final compact = buildEtTheme(brightness: brightness, compact: true);
      expect(compact.visualDensity, VisualDensity.compact,
          reason: 'wide-window density must lower M3 component heights');
    }
  });

  test('Type, shape, spacing and motion tokens follow the M3 scales', () {
    // M3 type scale (material_2021): labelSmall 11, bodySmall 12, bodyMedium 14,
    // bodyLarge/titleMedium 16, titleLarge 22, headlineMedium 28, displaySmall 36.
    expect(EtType.micro, 11);
    expect(EtType.caption, 12);
    expect(EtType.bodySm, 14);
    expect(EtType.body, 16);
    expect(EtType.title, 16);
    expect(EtType.headline, 22);
    expect(EtType.display, 28);
    expect(EtType.hero, 36);

    // Typography is the platform's system stack: UI text sets no family and
    // inherits it; machine data uses the platform monospace family.
    expect(EtText.ui().fontFamily, isNull,
        reason: 'UI text must inherit the system font, not a bundled family');
    expect(EtText.uiFallback, contains('Noto Sans SC'));
    expect(
      EtText.monoFamily,
      isIn(['monospace', 'Menlo', 'Consolas']),
      reason: 'mono must resolve to a platform monospace family',
    );
    expect(EtText.mono().fontFamily, EtText.monoFamily);

    // Expressive layer (v5): display size, hero radius, spring, accents, nav.
    expect(EtType.expressive, 45);
    expect(EtRadius.card, 24);
    expect(EtRadius.hero, 32);
    expect(EtCurves.spring != EtCurves.standard, isTrue,
        reason: 'spring overshoot must differ from the standard curve');
    expect(EtAccent.byIndex(0), isNotNull);

    // M3 shape scale.
    expect(EtRadius.xs, 4);
    expect(EtRadius.sm, 8);
    expect(EtRadius.md, 12);
    expect(EtRadius.lg, 16);
    expect(EtRadius.xl, 28);

    // M3 spacing base unit is 4dp.
    expect(EtSpace.x1, 4);
    expect(EtSpace.x2, 8);
    expect(EtSpace.x3, 12);
    expect(EtSpace.x4, 16);
    expect(EtSpace.x6, 24);
    expect(EtSpace.x12, 48);
    expect(EtSpace.gutter(400), 16);
    expect(EtSpace.gutter(1200), 24);

    // M3 duration tokens: short2 100, short3 150, short4 200, medium2 300.
    expect(EtDuration.instant, const Duration(milliseconds: 100));
    expect(EtDuration.fast, const Duration(milliseconds: 150));
    expect(EtDuration.base, const Duration(milliseconds: 200));
    expect(EtDuration.slow, const Duration(milliseconds: 300));

    // M3 easing: standard + emphasized decelerate/accelerate.
    expect(EtCurves.standard, const Cubic(0.2, 0.0, 0.0, 1.0));
    expect(EtCurves.enter, const Cubic(0.05, 0.7, 0.1, 1.0));
    expect(EtCurves.exit, const Cubic(0.3, 0.0, 0.8, 0.15));
  });

  test('text fonts are system fonts; only the Material Symbols icon font ships', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec.contains('material_symbols_icons'), isTrue,
        reason: 'icons must come from Material Symbols, not a bespoke icon font');
    expect(pubspec.contains('phosphor'), isFalse,
        reason: 'the v3 Phosphor icon font must not come back');
    // No bundled text fonts: the app must use the platform's system UI font.
    expect(pubspec.contains('assets/fonts'), isFalse,
        reason: 'text fonts must not be bundled; use the system font');
    expect(RegExp(r'^\s*fonts:', multiLine: true).hasMatch(pubspec), isFalse,
        reason: 'pubspec must not declare a flutter fonts section');
    expect(Directory('assets/fonts').existsSync(), isFalse,
        reason: 'bundled font directory must be gone');
    // The font files left in the repo are test fixtures only (flutter_test has
    // no system fonts, so goldens need a deterministic face).
    for (final fixture in [
      'test/fixtures/fonts/roboto-regular.ttf',
      'test/fixtures/fonts/robotomono-regular.ttf',
      'test/fixtures/fonts/noto-sans-sc-subset.ttf',
    ]) {
      expect(File(fixture).existsSync(), isTrue, reason: 'missing test fixture: $fixture');
    }

    // A quick icon-import sanity check over the kit: Symbols.* only, no Material
    // Icons.* fallback and no emoji as structural glyphs.
    final kit = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    for (final file in kit) {
      final source = file.readAsStringSync();
      expect(source.contains('phosphor_flutter'), isFalse,
          reason: '${file.path} still imports Phosphor');
      expect(RegExp(r'Icons\.[a-z]').hasMatch(source), isFalse,
          reason: '${file.path} mixes Material Icons with Material Symbols');
    }
  });
}

// --------------------------------------------------------------------------
// Measurement
// --------------------------------------------------------------------------

class _Measured {
  const _Measured({
    required this.label,
    required this.ratio,
    required this.min,
    required this.passes,
    required this.row,
    required this.detail,
  });

  final String label;
  final double ratio;
  final double min;
  final bool passes;
  final String row;
  final String detail;

  double get margin => ratio - min;
}

_Measured _measure(
  String themeLabel,
  _Pair pair,
  Map<String, Color> roles, {
  bool assertIt = true,
}) {
  final fg = roles[pair.foreground];
  final bg = roles[pair.background];
  if (fg == null || bg == null) {
    throw StateError(
      'unknown M3 role in pair ${pair.foreground}/${pair.background}',
    );
  }
  final ratio = _contrast(fg, bg);
  final passes = !assertIt || ratio + 0.005 >= pair.min;
  final label = '${pair.foreground} / ${pair.background}';
  final margin = ratio - pair.min;
  final note = pair.note == null ? '' : '  # ${pair.note}';
  final row = '  ${_pad(pair.foreground, 26)} ${_pad(pair.background, 27)} '
      '${_pad('${ratio.toStringAsFixed(2)}:1', 7)} '
      '${_pad(pair.min == 0 ? '-' : pair.min.toStringAsFixed(1), 5)} '
      '${_pad(pair.min == 0 ? '-' : _signed(margin), 8)} '
      '${assertIt ? (passes ? 'PASS' : 'FAIL') : 'INFO'}$note';
  final detail = '$themeLabel $label = ${ratio.toStringAsFixed(2)}:1 '
      '(minimum ${pair.min.toStringAsFixed(1)}:1)';
  return _Measured(
    label: '$themeLabel $label',
    ratio: ratio,
    min: pair.min,
    passes: passes,
    row: row,
    detail: detail,
  );
}

Map<String, Color> _roleValues(ColorScheme s, EtPalette p) => {
  'primary': s.primary,
  'onPrimary': s.onPrimary,
  'primaryContainer': s.primaryContainer,
  'onPrimaryContainer': s.onPrimaryContainer,
  'secondary': s.secondary,
  'onSecondary': s.onSecondary,
  'secondaryContainer': s.secondaryContainer,
  'onSecondaryContainer': s.onSecondaryContainer,
  'tertiary': s.tertiary,
  'onTertiary': s.onTertiary,
  'tertiaryContainer': s.tertiaryContainer,
  'onTertiaryContainer': s.onTertiaryContainer,
  'error': s.error,
  'onError': s.onError,
  'errorContainer': s.errorContainer,
  'onErrorContainer': s.onErrorContainer,
  'surface': s.surface,
  'onSurface': s.onSurface,
  'surfaceContainerLowest': s.surfaceContainerLowest,
  'surfaceContainerLow': s.surfaceContainerLow,
  'surfaceContainer': s.surfaceContainer,
  'surfaceContainerHigh': s.surfaceContainerHigh,
  'surfaceContainerHighest': s.surfaceContainerHighest,
  'onSurfaceVariant': s.onSurfaceVariant,
  'outline': s.outline,
  'outlineVariant': s.outlineVariant,
  'inverseSurface': s.inverseSurface,
  'onInverseSurface': s.onInverseSurface,
  'scrim': s.scrim,
  // Custom M3 extension roles (Google's semantic green/amber per brightness).
  'success': p.success,
  'onSuccess': p.onSuccess,
  'successContainer': p.successContainer,
  'onSuccessContainer': p.onSuccessContainer,
  'warning': p.warning,
  'onWarning': p.onWarning,
  'warningContainer': p.warningContainer,
  'onWarningContainer': p.onWarningContainer,
};

/// WCAG 2.1 relative luminance from sRGB channels.
double _luminance(Color color) {
  double channel(double value) => value <= 0.03928
      ? value / 12.92
      : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

/// WCAG 2.1 contrast ratio (1:1 .. 21:1).
double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

String _hex(Color color) =>
    '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

String _pad(String value, int width) =>
    value.length >= width ? value : value.padRight(width);

String _signed(double value) =>
    '${value >= 0 ? '+' : ''}${value.toStringAsFixed(2)}';

/// Radius of an M3 shape, or -1 when the shape is not a rounded rectangle.
double _radiusOf(Object? shape) {
  if (shape is RoundedRectangleBorder) {
    return shape.borderRadius.resolve(TextDirection.ltr).topLeft.x;
  }
  if (shape is OutlineInputBorder) {
    return shape.borderRadius.resolve(TextDirection.ltr).topLeft.x;
  }
  if (shape is StadiumBorder) return 999;
  return -1;
}
