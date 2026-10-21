import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

/// Material 3 tokens for the EasyTier client.
///
/// Colour is entirely derived from a single [ColorScheme] (`fromSeed`, Google
/// blue seed) so every role, state layer and tonal surface comes from the M3
/// spec. The only additions are the two semantic roles Material does not ship:
/// `success` (connected / alive) and `warning` (degraded), each with a container
/// pair so they can be used as M3 chips/banners.
///
/// Widgets read roles through this class — no raw `ColorScheme` reach-in, no
/// hex, no opacity hacks (except the M3 disabled 38% rule).
@immutable
class EtPalette extends ThemeExtension<EtPalette> {
  const EtPalette({
    required this.scheme,
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
  });

  final ColorScheme scheme;

  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;

  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color onWarningContainer;

  bool get isDark => scheme.brightness == Brightness.dark;

  // ---- M3 roles used by the UI kit, under the names the screens already use.
  Color get bg => scheme.surface;
  Color get surface1 => scheme.surfaceContainerLow;
  Color get surface2 => scheme.surfaceContainer;
  Color get surface3 => scheme.surfaceContainerHigh;
  Color get sunken => scheme.surfaceContainerLowest;

  Color get border => scheme.outlineVariant;
  Color get borderStrong => scheme.outline;
  Color get controlBorder => scheme.outline;
  Color get scrim => scheme.scrim;

  Color get text => scheme.onSurface;
  Color get text2 => scheme.onSurfaceVariant;
  Color get text3 => scheme.onSurfaceVariant;
  Color get textDisabled => scheme.onSurface.withValues(alpha: 0.38);

  Color get accent => scheme.primary;
  Color get onAccent => scheme.onPrimary;
  Color get accentQuiet => scheme.primaryContainer;
  Color get accentOnTint => scheme.onPrimaryContainer;

  Color get info => scheme.primary;
  Color get onInfo => scheme.onPrimary;
  Color get infoQuiet => scheme.secondaryContainer;
  Color get infoOnTint => scheme.onSecondaryContainer;

  Color get warn => warning;
  Color get onWarn => onWarning;
  Color get warnQuiet => warningContainer;
  Color get warnOnTint => onWarningContainer;

  Color get danger => scheme.error;
  Color get onDanger => scheme.onError;
  Color get dangerQuiet => scheme.errorContainer;
  Color get dangerOnTint => scheme.onErrorContainer;

  Color get neutral => scheme.onSurfaceVariant;
  Color get neutralQuiet => scheme.surfaceContainerHighest;

  Color get focus => scheme.primary;

  /// The Google blue seed used for the whole app.
  static const seed = Color(0xFF0B57D0);

  /// Builds the extension for a scheme. Success/warning are the only custom
  /// roles and they follow Google's own semantic greens/ambers per brightness.
  factory EtPalette.of(ColorScheme scheme) {
    if (scheme.brightness == Brightness.dark) {
      return EtPalette(
        scheme: scheme,
        success: const Color(0xFF81C995),
        onSuccess: const Color(0xFF00390F),
        successContainer: const Color(0xFF005322),
        onSuccessContainer: const Color(0xFFA6F4B6),
        warning: const Color(0xFFFFB95C),
        onWarning: const Color(0xFF4A2800),
        warningContainer: const Color(0xFF6A3B00),
        onWarningContainer: const Color(0xFFFFDDB3),
      );
    }
    return EtPalette(
      scheme: scheme,
      success: const Color(0xFF137333),
      onSuccess: Colors.white,
      successContainer: const Color(0xFFC4EED0),
      onSuccessContainer: const Color(0xFF072711),
      warning: const Color(0xFF8F4C00),
      onWarning: Colors.white,
      warningContainer: const Color(0xFFFFDDB3),
      onWarningContainer: const Color(0xFF2D1600),
    );
  }

