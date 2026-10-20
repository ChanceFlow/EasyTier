/// Dart bindings for the C ABI exposed by `easytier-contrib/easytier-ffi`.
///
/// Only `dart:ffi` and `dart:convert` are used: the Flutter app does not depend
/// on `package:ffi`, so string/struct helpers are implemented here.
///
/// ABI contract (keep in sync with `easytier-ffi/src/lib.rs`):
///  * C strings are null-terminated UTF-8. Strings returned by the library are
///    freed with [freeString]; input strings are malloc'd here and released by
///    [freeCString].
///  * `KeyValuePair` mirrors `#[repr(C)] struct KeyValuePair { *const c_char }`.
///  * Errors are reported as a negative `Int32` status; call [takeLastError] on
///    the same thread that received the failure.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';


// ===== C structs =====

/// Mirrors `easytier_ffi::KeyValuePair` (`#[repr(C)]`, two pointers).
final class KeyValuePair extends Struct {
  external Pointer<Char> key;
  external Pointer<Char> value;
}

// ===== Symbol typedefs =====

// `parse_config(const char*) -> int`
typedef ParseConfigNative = Int32 Function(Pointer<Char> config);
typedef ParseConfigDart = int Function(Pointer<Char> config);

// `run_network_instance(const char*) -> int`
typedef RunNetworkInstanceNative = Int32 Function(Pointer<Char> config);
typedef RunNetworkInstanceDart = int Function(Pointer<Char> config);

// `delete_network_instance(const char* const*, usize) -> int`
typedef DeleteNetworkInstanceNative = Int32 Function(
  Pointer<Pointer<Char>> instanceNames,
  Size length,
);
typedef DeleteNetworkInstanceDart = int Function(
  Pointer<Pointer<Char>> instanceNames,
  int length,
);

// `retain_network_instance(const char* const*, usize) -> int`
typedef RetainNetworkInstanceNative = Int32 Function(
  Pointer<Pointer<Char>> instanceNames,
  Size length,
);
typedef RetainNetworkInstanceDart = int Function(
  Pointer<Pointer<Char>> instanceNames,
  int length,
);

// `list_instance(KeyValuePair*, usize) -> int`
typedef ListInstanceNative = Int32 Function(
  Pointer<KeyValuePair> infos,
  Size maxLength,
);
typedef ListInstanceDart = int Function(
  Pointer<KeyValuePair> infos,
  int maxLength,
);

// `collect_network_infos(KeyValuePair*, usize) -> int`
typedef CollectNetworkInfosNative = Int32 Function(
  Pointer<KeyValuePair> infos,
  Size maxLength,
);
typedef CollectNetworkInfosDart = int Function(
  Pointer<KeyValuePair> infos,
  int maxLength,
);

// `set_tun_fd(const char*, int) -> int`
typedef SetTunFdNative = Int32 Function(Pointer<Char> instanceName, Int32 fd);
typedef SetTunFdDart = int Function(Pointer<Char> instanceName, int fd);

// `call_json_rpc(const char*, const char*, const char*, const char*, const char**) -> int`
typedef CallJsonRpcNative = Int32 Function(
  Pointer<Char> serviceName,
  Pointer<Char> methodName,
  Pointer<Char> domainName,
  Pointer<Char> payloadJson,
  Pointer<Pointer<Char>> outResponseJson,
);
typedef CallJsonRpcDart = int Function(
  Pointer<Char> serviceName,
  Pointer<Char> methodName,
  Pointer<Char> domainName,
  Pointer<Char> payloadJson,
  Pointer<Pointer<Char>> outResponseJson,
);

// `get_error_msg(const char**) -> void`
typedef GetErrorMsgNative = Void Function(Pointer<Pointer<Char>> out);
typedef GetErrorMsgDart = void Function(Pointer<Pointer<Char>> out);

// `get_version(const char**) -> void`
typedef GetVersionNative = Void Function(Pointer<Pointer<Char>> out);
typedef GetVersionDart = void Function(Pointer<Pointer<Char>> out);

// `free_string(const char*) -> void`
typedef FreeStringNative = Void Function(Pointer<Char> value);
typedef FreeStringDart = void Function(Pointer<Char> value);

// Instance event callback: `void (*)(const char* json, void* user_data)`.
typedef InstanceEventNative = Void Function(Pointer<Char> json, Pointer<Void> userData);
typedef InstanceEventDart = void Function(Pointer<Char> json, Pointer<Void> userData);

// `set_instance_event_callback(callback, void*) -> int`
typedef SetInstanceEventCallbackNative = Int32 Function(
  Pointer<NativeFunction<InstanceEventNative>> callback,
  Pointer<Void> userData,
);
typedef SetInstanceEventCallbackDart = int Function(
  Pointer<NativeFunction<InstanceEventNative>> callback,
  Pointer<Void> userData,
);

