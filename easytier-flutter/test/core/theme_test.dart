import 'package:easytier_flutter/core/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Machine-checks the palette against WCAG thresholds. The design system makes
/// contrast claims; this test makes them non-negotiable.
double _contrast(Color a, Color b) {
  final l1 = a.computeLuminance();
  final l2 = b.computeLuminance();
  final hi = l1 > l2 ? l1 : l2;
  final lo = l1 > l2 ? l2 : l1;
  return (hi + 0.05) / (lo + 0.05);
}

void _expectPair(EtPalette p, Color fg, Color bg, double min, String label) {
  final ratio = _contrast(fg, bg);
  expect(ratio, greaterThanOrEqualTo(min), reason: '$label: ${ratio.toStringAsFixed(2)}:1');
}

void main() {
  for (final (name, p) in [('dark', EtPalette.forBrightness(Brightness.dark)), ('light', EtPalette.forBrightness(Brightness.light))]) {
    group('$name palette', () {
      test('body and secondary text keep 4.5:1 on both surfaces', () {
        for (final (label, bg) in [('bg', p.bg), ('surface1', p.surface1)]) {
          _expectPair(p, p.text, bg, 4.5, 'text on $label');
          _expectPair(p, p.text2, bg, 4.5, 'text2 on $label');
        }
      });

      test('tertiary text is still readable at 4.5:1', () {
        _expectPair(p, p.text3, p.bg, 4.5, 'text3 on bg');
        _expectPair(p, p.text3, p.surface1, 4.5, 'text3 on surface1');
      });

      test('semantic colours used as text meet 4.5:1', () {
        for (final (label, color) in [
          ('accent', p.accent),
          ('info', p.info),
          ('warn', p.warn),
          ('danger', p.danger),
          ('neutral', p.neutral),
        ]) {
          _expectPair(p, color, p.bg, 4.5, '$label on bg');
          _expectPair(p, color, p.surface1, 4.5, '$label on surface1');
        }
      });

      test('interactive control boundaries keep 3:1', () {
        _expectPair(p, p.controlBorder, p.surface1, 3.0, 'control border on surface1');
        _expectPair(p, p.controlBorder, p.surface2, 3.0, 'control border on surface2');
      });

      test('text on semantic fills meets 4.5:1', () {
        _expectPair(p, p.onAccent, p.accent, 4.5, 'onAccent/accent');
        _expectPair(p, p.accentOnTint, p.accentQuiet, 4.5, 'accent on tint');
        _expectPair(p, p.infoOnTint, p.infoQuiet, 4.5, 'info on tint');
        _expectPair(p, p.warnOnTint, p.warnQuiet, 4.5, 'warn on tint');
        _expectPair(p, p.dangerOnTint, p.dangerQuiet, 4.5, 'danger on tint');
      });

      test('focus ring is distinguishable from surfaces', () {
        _expectPair(p, p.focus, p.bg, 3.0, 'focus on bg');
      });

      test('M3 semantic pairs keep their role contrast', () {
        _expectPair(p, p.scheme.onPrimary, p.scheme.primary, 4.5, 'onPrimary/primary');
        _expectPair(
          p,
          p.scheme.onPrimaryContainer,
          p.scheme.primaryContainer,
          4.5,
          'onPrimaryContainer/primaryContainer',
        );
        _expectPair(p, p.scheme.onSecondaryContainer, p.scheme.secondaryContainer, 4.5,
            'onSecondaryContainer/secondaryContainer');
        _expectPair(p, p.scheme.onError, p.scheme.error, 4.5, 'onError/error');
        _expectPair(p, p.scheme.onErrorContainer, p.scheme.errorContainer, 4.5,
            'onErrorContainer/errorContainer');
        _expectPair(p, p.scheme.onTertiary, p.scheme.tertiary, 4.5, 'onTertiary/tertiary');
        _expectPair(p, p.scheme.outline, p.scheme.surface, 3.0, 'outline/surface');
      });

      test('success and warning role pairs keep 4.5:1', () {
        _expectPair(p, p.onSuccess, p.success, 4.5, 'onSuccess/success');
        _expectPair(p, p.onSuccessContainer, p.successContainer, 4.5,
            'onSuccessContainer/successContainer');
        _expectPair(p, p.onWarning, p.warning, 4.5, 'onWarning/warning');
        _expectPair(p, p.onWarningContainer, p.warningContainer, 4.5,
            'onWarningContainer/warningContainer');
        // Success/warning are also used as text on surfaces (peer latency,
        // banners); check the surface pairs too.
        for (final (name, color) in [('success', p.success), ('warning', p.warning)]) {
          _expectPair(p, color, p.scheme.surface, 4.5, '$name on surface');
          _expectPair(p, color, p.surface1, 4.5, '$name on surfaceContainerLow');
        }
      });
    });
  }
}
