# Prebaked EasyTier builder image for the local act_runner.
#
# Registered as the runner label `easytier-builder` so Gitea Actions jobs
# run on a fully provisioned toolchain. The generic runner-images image
# lacks binutils/ld, mold (required by .cargo/config.toml rustflags),
# lld, cmake, protoc and the google well-known protos; installing those
# and a rust toolchain per job is slow and network-dependent. Everything
# is baked at image build time on the host where egress is reliable.
#
# Release matrix coverage (built with cargo-zigbuild, zig as linker):
#   linux musl  : x86_64 aarch64 riscv64gc loongarch64 armv7hf armv7 armhf arm
#   freebsd     : x86_64
#   windows-gnu : x86_64 i686 aarch64
#   mips/mipsel : musl-cross gcc + -Z build-std (see /opt/musl_gcc)
#   wasm32      : easytier-core -> wasm for the web config-generator
#
# No addresses or secrets are committed: the optional egress proxy and
# the NO_PROXY list are build ARGs supplied at build time by
# docker/build-image.sh (see its header comment).
FROM docker.gitea.com/runner-images:ubuntu-24.04

ARG http_proxy=
ARG https_proxy=
ARG all_proxy=
ARG no_proxy=gitea,localhost,127.0.0.1,::1,act_runner
ENV HTTP_PROXY=$http_proxy \
    HTTPS_PROXY=$https_proxy \
    ALL_PROXY=$all_proxy \
    NO_PROXY=$no_proxy \
    http_proxy=$http_proxy \
    https_proxy=$https_proxy \
    all_proxy=$all_proxy \
    no_proxy=$no_proxy \
    # cargo/rustup land here and must be on PATH for every job shell
    # (act runs job shells with --noprofile --norc, so PATH must come
    # from the image environment)
    PATH="/root/.cargo/bin:${PATH}"

