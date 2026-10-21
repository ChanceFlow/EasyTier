# EasyTier Flutter client

The cross-platform EasyTier client. It replaces the Tauri GUI
([`../easytier-gui/`](../easytier-gui/), deprecated — see
[`DEPRECATED.md`](../easytier-gui/DEPRECATED.md)) and is the only place where
new client work happens.

Status: **active development**. The app runs the full five-destination UI against
a mock core by default; the real transport (`easytier-ffi` over `dart:ffi`) and
the Android `VpnService` data plane are wired in parallel.

## Stack

| Layer | Choice |
|---|---|
| UI | Flutter with **Google Material 3** (`ColorScheme.fromSeed` Google blue, M3 components, M3 motion) |
| State | `ChangeNotifier` + `InheritedNotifier` (no third-party state package) |
| Theme | `lib/core/theme/theme.dart` → Material 3 `ThemeData`; `EtPalette` wraps the M3 `ColorScheme` (+ Google success/warning roles). Follows the system theme by default |
| Icons | Material Symbols (`material_symbols_icons`) — Google's official M3 icon set |
| Fonts | **System fonts**: platform UI font (Roboto/SF/Segoe/system-ui) + platform monospace for machine data + system CJK fallback. No text fonts are bundled |
| Core bridge | `CoreClient` seam (`lib/core/client/core_client.dart`): mock now, FFI/daemon later |
| Android data plane | `android.net.VpnService` → fd → `set_tun_fd` (see `android/README.md`) |

## Run

This machine's Flutter lives in a podman toolchain image. Always use the
wrapper (it mounts the tree, keeps a persistent pub cache, and uses host
networking):

```bash
bash /home/chance/Projects/.flutter-run.sh \
  /home/chance/Projects/easytier/easytier-flutter run -d linux
```

On a normal workstation with Flutter installed:

```bash
flutter pub get
flutter run          # or -d linux / -d macos / -d windows / -d <android device>
```

### Real core instead of the mock

```bash
# 1. build the cdylib for this host
bash tool/build_native.sh
# 2. run with the FFI transport
flutter run --dart-define=EASYTIER_USE_FFI=true
```

`createCoreClient()` falls back to the mock (with loader diagnostics on stderr)
when the native library is missing, so the app never pretends to be tunnelling
when it is not.

## Verify

```bash
bash /home/chance/Projects/.flutter-run.sh /home/chance/Projects/easytier/easytier-flutter analyze
bash /home/chance/Projects/.flutter-run.sh /home/chance/Projects/easytier/easytier-flutter test
```

Goldens are the design-review artifact:

```bash
bash /home/chance/Projects/.flutter-run.sh /home/chance/Projects/easytier/easytier-flutter \
  test --update-goldens test/golden_test.dart
```

PNGs land in `test/goldens/`. Data is deterministic (injected clock + fixed
seed), so a golden diff means the UI changed, not the data.

M3/wireframe contrast claims are machine-checked:

```bash
bash /home/chance/Projects/.flutter-run.sh /home/chance/Projects/easytier/easytier-flutter \
  test tool/check_tokens.dart
```

It builds the real `ColorScheme.fromSeed` + `EtPalette` and asserts WCAG AA for
every colour pair the UI renders (light and dark).

## Structure

```
lib/
  app.dart                  # MaterialApp + 5-destination shell + splash
  main.dart                 # composition root: picks the CoreClient
  core/
    theme/                  # tokens (palette/space/type/motion) + ThemeData
    models/                 # NetworkConfig, InstanceStatus, Peer, events
    client/                 # CoreClient seam, mock, factory; ffi/ (real transport)
    state/                  # AppState + AppScope (single global store)
    ui/                     # M3 kit: Card/FilledButton/ListTile/ExpansionTile wrappers…
    vpn/                    # VpnService abstraction + controller (Android)
  system_ui.dart            # edge-to-edge + M3 system bar icon brightness
  features/
    home/ devices/ config/ activity/ settings/
test/
  golden_test.dart          # screenshots: phone/desktop, dark/light
  support/test_app.dart     # test-only font fixtures + deterministic app pump helpers
```

## Design

The client is **Google Material 3**: seeded colour system (`ColorScheme.fromSeed`,
Google blue #0B57D0) with a Material 3 **Expressive** layer (hero + connection
orb + bento stats + vivid decorative accents), system-font typography, M3
shape/elevation/state
layers/motion, Material 3 components (AppBar, NavigationBar/Rail, Cards,
FilledButton, SegmentedButton, ListTile, ExpansionTile, SwitchListTile,
TextFormField, dialogs/sheets) and **Material Symbols** icons.

The written source of truth is
[`design-system/easytier-flutter/MASTER.md`](../design-system/easytier-flutter/MASTER.md)
(it replaced the previous custom "Instrument" v3 spec). Product-specific rules
that survive on top of M3: one primary action per screen, tri-encoded connection
state (icon + colour + text, with Google success/warning roles Material does not
ship), mono for machine data, 4.5:1 contrast, reduced motion respected, no emoji
icons.

## Platform notes

- **Android**: `VpnService` owns the TUN device and the foreground notification;
  the detached fd is handed to the Rust core. Only one active tunnel is
  possible; `onRevoke` (another VPN app) is surfaced to the UI.
- **Desktop**: runs the in-process core. Service/daemon mode and the elevation
  path are follow-ups in `docs/adr/0001-flutter-client.md`; the desktop build
  also needs the cdylib from `tool/build_native.sh`.
- **iOS**: project scaffold exists; the tunnel needs a NetworkExtension and is
  not implemented yet.

## Known gaps (honest list)

- Mock transport is the default; FFI is opt-in and needs a per-target native
  build (see `lib/core/client/ffi/README.md`).
- No i18n yet: copy is English; language selection persists but does not
  translate (M2).
- Config-server remote management and VPN portal management are not exposed in
  the Flutter UI yet.
- Desktop privilege elevation and the system-service mode are not implemented.
- Android device build is not verified in this environment (SDK licences).

### Android APK with the bundled Rust core

```bash
# requires Rust + Android NDK r28 + protoc; see android/README.md
ANDROID_NDK_HOME=$ANDROID_HOME/ndk/28.2.13676358 tool/build_android.sh
```

This stages `libeasytier_ffi.so` for arm64-v8a and builds with
`--dart-define=EASYTIER_USE_FFI=true`; without it the APK runs the mock core.
