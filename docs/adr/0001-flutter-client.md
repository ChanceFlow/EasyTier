# ADR 0001 — Client rewrite in Flutter

- **Status:** Accepted
- **Date:** 2026-10-20
- **Deciders:** EasyTier fork maintainers (ChanceFlow)
- **Supersedes:** none
- **Superseded by:** none

## Context

EasyTier's native client lives in `easytier-gui/`: a Tauri 2 application with a
Vue 3 + Vuetify frontend and a Rust backend (`easytier-gui/src-tauri`) that
embeds `easytier-core` directly. A separate Vue codebase,
`easytier-web/frontend-lib`, powers the web console and is shared with the Tauri
client. The client is built by `.github/workflows/gui.yml` (desktop bundles)
and `.github/workflows/mobile.yml` (Android APKs); Android tunnel integration
goes through our own `tauri-plugin-vpnservice`.

This repository is a fork. `origin` is the Gitea forge (ChanceFlow) and
`upstream` is `github.com/EasyTier/EasyTier`, whose GUI is also Tauri. The
release flow in `AGENTS.md` relies on the GitHub fork for cross-platform CI.

Three problems drove this decision:

1. **Mobile is now the primary form factor, and Tauri treats it as secondary.**
   Android needs a `VpnService` that owns the tunnel and hands its file
   descriptor to the core. In Tauri that requires a custom plugin plus a
   webview↔Kotlin bridge; we already shipped a wiring guard
   (`scripts/verify-android-vpn-wiring.mjs`) because cross-file drift between
   the webview, the Tauri ACL and the Kotlin handlers caused silent failures.
2. **Two UI toolchains and two design systems for one product.** The Vue design
   system (`design-system/easytier/`) serves the web console; the client needs
   its own native design system. Keeping both stacks means duplicating
   components, tokens and review effort across Vue and the client.
3. **Webview rendering is not consistent enough for a client UI.** Fonts,
   layout, insets and scroll behaviour differ per platform webview, and a
   client that must look the same on Windows, macOS, Linux and Android pays for
   that repeatedly.

## Decision

The native client is rewritten in **Flutter** in `easytier-flutter/`, and the
Tauri client in `easytier-gui/` is **removed**. The Flutter client is the only
native client in this repo; the Tauri crate and its Android plugin no longer
build or ship here.

- New client work — features, platforms, redesigns — happens only in
  `easytier-flutter/`.
- Tauri client sources, its Android plugin, GUI/mobile workflows and release
  assets were deleted; upstream can still carry its own GUI, this fork does not.
- Both clients coexist until the Flutter client reaches feature parity; only
  were Tauri artifacts and Tauri CI jobs; both are now retired.
- The web console (`easytier-web/frontend-lib`) and its design system
  (`design-system/easytier/`) are unaffected; they are not deprecated.
- The Flutter client follows `design-system/easytier-flutter/`.

The Flutter client targets Android, Linux, Windows, macOS and iOS. The bridge
design is recorded below; it is the load-bearing part of this decision.

## Alternatives considered

### Tauri 2 (status quo)

Continue investing in the existing Vue client and eventually improve its mobile
support.

- **Pros:** works and ships today; shares Vue components and i18n with the web
  console; small bundles because it uses the system webview; CI, release flow
  and design gates already exist; identical to upstream, so GUI patches merge
  cleanly.
- **Cons:** mobile is a second-class target — the Android tunnel needs a custom
  plugin and a Kotlin/webview bridge, and mobile lifecycle (VpnService
  revocation, foreground service, process death) is fragile across the webview
  boundary; rendering differs per platform webview; the client stays coupled to
  the web console's Vue/Vuetify toolchain and design system.
- **Why rejected:** it keeps the two costs we are trying to remove — webview
  inconsistency and a mobile bridge we do not control — while the product moves
  mobile-first.

### Flutter (chosen)

- **Pros:** one rendering stack (Impeller/Skia) gives the same pixels on every
  platform; first-class Android and desktop targets, iOS scaffold included;
  direct platform integration for `VpnService` and a typed bridge for the Rust
  core; hot reload and a mature test story; design tokens map directly onto
  Flutter themes, so one native design system serves all platforms.
