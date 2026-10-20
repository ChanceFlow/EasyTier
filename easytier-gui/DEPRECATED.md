# `easytier-gui` is deprecated

> **Status: deprecated — maintenance only.**
> The replacement is the Flutter client in [`easytier-flutter/`](../easytier-flutter/).
> Decision record: [`docs/adr/0001-flutter-client.md`](../docs/adr/0001-flutter-client.md).
> Deprecated on 2026-10-20.

This directory contains the Tauri 2 + Vue 3 + Vuetify desktop/mobile client, with a
Rust backend that embeds `easytier-core`. It is **not deleted** and **not abandoned**,
but it is no longer where client development happens.

## What "deprecated" means here

Frozen — do not add:

- new features or options;
- new platforms or form factors;
- redesigns or design-system changes for this client.

Accepted — maintenance fixes:

- security fixes;
- data-loss or data-corruption fixes;
- crash fixes on platforms this client already supports;
- build, toolchain and dependency breakage needed to keep the existing pipeline
  green (Rust edition, Tauri, Android SDK/NDK, pnpm/Vite, CI runner images);
- corrections to this document and to the deprecation notices.

A pull request that adds a feature under `easytier-gui/` should almost certainly
target [`easytier-flutter/`](../easytier-flutter/) instead. Fixes that meet the list
above are still welcome.

## Why we are replacing it

1. **One UI stack instead of two.** The web console (`easytier-web/frontend-lib`,
   Vue) and the native client were two Vue codebases with separate build, review
   and design-system work. The client is being consolidated on Flutter so the
   native UI is built and shipped independently of the web console.
2. **A mobile-native data plane.** On Android the client must own the tunnel
   through a `VpnService`, hand its file descriptor to the core, and survive
   process/service lifecycle events. The Tauri path does this through a custom
   Tauri plugin (`tauri-plugin-vpnservice`) and a webview/Kotlin bridge; Flutter
   integrates with `VpnService` directly and is the platform the mobile UX work
   is now designed for.
3. **UI consistency across form factors.** The new design system is native to the
   client stack (`design-system/easytier-flutter/`), so desktop and mobile render
   the same tokens, spacing and components instead of translating Vue/Vuetify
   output through a webview.

## What the replacement is, and what it is not yet

[`easytier-flutter/`](../easytier-flutter/) is the new client:

- **Framework:** Flutter, with platform scaffolds for Android, Linux, Windows,
  macOS and iOS (iOS is a target the Tauri client never shipped).
- **Design system:** [`design-system/easytier-flutter/`](../design-system/easytier-flutter/).
- **Bridge:** the `easytier-ffi` C ABI called through `dart:ffi` on Android and
  desktop, plus an optional desktop daemon that the UI reaches over the core's
  RPC/JSON bridge (needed for service-mode and unprivileged UI operation).
- **Core seam:** `CoreClient` in
  [`easytier-flutter/lib/core/client/core_client.dart`](../easytier-flutter/lib/core/client/core_client.dart).
- **Android data plane:** a `VpnService` establishes the tun and passes its file
  descriptor to `set_tun_fd`; the core owns the tunnel from then on.

**The Flutter client is under active construction and is not feature-complete.**
The deprecation is a feature freeze on the Tauri client, not a removal of it:
until parity is reached, `easytier-gui` remains the client that ships.

## Feature parity table

This is a snapshot taken at deprecation time (2026-10-20). For the live state of
the new client, read `easytier-flutter/`; do not treat this table as a promise of
what exists today.