// `clear_instance_event_callback() -> int`
typedef ClearInstanceEventCallbackNative = Int32 Function();
typedef ClearInstanceEventCallbackDart = int Function();

// ===== Bindings =====

/// Resolved handles for every `easytier-ffi` symbol the Dart client uses.
///
/// Constructing this class fails with an [ArgumentError] when the library does
/// not export one of the symbols (for example because an older build was
/// loaded), which [EasytierFfi.load] reports as a load failure.
final class EasytierFfiBindings {
  EasytierFfiBindings(DynamicLibrary library)
    : parseConfig = library.lookupFunction<ParseConfigNative, ParseConfigDart>(
        'parse_config',
      ),
      runNetworkInstance = library
          .lookupFunction<RunNetworkInstanceNative, RunNetworkInstanceDart>(
            'run_network_instance',
          ),
      deleteNetworkInstance = library
          .lookupFunction<DeleteNetworkInstanceNative, DeleteNetworkInstanceDart>(
            'delete_network_instance',
          ),
      retainNetworkInstance = library
          .lookupFunction<RetainNetworkInstanceNative, RetainNetworkInstanceDart>(
            'retain_network_instance',
          ),
      listInstance = library
          .lookupFunction<ListInstanceNative, ListInstanceDart>('list_instance'),
      collectNetworkInfos = library
          .lookupFunction<CollectNetworkInfosNative, CollectNetworkInfosDart>(
            'collect_network_infos',
          ),
      setTunFd = library.lookupFunction<SetTunFdNative, SetTunFdDart>(
        'set_tun_fd',
      ),
      callJsonRpc = library.lookupFunction<CallJsonRpcNative, CallJsonRpcDart>(
        'call_json_rpc',
      ),
      getErrorMsg = library.lookupFunction<GetErrorMsgNative, GetErrorMsgDart>(
        'get_error_msg',
      ),
      getVersion = library.lookupFunction<GetVersionNative, GetVersionDart>(
        'get_version',
      ),
      freeString = library.lookupFunction<FreeStringNative, FreeStringDart>(
        'free_string',
      ),
      setInstanceEventCallback = library
          .lookupFunction<
            SetInstanceEventCallbackNative,
            SetInstanceEventCallbackDart
          >('set_instance_event_callback'),
      clearInstanceEventCallback = library
          .lookupFunction<
            ClearInstanceEventCallbackNative,
            ClearInstanceEventCallbackDart
          >('clear_instance_event_callback');

  final ParseConfigDart parseConfig;
  final RunNetworkInstanceDart runNetworkInstance;
  final DeleteNetworkInstanceDart deleteNetworkInstance;
  final RetainNetworkInstanceDart retainNetworkInstance;
  final ListInstanceDart listInstance;
  final CollectNetworkInfosDart collectNetworkInfos;
  final SetTunFdDart setTunFd;
  final CallJsonRpcDart callJsonRpc;
  final GetErrorMsgDart getErrorMsg;
  final GetVersionDart getVersion;
  final FreeStringDart freeString;
  final SetInstanceEventCallbackDart setInstanceEventCallback;
  final ClearInstanceEventCallbackDart clearInstanceEventCallback;

  // ===== String helpers =====

  /// Copies a null-terminated UTF-8 C string into a Dart string.
  ///
  /// Returns an empty string for a null pointer. Malformed UTF-8 is replaced
  /// instead of throwing because event payloads must never crash the app.
  String copyCString(Pointer<Char> pointer) {
    if (pointer == nullptr) return '';
    final bytes = pointer.cast<Uint8>();
    var length = 0;
    while (bytes[length] != 0) {
      length++;
    }
    return utf8.decode(bytes.asTypedList(length), allowMalformed: true);
  }

  /// Allocates a null-terminated UTF-8 C string on the native heap.
  ///
  /// Release it with [freeCString].
  Pointer<Char> allocateCString(String value) {
    final encoded = utf8.encode(value);
    final pointer = _LibcAllocator.instance.allocate(encoded.length + 1);
    final bytes = pointer.asTypedList(encoded.length + 1);
    bytes.setRange(0, encoded.length, encoded);
    bytes[encoded.length] = 0;
    return pointer.cast<Char>();
  }

  /// Releases a string allocated by [allocateCString].
  void freeCString(Pointer<Char> pointer) {
    if (pointer == nullptr) return;
    _LibcAllocator.instance.free(pointer.cast<Uint8>());
  }

  /// Releases a string returned by the native library via [freeString].
  void freeReturnedString(Pointer<Char> pointer) => freeString(pointer);