  /// Convenience for tests and non-widget code.
  static EtPalette forBrightness(Brightness brightness) =>
      EtPalette.of(ColorScheme.fromSeed(seedColor: seed, brightness: brightness));

  @override
  EtPalette copyWith({ColorScheme? scheme}) => scheme == null
      ? this
      : EtPalette.of(scheme);

  @override
  EtPalette lerp(ThemeExtension<EtPalette>? other, double t) {
    // M3 colour roles are discrete; a half-way blend of two schemes is not a
    // defined colour. Theme switches land at the halfway point.
    if (other is! EtPalette) return this;
    return t < 0.5 ? this : other;
  }
}

/// 4-based spacing scale (M3 uses 4dp as the base unit).
abstract final class EtSpace {
  static const x1 = 4.0;
  static const x2 = 8.0;
  static const x3 = 12.0;
  static const x4 = 16.0;
  static const x5 = 20.0;
  static const x6 = 24.0;
  static const x8 = 32.0;
  static const x10 = 40.0;
  static const x12 = 48.0;
  static const x16 = 64.0;

  static double gutter(double width) => width >= 900 ? x6 : x4;

  static const maxContentWidth = 1040.0;
}

/// M3 shape scale.
abstract final class EtRadius {
  static const xs = 4.0; // extra small
  static const sm = 8.0; // small
  static const md = 12.0; // medium (M3 card/inputs baseline)
  static const lg = 16.0; // large
  static const xl = 28.0; // extra large
  static const card = 24.0; // expressive card surface
  static const hero = 32.0; // expressive hero surfaces
  static const pill = 999.0;
}

/// M3 motion tokens. Durations come from the short/medium tiers; easing from
/// the emphasized family for navigation and state changes.
/// Fixed expressive accent colours for decorative surfaces (the Home aura,
/// connection orb glow, avatar tints). These are not UI control roles — controls
/// always use `ColorScheme` — but M3 Expressive allows vivid brand accents in
/// large decorative surfaces. AA text contrast is still measured against the
/// calm tonal layer the text actually sits on.
abstract final class EtAccent {
  static const blue = Color(0xFF3D7BFF);
  static const violet = Color(0xFF8B5CF6);
  static const mint = Color(0xFF25E0B0);
  static const cyan = Color(0xFF22D3EE);

  static Color byIndex(int index) => switch (index % 4) {
    0 => blue,
    1 => violet,
    2 => mint,
    _ => cyan,
  };
}

/// Expressive gradients. They are decorative backgrounds only: text and actions
/// always sit on a solid tonal surface above them (contrast is measured against
/// that surface, never against the gradient).
abstract final class EtGradient {
  /// The Home hero aura: primary -> tertiary -> success, low frequency.
  static LinearGradient hero(EtPalette p) => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      // Kept low enough that onSurface text on the hero clears 4.5:1 without
      // a scrim; the aura is atmosphere, not a colour surface.
      Color.alphaBlend(p.scheme.primary.withValues(alpha: 0.30), p.scheme.surfaceContainerHigh),
      Color.alphaBlend(p.scheme.tertiary.withValues(alpha: 0.22), p.scheme.surfaceContainerHigh),
      Color.alphaBlend(p.success.withValues(alpha: 0.14), p.scheme.surfaceContainerHigh),
    ],
    stops: const [0.0, 0.55, 1.0],
  );

  /// A quieter version for secondary headers/banners.
  static LinearGradient surfaceGlow(EtPalette p) => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color.alphaBlend(p.scheme.primary.withValues(alpha: 0.16), p.scheme.surfaceContainerLow),
      p.scheme.surfaceContainerLow,
    ],
  );
}

abstract final class EtDuration {
  static const instant = Duration(milliseconds: 100); // short2
  static const fast = Duration(milliseconds: 150); // short3
  static const base = Duration(milliseconds: 200); // short4
  static const slow = Duration(milliseconds: 300); // medium2

