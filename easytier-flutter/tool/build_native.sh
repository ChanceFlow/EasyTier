#!/usr/bin/env bash
# Build the `easytier-ffi` cdylib and stage it where the Flutter app loads it.
#
# Usage:
#   tool/build_native.sh              # host debug build -> build/native/
#   tool/build_native.sh --release    # host release build -> build/native/
#   tool/build_native.sh --android    # Android release build -> android/app/src/main/jniLibs/
#
# Environment notes:
#   * Rust:        export PATH="$HOME/.cargo/bin:$PATH"
#   * protoc:      `protoc` (or PROTOC=<path>) is required by easytier-proto.
#   * linker:      .cargo/config.toml uses `-fuse-ld=mold`; install mold, or
#                  provide a `mold` (and `ld.mold`) shim on PATH that delegates
#                  to GNU ld.
#   * Android:     cargo-ndk + ANDROID_NDK_HOME/ANDROID_NDK_ROOT are required.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLUTTER_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$FLUTTER_DIR/.." && pwd)"
PACKAGE="easytier-ffi"

MODE="host-debug"
for arg in "$@"; do
  case "$arg" in
    --release) MODE="host-release" ;;
    --android) MODE="android" ;;
    -h|--help)
      sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "unknown argument: $arg" >&2
      exit 2
      ;;
  esac
done

export PATH="${HOME}/.cargo/bin:${PATH}"

if ! command -v cargo >/dev/null 2>&1; then
  echo "error: cargo not found; add \$HOME/.cargo/bin to PATH" >&2
  exit 1
fi
if ! command -v protoc >/dev/null 2>&1 && [ -z "${PROTOC:-}" ]; then
  echo "warning: protoc not found; set PROTOC=/path/to/protoc (easytier-proto needs it)" >&2
fi

case "$MODE" in
  host-debug)
    PROFILE_DIR="debug"
    CARGO_ARGS=(build -p "$PACKAGE")
    ;;
  host-release)
    PROFILE_DIR="release"
    CARGO_ARGS=(build -p "$PACKAGE" --release)
    ;;
  android)
    if ! command -v cargo-ndk >/dev/null 2>&1; then
      echo "error: cargo-ndk not found; install with: cargo install cargo-ndk" >&2
      exit 1
    fi
    if [ -z "${ANDROID_NDK_HOME:-}" ] && [ -z "${ANDROID_NDK_ROOT:-}" ]; then
      echo "error: set ANDROID_NDK_HOME (or ANDROID_NDK_ROOT) to the NDK path" >&2
      exit 1
    fi
    JNI_DIR="$FLUTTER_DIR/android/app/src/main/jniLibs"
    mkdir -p "$JNI_DIR"
    echo "==> cargo ndk (4 ABIs) -> $JNI_DIR"
    # `cargo ndk -o` places each ABI's libeasytier_ffi.so in <out>/<abi>/.
    cargo ndk \
      -t arm64-v8a \
      -t armeabi-v7a \
      -t x86_64 \
      -t x86 \
      -o "$JNI_DIR" \
      build -p "$PACKAGE" --release
    echo
    echo "Staged for Android:"
    find "$JNI_DIR" -name 'libeasytier_ffi.so' -print
    echo
    echo "The Flutter loader opens the soname 'libeasytier_ffi.so', so no Dart"
    echo "path configuration is needed for Android as long as jniLibs is packaged."
    exit 0
    ;;
esac

echo "==> cargo ${CARGO_ARGS[*]}"
(cd "$REPO_ROOT" && cargo "${CARGO_ARGS[@]}")

HOST_TRIPLE="$(rustc -vV | sed -n 's/^host: //p')"
TARGET_DIR="${CARGO_TARGET_DIR:-$REPO_ROOT/target}/$PROFILE_DIR"

case "$HOST_TRIPLE" in
  *windows*) SOURCE="$TARGET_DIR/easytier_ffi.dll" ;;
  *darwin*) SOURCE="$TARGET_DIR/libeasytier_ffi.dylib" ;;
  *) SOURCE="$TARGET_DIR/libeasytier_ffi.so" ;;
esac

if [ ! -f "$SOURCE" ]; then
  echo "error: expected artifact not found: $SOURCE" >&2
  exit 1
fi

STAGE_DIR="$FLUTTER_DIR/build/native"
mkdir -p "$STAGE_DIR"
cp -f "$SOURCE" "$STAGE_DIR/"
echo
echo "Staged $(basename "$SOURCE") -> $STAGE_DIR"
echo "Run: bash /home/chance/Projects/.flutter-run.sh $FLUTTER_DIR run -d linux"
echo
echo "Desktop install paths for a bundled app:"
echo "  Linux:   next to the executable, or /usr/lib/easytier/libeasytier_ffi.so"
echo "  macOS:   inside .app/Contents/Frameworks/libeasytier_ffi.dylib"
echo "  Windows: next to the .exe (easytier_ffi.dll)"
echo "Alternatively point EASYTIER_FFI_LIB at the shared library."