| Capability | Tauri client (frozen) | Flutter client (target) |
| --- | --- | --- |
| Normal mode — run core in-process, one config per instance | Yes | In progress — screens exist but run on `MockCoreClient`; the FFI client is not wired yet |
| Service mode — core runs as a system service/daemon, UI attaches over RPC | Yes | Planned — depends on the desktop daemon option |
| Remote mode — attach to an RPC endpoint of a core on another host | Yes | Planned |
| Embedded web console / config-server login | Yes | Deferred; the web console stays a web surface |
| VPN portal client management (WireGuard portal peers) | Yes | Planned |
| Android VPN (`VpnService` + tunnel fd, quick-settings tile, traffic notification) | Yes, via `tauri-plugin-vpnservice` | In progress — target design is `VpnService` fd → `set_tun_fd` |
| Tray icon, autostart, single-instance | Yes | Planned (desktop) |
| Privilege elevation (macOS / Windows / Linux) | Yes (`src-tauri/src/elevate`) | Unresolved — needs a desktop-daemon/elevation decision |
| i18n (English / Chinese) | Yes, shared `frontend-lib` locales | In progress (`Locale` in app state; no locale pipeline yet) |
| Design system | Vuetify + `design-system/easytier` tokens | `design-system/easytier-flutter` (Flutter-native tokens) |
| Platforms | Windows, macOS, Linux, Android | Android, Linux, Windows, macOS, iOS scaffolds |

## How to build and run the legacy client

The full prerequisite list is in [`README.md`](README.md). The short version,
from the repository root, is:

```bash
# shared native/frontend dependencies
pnpm --dir tauri-plugin-vpnservice install && pnpm --dir tauri-plugin-vpnservice build
pnpm --dir easytier-web/frontend-lib install && pnpm --dir easytier-web/frontend-lib build

# desktop
cd easytier-gui
pnpm install
pnpm tauri dev     # development
pnpm tauri build   # release bundles

# Android
pnpm tauri android init
pnpm tauri android build
```

`easytier-gui/src-tauri` is still a member of the Cargo workspace, so it keeps
building through the normal workspace commands until it is removed in the
cleanup step below.

## Migration checklist

For the team, roughly in order:

- [ ] Sign off feature parity row by row against the shipped Flutter client.
- [ ] Add Flutter build/test CI (Android and the desktop targets) before dropping
      any Tauri job, so no platform loses coverage.
- [ ] Decide how Flutter artifacts enter the release pipeline. Note that
      `assemble.yml` currently dispatches `release.yml` only when the Core, GUI
      and Mobile runs all succeed on the same commit, and `release.yml` downloads
      a GUI artifact; both need a decision, not just a workflow deletion.
- [ ] Pick the release tag after which Tauri artifacts (NSIS/DMG/deb/rpm/AppImage,
      Android APKs, and the Homebrew cask that points at them) are no longer
      published. This is a product decision, not a docs change.
- [ ] Then remove `easytier-gui/src-tauri` from `Cargo.toml` workspace members,
      retire `.github/workflows/gui.yml` and `.github/workflows/mobile.yml`, and
      decide the fate of `tauri-plugin-vpnservice`, the `easytier-gui` pnpm
      workspace packages, and the `design-system/easytier` job that builds the
      legacy client (`verify-all.sh`).
- [ ] Update install documentation, the Homebrew tap, and any links that still
      describe the Tauri client as the client.
- [ ] Announce the replacement in the release notes of the first Flutter release.

## Relationship to upstream

This repository is a fork: `origin` is the Gitea forge (ChanceFlow) and
`upstream` is `github.com/EasyTier/EasyTier`. **Upstream's GUI is Tauri.** As a
consequence of choosing Flutter here, future upstream GUI changes cannot be
merged into this client: the client is now permanently fork-only, and only core
changes (`easytier-core`, `easytier-proto`, CLI, and other non-GUI crates) can
still be taken from upstream. Any upstream GUI bug fix that matters here has to
be reimplemented against the Flutter client.

## Not deprecated: the Vue design system

[`design-system/easytier/`](../design-system/easytier/) is **not** deprecated. It
is still the current design system for the web console
(`easytier-web/frontend-lib`) and it still gates the frozen Tauri client while
that client exists. It simply no longer governs the client going forward; new
client UI work follows `design-system/easytier-flutter/`.