- **Cons:** a full rewrite of the client UI; the Flutter engine is bundled, so
  binaries are larger than a system-webview Tauri app; a new toolchain and new
  CI; the FFI boundary must be kept ABI-stable; desktop niceties (tray,
  notifications, elevation) need plugins or custom code.
- **Why chosen:** best fit for a mobile-first VPN client that must render
  identically everywhere and own a native tunnel, with no webview between the
  core and the UI.

### Compose Multiplatform

- **Pros:** Kotlin, Android-native quality, shared UI across Android, desktop
  and iOS; strong JetBrains tooling.
- **Cons:** iOS support is younger than Flutter's, desktop still maturing; adds
  a JVM/Kotlin toolchain next to Rust with no reuse elsewhere in this repo;
  nothing in the existing tree is Kotlin.
- **Why rejected:** no decisive advantage over Flutter, and it exchanges
  Flutter's broader platform maturity for Kotlin alignment we do not otherwise
  have.

### Electron

- **Pros:** could reuse Vue code and web skills; fastest route back to a
  desktop UI.
- **Cons:** no native mobile story at all; ships Chromium + Node with every
  install; a poor fit for a long-running VPN process; still needs a Rust
  sidecar and a bridge.
- **Why rejected:** it cannot serve Android, which is the primary target.

### React Native

- **Pros:** TypeScript, a large ecosystem, strong mobile support.
- **Cons:** still a full UI rewrite (Vue → React), plus native modules for the
  Android tunnel and a desktop story (Windows/macOS) less mature than Flutter's;
  high-frequency status streaming over the JS bridge needs care.
- **Why rejected:** the only reuse argument is JS/TS familiarity, which is
  outweighed by a rewrite and a weaker desktop story.

### Rust-native UI (Slint / egui)

- **Pros:** no FFI bridge — UI and core in one language, direct access to core
  types, smallest binaries, no webview.
- **Cons:** the ecosystem is immature for a polished consumer app.
  Accessibility, IME, CJK text shaping, tray/notifications and per-platform
  integration would largely be hand-rolled; design-system fidelity would be
  hard to reach; egui's immediate-mode model fits a settings-heavy form app
  poorly, and Slint's mobile story is young.
- **Why rejected:** concentrates the highest engineering risk exactly where the
  current client is already weakest — UI polish and platform integration.

## Bridge design

The UI never touches a socket, a config file or a TUN fd directly. Everything
goes through the `CoreClient` seam in
`easytier-flutter/lib/core/client/core_client.dart`, which has two
implementations: `MockCoreClient` (design and tests, no Rust required) and an
FFI client for real cores.

```text
Flutter UI (Android / Linux / Windows / macOS / iOS)
  └── CoreClient (Dart interface: init, list/run/stop/delete instance,
        save/get/validate config, collectStatus, version, events stream)
        ├── FfiCoreClient — dart:ffi → libeasytier_ffi (C ABI)
        │     • parse_config / run_network_instance / retain_network_instance
        │     • delete_network_instance / list_instance / collect_network_infos
        │     • call_json_rpc (per-instance RPC through the FFI boundary)
        │     • set_tun_fd (attach a tun fd to a named instance)
        │     • start/stop_config_server_client, get_error_msg, free_string
        └── Optional desktop daemon — UI ↔ core daemon over the core's
              RPC/JSON bridge (service mode, unprivileged UI, elevation)
```

- **Android data plane:** the app establishes a `VpnService` tunnel, passes the
  `ParcelFileDescriptor` to `set_tun_fd`, and the core drives the data plane
  from then on. No webview and no Tauri plugin sits in that path.
- **Desktop in-process mode:** the same `easytier-ffi` C ABI is loaded with
  `dart:ffi`, so the client can run a core in-process with the ordinary config
  TOML.
- **Desktop daemon mode (optional):** service mode and any UI that must run
  unprivileged attach to a core daemon over the core's RPC/JSON bridge instead
  of loading the library in-process. This is the intended shape, but the exact
  transport (core RPC endpoint vs. a thin JSON bridge over a local socket) and
  the privilege-elevation model are follow-up design work, not settled here.
