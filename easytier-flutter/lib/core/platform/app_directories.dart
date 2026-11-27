import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Host facts `dart:io` cannot discover on Android/iOS.
///
/// The core client persists network configurations in a directory it is handed
/// at boot. On desktop that is a well-known `$HOME`/`APPDATA` path; inside a
/// mobile sandbox `dart:io` has no API for the app's private directory, and the
/// previous temp-directory fallback was not reliably writable — which showed up
/// as an empty network list ("No networks yet") even after the user added a
/// network, because the add could not be persisted.
///
/// The Android host (`MainActivity`) answers `filesDir` on
/// [channelName], so the client can store configurations in app-private,
/// restart-surviving storage without pulling in a plugin dependency.
abstract final class AppDirectories {
  static const MethodChannel _channel = MethodChannel(
    'com.kkrainbow.easytier/app',
  );

  /// Directory for persisted network configurations, or `null` when the host
  /// does not expose one (desktop, web, unsupported platform). A `null` result
  /// lets [FfiCoreClient] keep its own desktop defaults.
  static Future<String?> configDirectory() async {
    if (kIsWeb) return null;
    if (!Platform.isAndroid && !Platform.isIOS) return null;
    // The engine may still be wiring the activity's channels when Dart starts;
    // a short bounded retry keeps first-launch configuration storage working
    // instead of silently falling back to an unwritable temp path.
    for (var attempt = 0; attempt < 5; attempt++) {
      final directory = await _filesDir();
      if (directory != null) {
        return '$directory${Platform.pathSeparator}easytier';
      }
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
    return null;
  }

  static Future<String?> _filesDir() async {
    try {
      final filesDir = await _channel.invokeMethod<String>('filesDir');
      if (filesDir == null || filesDir.trim().isEmpty) return null;
      return filesDir.trim();
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// App-private cache directory, used only for diagnostics.
  static Future<String?> cacheDirectory() async {
    if (kIsWeb || !Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>('cacheDir');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
