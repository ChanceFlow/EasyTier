import 'package:flutter/material.dart';

import 'tokens.dart';

export 'tokens.dart';

/// Builds the Material 3 theme.
///
/// The whole visual language is Google's: `ColorScheme.fromSeed` (Google blue),
/// Material 3 typography (Roboto), M3 component defaults (buttons, cards, nav
/// bar/rail, text fields, dialogs, sheets), M3 shape and elevation tokens.
/// Themed overrides are intentionally minimal — only brand identity (app bar
/// behaviour, snackbar placement) and compact density on wide screens.
ThemeData buildEtTheme({required Brightness brightness, bool compact = false}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: EtPalette.seed,
    brightness: brightness,
  );
  final palette = EtPalette.of(scheme);
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
  );

  final textTheme = base.textTheme
      .apply(fontFamilyFallback: EtText.uiFallback)
      .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);

  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    canvasColor: scheme.surface,
    textTheme: textTheme,
    extensions: [palette],
    visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: scheme.surfaceTint,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 3,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge?.copyWith(color: scheme.onSurface),
    ),
    cardTheme: CardThemeData(
      elevation: 1,
      surfaceTintColor: scheme.surfaceTint,
      color: scheme.surfaceContainerLow,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(EtRadius.card)),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1, space: 1),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.primaryContainer,
      selectedIconTheme: IconThemeData(color: scheme.onPrimaryContainer),
      unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      selectedLabelTextStyle: textTheme.labelMedium?.copyWith(
        color: scheme.onSurface,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelTextStyle: textTheme.labelMedium?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 76,
      elevation: 0,
      backgroundColor: scheme.surfaceContainer,
      indicatorColor: scheme.primaryContainer,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? scheme.onPrimaryContainer
              : scheme.onSurfaceVariant,
        ),
      ),
      indicatorShape: const StadiumBorder(),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => textTheme.labelMedium?.copyWith(
          color: states.contains(WidgetState.selected)
              ? scheme.onSurface
              : scheme.onSurfaceVariant,
          fontWeight: states.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(EtRadius.xs)),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(EtRadius.xl)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(EtRadius.xl)),
      ),
    ),
    // Input fields: M3 outlined variant (Google's settings/product forms).
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(EtRadius.xs)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(EtRadius.xs),
        borderSide: BorderSide(color: scheme.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(EtRadius.xs),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
    ),
  );
}

/// Convenience accessors used by every widget.
extension EtThemeContext on BuildContext {
  EtPalette get et => Theme.of(this).extension<EtPalette>() ?? EtPalette.forBrightness(Theme.of(this).brightness);

  TextTheme get etText => Theme.of(this).textTheme;

  ColorScheme get etScheme => Theme.of(this).colorScheme;

  /// M3 window size classes: compact <600, medium 600-839, expanded >=840.
  /// Medium and larger use the navigation rail; expanded gets two-pane layouts.
  bool get etUseRail => MediaQuery.sizeOf(this).width >= 600;

  bool get etDesktop => MediaQuery.sizeOf(this).width >= 840;

  bool get etReducedMotion =>
      MediaQuery.maybeDisableAnimationsOf(this) ??
      (WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations);
}
