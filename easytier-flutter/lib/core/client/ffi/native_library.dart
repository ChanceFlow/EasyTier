import 'dart:ffi';
import 'dart:io';

import 'ffi_bindings.dart';

/// Raised when the native EasyTier library cannot be loaded or is missing
/// required ABI symbols.
class EasytierFfiLoadException implements Exception {
  EasytierFfiLoadException(this.message, this.attempts);

  final String message;

  /// One line per attempted library path and why it failed.
  final List<String> attempts;

  @override
  String toString() {
    final buffer = StringBuffer(message);
    if (attempts.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Attempted:');
      for (final attempt in attempts) {
        buffer.writeln('  - $attempt');
      }
      buffer.write(
        'Build the native library with tool/build_native.sh (desktop) or '
        'cargo ndk (Android) and copy it next to the app, or point '
        'EASYTIER_FFI_LIB at it.',
      );
    }
    return buffer.toString();
  }
}

/// Handle to a loaded `libeasytier_ffi` shared library.
///
/// The location is resolved per platform:
///  * Android: the packaged `libeasytier_ffi.so` (`jniLibs/<abi>/`), loaded by
///    its soname through the linker.
///  * Linux: `libeasytier_ffi.so`, macOS: `libeasytier_ffi.dylib`, Windows:
///    `easytier_ffi.dll` — searched next to the executable, in
///    `<cwd>/build/native/`, and on the normal library search path.
///  * iOS: static link, so the symbols come from `DynamicLibrary.process()`.
///
/// An explicit path can always be forced with [load]'s `overridePath` argument
/// or the `EASYTIER_FFI_LIB` environment variable.
final class EasytierFfi {
  EasytierFfi._(this.library, this.path) : bindings = EasytierFfiBindings(library);

  /// The opened dynamic library.
  final DynamicLibrary library;

  /// The path (or load hint) that succeeded, useful to reuse from a worker
  /// isolate. `null` when the process handle was used.
  final String? path;

  /// Resolved C ABI symbols.
  final EasytierFfiBindings bindings;

  /// Loads the native library, trying the platform default locations.
  ///
  /// Throws [EasytierFfiLoadException] with every attempted location when no
  /// candidate exposes the required symbols.
  static EasytierFfi load({String? overridePath}) {
    final attempts = <String>[];
    for (final candidate in _candidates(overridePath)) {
      try {
        final library = DynamicLibrary.open(candidate);
        final ffi = EasytierFfi._(library, candidate);
        // Touch a symbol that is only present in a compatible ABI build so an
        // incompatible library is reported as a load failure.
        ffi.bindings.parseConfig;
        return ffi;
      } on ArgumentError catch (error) {
        attempts.add('$candidate: ${error.message}');
      } on OSError catch (error) {
        attempts.add('$candidate: ${error.message}');
      }
    }

    // iOS links the Rust staticlib into the app binary, so there is no shared
    // object to open: the symbols already live in the process image.
    if (Platform.isIOS) {
      try {
        final library = DynamicLibrary.process();
        final ffi = EasytierFfi._(library, null);
        ffi.bindings.parseConfig;
        return ffi;
      } on ArgumentError catch (error) {
        attempts.add('process image: ${error.message}');
      }
    }

    throw EasytierFfiLoadException(
      'Could not load the EasyTier native library for '
      '${Platform.operatingSystem}.',
      attempts,
    );
  }

  static String get nativeLibraryFileName {
    if (Platform.isWindows) return 'easytier_ffi.dll';
    if (Platform.isMacOS) return 'libeasytier_ffi.dylib';
    return 'libeasytier_ffi.so';
  }

  static List<String> _candidates(String? overridePath) {
    final candidates = <String>[];
    void add(String? path) {
      if (path == null || path.isEmpty) return;
      if (!candidates.contains(path)) candidates.add(path);
    }

    add(overridePath);
    add(Platform.environment['EASYTIER_FFI_LIB']);

    final fileName = nativeLibraryFileName;

    // Next to the running executable (installed desktop app layout).
    try {
      final executableDir = File(Platform.resolvedExecutable).parent.path;
      final separator = Platform.pathSeparator;
      add('$executableDir$separator$fileName');
    } on FileSystemException {
      // resolvedExecutable is not always a real file (e.g. mobile sandboxes).
    }

    // `tool/build_native.sh` output used by `flutter run` on the host.
    final separator = Platform.pathSeparator;
    final workingDirectory = Directory.current.path;
    add('$workingDirectory${separator}build${separator}native$separator$fileName');

    // Linker search path: Android packages the .so next to the app libraries,
    // and desktop systems find it through LD_LIBRARY_PATH/DYLD_LIBRARY_PATH.
    add(fileName);

    return candidates;
  }
}