# System build dependencies (GitHub's ubuntu-latest ships these; the
# gitea runner-images image does not). clang/libclang are needed by
# bindgen (kcp-sys build script); LIBCLANG_PATH points bindgen at it.
# gcc-mingw-w64-* are the x86_64/i686 Windows GNU cross compilers: they
# make windivert-sys take its gnu.rs path (cc-rs is_like_gnu() is true
# only for a real gcc-family cc, NOT for cargo-zigbuild's zigcc wrapper,
# which therefore wrongly falls into the MSVC flags path).
RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends \
      build-essential cmake pkg-config mold lld protobuf-compiler unzip \
      clang libclang-dev libssl-dev xz-utils \
      gcc-mingw-w64-x86-64 gcc-mingw-w64-i686 \
 && rm -rf /var/lib/apt/lists/* \
 && test -f /usr/lib/llvm-18/lib/libclang.so

ENV LIBCLANG_PATH=/usr/lib/llvm-18/lib

# Google well-known protos for prost-wkt-types (duration, timestamp, ...).
# Ubuntu's protobuf-compiler ships protoc but not the includes; fetch them
# from the matching protoc release zip (only the include files).
RUN curl -fsSL -o /tmp/protoc-wkt.zip \
      https://github.com/protocolbuffers/protobuf/releases/download/v25.4/protoc-25.4-linux-x86_64.zip \
 && unzip -oq /tmp/protoc-wkt.zip 'include/*' -d /usr \
 && rm -f /tmp/protoc-wkt.zip \
 && test -f /usr/include/google/protobuf/duration.proto

# Rustup with the pinned channel 1.95 (see rust-toolchain.toml).
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal \
 && rustup toolchain install 1.95 --profile minimal --no-self-update \
 && rustup default 1.95 \
 && rustc --version \
 && cargo --version

# Node.js 22 + pnpm 10 for the web frontend (vite) and wasm tooling.
ARG NODE_VERSION=22.16.0
RUN curl -fsSL -o /tmp/node.tar.xz \
      "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" \
 && mkdir -p /opt/node \
 && tar -xJf /tmp/node.tar.xz -C /opt/node --strip-components=1 \
 && ln -sf /opt/node/bin/node /usr/local/bin/node \
 && ln -sf /opt/node/bin/npm /usr/local/bin/npm \
 && ln -sf /opt/node/bin/npx /usr/local/bin/npx \
 && rm -f /tmp/node.tar.xz \
 && corepack enable \
 && corepack prepare pnpm@10 --activate \
 && ln -sf /opt/node/bin/pnpm /usr/local/bin/pnpm \
 && node --version && pnpm --version

# wasm-pack + wasm-bindgen-cli: builds easytier-core to wasm for the web
# config-generator. wasm-bindgen-cli version matches Cargo.lock.
ARG WASM_PACK_VERSION=0.13.1
RUN curl -fsSL -o /tmp/wasm-pack.tgz \
      "https://github.com/rustwasm/wasm-pack/releases/download/v${WASM_PACK_VERSION}/wasm-pack-v${WASM_PACK_VERSION}-x86_64-unknown-linux-musl.tar.gz" \
 && tar -xzf /tmp/wasm-pack.tgz -C /usr/local/bin --strip-components=1 \
 && rm -f /tmp/wasm-pack.tgz \
 && cargo install wasm-bindgen-cli --version 0.2.118 --locked --root /usr/local \
 && rustup target add wasm32-unknown-unknown \
 && wasm-pack --version

# Cross-compile linker/cc: zig 0.16.0 + cargo-zigbuild.
ARG ZIG_VERSION=0.16.0
RUN curl -fsSL -o /tmp/zig.tar.xz \
      "https://ziglang.org/download/${ZIG_VERSION}/zig-x86_64-linux-${ZIG_VERSION}.tar.xz" \
 && mkdir -p /opt/zig \
 && tar -xJf /tmp/zig.tar.xz -C /opt/zig --strip-components=1 \
 && ln -sf /opt/zig/zig /usr/local/bin/zig \
 && cargo install cargo-zigbuild --locked \
 && rm -f /tmp/zig.tar.xz \
 && zig version && cargo-zigbuild --version

# Rust std for every release target (musl/freebsd/windows-gnu) + rust-src
# (needed by cargo-zigbuild and the -Z build-std mips path).
# aarch64-pc-windows-gnu has no prebuilt std on 1.95; the workflow builds
# it with -Z build-std instead, so it is not listed here.
# darwin targets are linked with zig plus the bundled macOS SDK tbds in
# /opt/macos-sdk (see below); android targets are compiled with the NDK
# clang toolchain in /opt/ndk (see below), since zig provides no bionic.
RUN rustup target add \
      x86_64-unknown-linux-musl \
      aarch64-unknown-linux-musl \
      riscv64gc-unknown-linux-musl \
      loongarch64-unknown-linux-musl \
      armv7-unknown-linux-musleabihf \
      armv7-unknown-linux-musleabi \
      arm-unknown-linux-musleabihf \
      arm-unknown-linux-musleabi \
      x86_64-unknown-freebsd \
      x86_64-pc-windows-gnu \
      i686-pc-windows-gnu \
      x86_64-apple-darwin \
      aarch64-apple-darwin \
      aarch64-linux-android \
      armv7-linux-androideabi \
      i686-linux-android \
      x86_64-linux-android \
 && rustup component add rust-src

# musl-cross toolchains for mips/mipsel (-Z build-std path), mirrors the
# upstream prepare-build action: the .cargo/config.toml references
# ./musl_gcc/... so jobs symlink /opt/musl_gcc into the workspace.
ARG MUSL_CROSS_REPO=cross-tools/musl-cross
ARG MUSL_CROSS_TAG=20250520
RUN for target in mips-unknown-linux-muslsf mipsel-unknown-linux-muslsf; do \
      curl -fsSL -o /tmp/${target}.tar.xz \
        "https://github.com/${MUSL_CROSS_REPO}/releases/download/${MUSL_CROSS_TAG}/${target}.tar.xz" \
      && mkdir -p /opt/musl_gcc \
      && tar -xJf /tmp/${target}.tar.xz -C /opt/musl_gcc \
      && rm -f /tmp/${target}.tar.xz \
      && ln -sf /opt/musl_gcc/${target}/bin/*gcc /usr/bin/ \
      && ln -sf /opt/musl_gcc/${target}/include/ /usr/include/musl-cross; \
    done \
 && ln -sf /opt/musl_gcc/mips-unknown-linux-muslsf/mips-unknown-linux-muslsf/sysroot \
           /opt/musl_gcc/sysroot \
 && for target in mips-unknown-linux-muslsf mipsel-unknown-linux-muslsf; do \
      cd /opt/musl_gcc/${target}/lib/gcc/${target}/15.1.0 \
      && cp libgcc_eh.a libunwind.a \
      && ar x libgcc.a _ctzsi2.o _clz.o _bswapsi2.o \
      && ar rcs libctz.a _ctzsi2.o _clz.o _bswapsi2.o; \
    done \
 && chmod -R a+rwx /opt/musl_gcc

# Android NDK toolchain: the NDK's llvm prebuilt tree comes from a named
# build context (docker/build-image.sh passes --build-context ndk=<ndk dir>).
# The llvm prebuilt clang cross-compiles the *-linux-android targets and
# provides the bionic sysroot that zig does not ship. kcp-sys' bindgen
# needs BINDGEN_EXTRA_CLANG_ARGS pointing at that sysroot (see release.yml).
COPY --from=ndk /toolchains /opt/ndk/toolchains
RUN test -x /opt/ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android24-clang

# Minimal macOS SDK (link-time stubs only): Rust crates are precompiled,
# so only the tbd files are needed, not headers. Zig ships libSystem etc.
# but not the Apple frameworks (CoreFoundation/Security/SystemConfiguration/
# IOKit) or libobjc, which easytier's macOS dependency tree links against.
# The tbds come from the public phracker/MacOSX-SDKs repo; each is a few
# tens of KB. Release jobs pass
#   CARGO_TARGET_<TRIPLE>_RUSTFLAGS="-C link-arg=-F/opt/macos-sdk/System/Library/Frameworks -C link-arg=-L/opt/macos-sdk/usr/lib"
# (see release.yml).
ARG MACOS_SDK_URL=https://raw.githubusercontent.com/phracker/MacOSX-SDKs/master/MacOSX11.3.sdk
RUN mkdir -p /opt/macos-sdk/System/Library/Frameworks \
             /opt/macos-sdk/System/Library/Frameworks/CoreFoundation.framework \
             /opt/macos-sdk/System/Library/Frameworks/Security.framework \
             /opt/macos-sdk/System/Library/Frameworks/SystemConfiguration.framework \
             /opt/macos-sdk/System/Library/Frameworks/IOKit.framework \
             /opt/macos-sdk/usr/lib \
 && curl -fsSL -o /opt/macos-sdk/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation.tbd \
      "${MACOS_SDK_URL}/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation.tbd" \
 && curl -fsSL -o /opt/macos-sdk/System/Library/Frameworks/Security.framework/Security.tbd \
      "${MACOS_SDK_URL}/System/Library/Frameworks/Security.framework/Versions/A/Security.tbd" \
 && curl -fsSL -o /opt/macos-sdk/System/Library/Frameworks/SystemConfiguration.framework/SystemConfiguration.tbd \
      "${MACOS_SDK_URL}/System/Library/Frameworks/SystemConfiguration.framework/Versions/A/SystemConfiguration.tbd" \
 && curl -fsSL -o /opt/macos-sdk/System/Library/Frameworks/IOKit.framework/IOKit.tbd \
      "${MACOS_SDK_URL}/System/Library/Frameworks/IOKit.framework/Versions/A/IOKit.tbd" \
 && curl -fsSL -o /opt/macos-sdk/usr/lib/libobjc.A.tbd \
      "${MACOS_SDK_URL}/usr/lib/libobjc.A.tbd" \
 && ln -sf libobjc.A.tbd /opt/macos-sdk/usr/lib/libobjc.tbd \
 && find /opt/macos-sdk -name '*.tbd' | xargs wc -c | tail -1

# Warm the cargo registry AND the pnpm store with the repo's locked
# dependency set so job runs download nothing. The repo tree comes from a
# named build context (docker/build-image.sh archives the committed HEAD).
# easytier-gui + tauri-plugin-vpnservice are warmed too: the APK job runs
# `pnpm tauri android build` inside easytier-gui, and a cold store made
# pnpm download through a flaky egress and hang.
COPY --from=repo / /tmp/warmup/repo
RUN cd /tmp/warmup/repo \
 && cargo fetch \
 && pnpm install --frozen-lockfile \
 && rm -rf /tmp/warmup

# binaryen/wasm-opt: wasm-pack's release profile for easytier-core uses
# wasm-opt flags; the generated wasm uses sign-extension instructions which
# old binaryen (apt 108) rejects. Install the binaryen version wasm-pack
# 0.13.1 pins (`version_117`, treated as its own layer so earlier layers
# stay cached).
ARG BINARYEN_VERSION=version_117
RUN curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors -C - \
      -o /tmp/binaryen.tar.gz \
      "https://github.com/WebAssembly/binaryen/releases/download/${BINARYEN_VERSION}/binaryen-${BINARYEN_VERSION}-x86_64-linux.tar.gz" \
 && tar -xzf /tmp/binaryen.tar.gz -C /opt \
 && mv "/opt/binaryen-${BINARYEN_VERSION}" /opt/binaryen \
 && ln -sf /opt/binaryen/bin/wasm-opt /usr/local/bin/wasm-opt \
 && rm -f /tmp/binaryen.tar.gz \
 && wasm-opt --version

WORKDIR /workspace