  /// Allocates `count` zero-filled [KeyValuePair] slots for the `*_instance`
  /// output APIs. Release with [freeNative].
  Pointer<KeyValuePair> allocateKeyValuePairs(int count) {
    final byteCount = count * sizeOf<KeyValuePair>();
    final pointer = _LibcAllocator.instance.allocate(byteCount);
    pointer.asTypedList(byteCount).fillRange(0, byteCount, 0);
    return pointer.cast<KeyValuePair>();
  }

  /// Allocates storage for one C string/pointer output parameter.
  Pointer<Pointer<Char>> allocatePointerSlot() {
    final byteCount = sizeOf<Pointer<Char>>();
    final pointer = _LibcAllocator.instance.allocate(byteCount);
    pointer.asTypedList(byteCount).fillRange(0, byteCount, 0);
    return pointer.cast<Pointer<Char>>();
  }

  /// Allocates a zero-filled array of `count` C string pointers (for the
  /// `*_network_instance` name-array parameters). Release with [freeNative].
  Pointer<Pointer<Char>> allocateCStringPointerArray(int count) {
    final slots = count == 0 ? 1 : count;
    final byteCount = slots * sizeOf<Pointer<Char>>();
    final pointer = _LibcAllocator.instance.allocate(byteCount);
    pointer.asTypedList(byteCount).fillRange(0, byteCount, 0);
    return pointer.cast<Pointer<Char>>();
  }

  /// Releases memory allocated by any `allocate*` helper above.
  void freeNative(Pointer<NativeType> pointer) {
    if (pointer == nullptr) return;
    _LibcAllocator.instance.free(pointer.cast<Uint8>());
  }

  // ===== Error / version helpers =====

  /// Reads and clears the thread-local native error message.
  ///
  /// Must be called on the same thread that observed a negative status.
  String? takeLastError() {
    final slot = allocatePointerSlot();
    try {
      getErrorMsg(slot);
      final message = slot.value;
      if (message == nullptr) return null;
      final text = copyCString(message);
      freeString(message);
      return text.isEmpty ? null : text;
    } finally {
      freeNative(slot);
    }
  }

  /// Returns the linked EasyTier core version string.
  String readVersion() {
    final slot = allocatePointerSlot();
    try {
      getVersion(slot);
      final version = slot.value;
      if (version == nullptr) return 'unknown';
      final text = copyCString(version);
      freeString(version);
      return text;
    } finally {
      freeNative(slot);
    }
  }
}

/// Minimal libc allocator used for FFI input buffers.
///
/// The native library frees its own returned strings through `free_string`, so
/// this allocator only ever releases memory it allocated itself.
final class _LibcAllocator {
  _LibcAllocator._(DynamicLibrary library)
    : _malloc = library.lookupFunction<
        Pointer<Uint8> Function(Size),
        Pointer<Uint8> Function(int)
      >('malloc'),
      _free = library.lookupFunction<
        Void Function(Pointer<Uint8>),
        void Function(Pointer<Uint8>)
      >('free');

  static final _LibcAllocator instance = _LibcAllocator._(_openLibc());

  final Pointer<Uint8> Function(int bytes) _malloc;
  final void Function(Pointer<Uint8> pointer) _free;

  /// Opens a library that exports the C runtime's `malloc`/`free`.
  ///
  /// The process image resolves libc on Linux/macOS/iOS/Android because those
  /// symbols are in the global namespace. Windows needs an explicit CRT DLL;
  /// `ucrtbase.dll` ships with Windows 10+, `msvcrt.dll` is the legacy
  /// fallback. Each candidate is probed so a partially stripped image cannot
  /// fail lazily on the first allocation.
  static DynamicLibrary _openLibc() {
    final errors = <String>[];
    final candidates = <String>[];
    if (Platform.isWindows) {
      candidates.addAll(const ['ucrtbase.dll', 'msvcrt.dll']);
    } else {
      candidates.addAll(const [
        '<process>',
        'libc.so.6',
        'libc.so',
        '/usr/lib/libSystem.B.dylib',
      ]);
    }

    for (final name in candidates) {
      try {
        final library = name == '<process>'
            ? DynamicLibrary.process()
            : DynamicLibrary.open(name);
        library.lookupFunction<
          Pointer<Uint8> Function(Size),
          Pointer<Uint8> Function(int)
        >('malloc');
        library.lookupFunction<
          Void Function(Pointer<Uint8>),
          void Function(Pointer<Uint8>)
        >('free');
        return library;
      } on Object catch (error) {
        errors.add('$name: $error');
      }
    }
    throw StateError(
      'Could not resolve malloc/free for FFI string allocation '
      '(${errors.join('; ')}).',
    );
  }

  Pointer<Uint8> allocate(int byteCount) {
    final pointer = _malloc(byteCount);
    if (pointer == nullptr) {
      throw StateError(
        'Failed to allocate $byteCount bytes on the native heap.',
      );
    }
    return pointer;
  }

  void free(Pointer<Uint8> pointer) => _free(pointer);
}