  /// One-shot entrance for page-transition / hero choreography (kept below
  /// 320ms so a single golden capture always sees the settled state).
  static const hero = Duration(milliseconds: 280);

  /// Delay between sibling entrance steps (badge → orb → text → action).
  static const stagger = Duration(milliseconds: 36);

  static const loopSpin = Duration(milliseconds: 700);
  static const loopSweep = Duration(milliseconds: 900);
  static const loopShimmer = Duration(milliseconds: 1400);
  static const loopBreathe = Duration(milliseconds: 1400);
  static const loopPulse = Duration(milliseconds: 1400);
  static const loopRing = Duration(milliseconds: 2000);
}

abstract final class EtCurves {
  static const standard = Cubic(0.2, 0.0, 0.0, 1.0);
  static const enter = Cubic(0.05, 0.7, 0.1, 1.0); // M3 emphasized decelerate
  static const exit = Cubic(0.3, 0.0, 0.8, 0.15); // M3 emphasized accelerate
  static const hover = Cubic(0.2, 0.0, 0.0, 1.0);

  /// M3 Expressive spring: slight overshoot (spring damping < 1), used for
  /// state changes and hero moments. Never used on dense data rows.
  static const spring = Cubic(0.34, 1.56, 0.64, 1.0);
}

/// M3 type scale (material_2021) plus the product's two display sizes.
abstract final class EtType {
  static const micro = 11.0; // labelSmall
  static const caption = 12.0; // bodySmall
  static const bodySm = 14.0; // bodyMedium
  static const body = 16.0; // bodyLarge
  static const title = 16.0; // titleMedium
  static const headline = 22.0; // titleLarge
  static const display = 28.0; // headlineMedium
  static const hero = 36.0; // displaySmall
  /// M3 Expressive emphasized display: the one hero number on Home.
  static const expressive = 45.0; // displayMedium
}

/// Text builders.
///
/// The app ships **no text fonts**: UI text uses the platform's system UI font
/// (Roboto on Android, SF on Apple platforms, Segoe UI on Windows, the
/// system-ui default on Linux), so the client follows the user's system
/// typography. Machine data (IPs, latency, rates, ids) uses the platform
/// monospace family so columns still align. Missing CJK glyphs fall back to
/// the platform's CJK faces via [uiFallback] (also system fonts).
abstract final class EtText {
  /// System CJK fallbacks, by family name the platform actually ships.
  static const uiFallback = <String>[
    'Noto Sans CJK SC',
    'Noto Sans SC',
    'PingFang SC',
    'Hiragino Sans GB',
    'Microsoft YaHei',
    'WenQuanYi Micro Hei',
  ];

  /// Platform monospace family for machine data (a system font on every
  /// target; there is no bundled mono face).
  static String get monoFamily => switch (defaultTargetPlatform) {
    TargetPlatform.iOS || TargetPlatform.macOS => 'Menlo',
    TargetPlatform.windows => 'Consolas',
    _ => 'monospace',
  };

  static TextStyle ui({
    double size = EtType.body,
    FontWeight weight = FontWeight.w400,
    Color? color,
    double? height,
    double? letterSpacing,
  }) => TextStyle(
    // No fontFamily: inherit the platform/system UI font from the theme.
    fontFamilyFallback: uiFallback,
    fontSize: size,
    fontWeight: weight,
    color: color,
    // M3 line-heights shrink as type gets larger (body 16/24, title 22/28,
    // display 36/44); tabular figures are only for machine data, not UI copy.
    height: height ?? (size >= EtType.headline ? 1.27 : 1.5),
    letterSpacing: letterSpacing,
  );

  static TextStyle mono({
    double size = EtType.bodySm,
    FontWeight weight = FontWeight.w400,
    Color? color,
    double? height = 1.5,
    double? letterSpacing,
  }) => TextStyle(
    fontFamily: monoFamily,
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: height,
    letterSpacing: letterSpacing,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}