- **ABI:** `easytier-ffi` stays the narrow contract between client and core.
  Its C ABI and the native data-plane ABI are versioned separately from the
  Flutter app; contract tests live with the FFI crate. This crate is the one
  place where client work and core work must agree, which keeps the client
  decoupled from core internals.

## Consequences

### Positive

- The client gets one UI stack and one native design system across Android,
  Linux, Windows, macOS and iOS, instead of one Vue system for the web console
  and a translated one for the client.
- Android owns its tunnel directly (`VpnService` fd → `set_tun_fd`), removing
  the custom Tauri plugin and its cross-file wiring class of bugs.
- The client can evolve independently: it no longer shares a component library,
  build or release cadence with the web console.
- `CoreClient` makes the UI testable without Rust (`MockCoreClient`), so design
  and screen work are not blocked on the native build.
- The Flutter client can add iOS, which the Tauri client never shipped.

### Negative

- **A full rewrite.** No Vue screen can be reused; every feature must be
  reimplemented and re-reviewed against the parity table.
- **A short dual-maintenance window** (historical). Two clients existed until the Tauri
  client still needs security and build fixes, and the Flutter client needs to
  catch up. This is the largest cost of the decision.
- **Larger binaries** than the system-webview Tauri app, and a new toolchain
  (Flutter SDK, podman-based runner here) plus new CI to maintain.
- **Desktop service mode and escalation** used to fall out of the Tauri process
  being a Rust binary with elevation helpers; the Flutter client needs an
  explicit daemon/elevation design instead.
- **Design-system duplication** persists until the Vue and Flutter token sets
  converge on one machine-readable source.

### Upstream (accepted, permanent)

Upstream's GUI is Tauri. Choosing Flutter means:

- future upstream **GUI** changes cannot be merged — they target a different
  framework and a different component tree;
- only **core** changes (`easytier-core`, `easytier-proto`, the CLI, and other
  non-GUI crates) can still be taken from upstream;
- our client becomes permanently fork-only: upstream GUI bug fixes that matter
  here must be reimplemented against the Flutter client;
- the fork can no longer be a clean mirror of upstream. This is accepted
  deliberately, not overlooked.

Mitigation: keep client code out of shared/core crates, keep the crack at the
`easytier-ffi` boundary, and sync core regularly. The alternative — staying on
Tauri to preserve GUI merges — was rejected because it preserves upstream
compatibility at the cost of the client architecture we actually need.

### Risks

- **FFI ABI drift** between the Dart bindings and `easytier-ffi`; mitigated by
  versioning the ABI and keeping contract tests in the FFI crate.
- **Android lifecycle:** VpnService revocation, background-start restrictions
  and OEM battery policy can break a tunnel that the UI still reports as up;
  the Tauri client already shipped a fix for exactly that class of bug, and the
  Flutter client must design for it from the start.
- **iOS tunnel** needs a NetworkExtension Packet Tunnel Provider and App Store
  review; that design does not exist yet and is the least-proven target.
- **Parity may slip** while the Tauri client is frozen; the parity table in
  removed Tauri client was the tracking artifact; parity is now tracked in
  `easytier-flutter/README.md`.

## Follow-up decisions (not settled by this ADR)

1. The release tag after which Tauri artifacts stop being published, and how
   Homebrew/the install docs move to Flutter.
2. How Flutter artifacts enter the release pipeline — `assemble.yml` currently
   requires the Core + GUI + Mobile runs on one commit, and `release.yml`
   downloads a GUI artifact.
3. The desktop daemon and privilege-elevation model for service mode.
4. The iOS tunnel design (NetworkExtension) and whether iOS ships with the
   first Flutter release.
5. An FFI ABI versioning policy and its contract-test surface.

## References

- `easytier-flutter/README.md` — current client status and known gaps.
- `easytier-flutter/lib/core/client/core_client.dart` — the `CoreClient` seam.
- `easytier-contrib/easytier-ffi/` — the C ABI and `DATA_PLANE_ABI.md`.
- `design-system/easytier-flutter/` — the client design system.
- `design-system/easytier/` — the Vue design system, still current for the web
  console and not deprecated by this ADR.
- `.github/workflows/gui.yml`, `.github/workflows/mobile.yml` — the deprecated
  client's build jobs.
- `AGENTS.md` — release/versioning conventions, including the Flutter runner.
