import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Material 3 apps are edge-to-edge: transparent system bars, icon brightness
/// following the themed surface. Without this the Android chrome keeps default
/// colours and the app stops looking like a Google app.
SystemUiOverlayStyle etSystemUiOverlayStyle(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
    statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
    systemNavigationBarContrastEnforced: false,
    systemStatusBarContrastEnforced: false,
  );
}

/// Enables edge-to-edge once at startup.
void enableEtEdgeToEdge() {
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
}
