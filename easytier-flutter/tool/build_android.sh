#!/usr/bin/env bash
# Build the Flutter Android APK with the real Rust core (easytier-ffi) bundled.
#
# The APK needs the easytier-ffi cdylib per ABI in android/app/src/main/jniLibs/
# and the Dart side compiled with EASYTIER_USE_FFI=true; without both the app
# falls back to MockCoreClient (UI preview only, no tunnel).
#
# Prereqs:
#   * rustup target: aarch64-linux-android
#   * Android NDK r28 (set ANDROID_NDK_HOME, e.g. $ANDROID_HOME/ndk/28.2.13676358)
#   * protoc on PATH (or PROTOC=...)
#   * libclang for bindgen (kcp-sys); LIBCLANG_PATH if not auto-discovered
#   * Flutter wrapper: bash /home/chance/Projects/.flutter-run.sh <dir> ...
#
# Usage:
#   tool/build_android.sh                 # arm64-v8a debug-signed release APK
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(cd "$APP_DIR/.." && pwd)"
NDK="${ANDROID_NDK_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}/ndk/28.2.13676358}"
FLUTTER_RUN="${FLUTTER_RUN:-/home/chance/Projects/.flutter-run.sh}"
ABI="arm64-v8a"
TARGET="aarch64-linux-android"
TRIPLE="aarch64-linux-android"
CLANG_ABI="aarch64-linux-android24"

TC="$NDK/toolchains/llvm/prebuilt/linux-x86_64"
[[ -x "$TC/bin/$CLANG_ABI-clang" ]] || {
  echo "error: NDK clang not found under $TC (set ANDROID_NDK_HOME)" >&2; exit 2; }

export PATH="$HOME/.cargo/bin:$PATH"
export CC_aarch64_linux_android="$TC/bin/$CLANG_ABI-clang"
export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$TC/bin/$CLANG_ABI-clang"
export AR_aarch64_linux_android="$TC/bin/llvm-ar"
export BINDGEN_EXTRA_CLANG_ARGS="--sysroot=$TC/sysroot --target=$CLANG_ABI -I$TC/lib/clang/19/include"
export PROTOC="${PROTOC:-protoc}"

echo "==> building easytier-ffi for $TARGET"
(cd "$REPO_DIR" && cargo build --release -p easytier-ffi --target "$TARGET")

JNI_DIR="$APP_DIR/android/app/src/main/jniLibs/$ABI"
mkdir -p "$JNI_DIR"
cp "$REPO_DIR/target/$TRIPLE/release/libeasytier_ffi.so" "$JNI_DIR/"

echo "==> building Flutter APK (arm64-v8a, FFI transport)"
"$FLUTTER_RUN" "$APP_DIR" build apk --release \
  --target-platform android-arm64 \
  --dart-define=EASYTIER_USE_FFI=true

echo "==> done: $APP_DIR/build/app/outputs/flutter-apk/app-release.apk"
