# EasyTier Flutter — Android VPN data plane

This directory is the Android side of the Flutter client. The only part that is
not stock `flutter create` output is the VPN data plane, which owns Android's
process-wide TUN slot and hands the raw TUN fd to the Rust core.

Ported from the deprecated Tauri client (`tauri-plugin-vpnservice/android`);
the behaviour is preserved, the Tauri plugin runtime is not.

> **Status:** compiles and packages in this repo's podman toolchain
> (`:app:compileDebugKotlin` and `:app:assembleDebug` both succeed; the packaged
> APK contains the services, permissions, drawables and strings described
> below), Dart analyzer-clean, but **not device-verified**: no device/emulator is
> available, so none of the runtime behaviour was exercised. See
> [What must be verified on a real device](#what-must-be-verified-on-a-real-device).

## Files

| File | Responsibility |
| --- | --- |
| `.../MainActivity.kt` | Flutter host + `MethodChannel("com.kkrainbow.easytier/vpn")` / `EventChannel("com.kkrainbow.easytier/vpn/events")`; VPN consent flow, service start/stop, notification permission, live rate updates, tile-action drain |
| `.../EasyTierVpnService.kt` | Real `android.net.VpnService`: `establish()` → `detachFd()`, foreground service, `onRevoke`, single-tunnel enforcement, fd ownership/lifecycle |
| `.../VpnNotification.kt` | Single source of truth for the ongoing notification (channel id, notification id, copy, actions, rate formatting) |
| `.../EasyTierVpnTileService.kt` | Quick-settings tile (start/stop; falls back to opening the app) |
| `.../VpnEvents.kt` | Process-wide event bus (service → activity) and tile → Dart bridge |
| `res/values{,-zh-rCN}/strings.xml` | Notification/tile copy |
| `res/drawable/ic_notification.xml`, `vpn_tile_icon.xml` | Status-bar and tile icons |

Dart side lives in `lib/core/vpn/`:

| File | Responsibility |
| --- | --- |
| `vpn_service.dart` | `VpnService` seam, `MethodChannelVpnService`, `UnsupportedVpnService`, `FakeVpnService`, models/events |
| `vpn_controller.dart` | `VpnController`: consent→start sequence, `Stream<int> tunFds`, `TunFdSink`, teardown reasons |
| `vpn.dart` | Barrel export |

No new Flutter or Gradle dependencies: the native layer uses platform APIs only
(`android.app.Notification`, `android.service.quicksettings`, `android.system.Os`),
so `build.gradle.kts` is untouched (Flutter 3.47 defaults: `minSdk 24`,
`compileSdk 36`, `targetSdk 36`).

## Channel contract

Commands (`MethodChannel "com.kkrainbow.easytier/vpn"`):

| Method | Args | Result |
| --- | --- | --- |
| `prepare` | — | `bool` (consent granted; shows the system dialog when needed) |
| `start` | `{ipv4Cidr, ipv6Cidr?, routes, dns, mtu, session, disallowedApplications}` | `{type:"started", fd, ipv4Cidr, ipv6Cidr, routes, dns, mtu, session}` |
| `stop` | — | `null` |
| `status` | — | `{running, ipv4Cidr, ipv6Cidr, routes, dns, mtu, lastError}` |
| `requestPermission` | — | `bool` (POST_NOTIFICATIONS, Android 13+) |
| `notificationStatus` | — | `{granted, enabled}` |
| `openNotificationSettings` | — | `null` |
| `updateNotification` | `{rxBps, txBps, connected}` | `null` |
| `consumeTileAction` | — | `"start" \| "stop" \| null` |

`start` throws `PlatformException` with `need_prepare` (consent missing),
`bad_args`, `vpn_busy` (another start/consent request in flight),
`vpn_start_failed`, `vpn_start_timeout` (10 s without a TUN fd).

Events (`EventChannel "com.kkrainbow.easytier/vpn/events"`):

| `type` | Payload | Meaning |
| --- | --- | --- |
| `started` | tunnel map (as above) | Tunnel ready, **only** when it was not started by the pending `start` call (tile / service restart) so the fd is handed over exactly once |
| `stopped` | `reason`: `user` \| `revoked` \| `destroy` \| `superseded` \| `error` | Tunnel down. `revoked` = another VPN app took the slot |
| `error` | `message` | Native establish/start failure |
| `tileAction` | `action`: `start` \| `stop` | Quick-settings tile tapped while the app is in the foreground |

## fd handoff

```
Dart VpnController.connect(request)
  └─> MethodChannel "prepare"            (VpnService.prepare -> system consent)
  └─> MethodChannel "start" (extras)
        └─> MainActivity.startForegroundService(EasyTierVpnService, request)
              └─> VpnService.establish()            -> ParcelFileDescriptor
              └─> Builder.setBlocking(false)
              └─> pfd.detachFd()                    -> raw int fd (ownership: Kotlin)
              └─> MethodChannel result {fd, ...}    (or "started" event for tile starts)
  └─> VpnController.tunFds  /  TunFdSink.setTunFd(fd)
  └─> Rust bridge: set_tun_fd(instanceName, fd)  -> easytier-core attaches the NIC
```

Ownership rules:

* Kotlin is the owner of the descriptor. The core **borrows** it:
  `easytier-core` configures the tun crate with `close_fd_on_drop(false)`
  (`easytier/src/instance/virtual_nic.rs`), so Rust never closes it.
* Therefore the service must close the fd on every teardown path
  (`EasyTierVpnService.releaseTunnel` → `Os.close`), otherwise every
  connect/disconnect leaks one descriptor. Dart must never close it.
* On teardown the fd is closed before the `stopped` event is emitted; the Rust
  side sees EBADF/EOF and its data-plane tasks exit. Stop the core instance
  before or right after calling `VpnController.disconnect()`.

Desktop/other platforms use `UnsupportedVpnService`; the core creates its own
TUN there, so no VpnService is involved.

## Permission model

Manifest (`android/app/src/main/AndroidManifest.xml`):

* `INTERNET` — the Rust core opens peer/RPC sockets from this process.
* `FOREGROUND_SERVICE` — an active VPN must be a foreground service.
* `FOREGROUND_SERVICE_SPECIAL_USE` — targetSdk 34+ requires a declared FGS type;
  `VpnService` has no dedicated type, so the tunnel is declared `specialUse`
  with `PROPERTY_SPECIAL_USE_FGS_SUBTYPE` ("Maintains the user-initiated
  EasyTier VPN tunnel.").
* `POST_NOTIFICATIONS` — Android 13+ runtime permission, requested through the
  `requestPermission` method. Without it the tunnel still works but the ongoing
  notification is invisible.
* `<service .EasyTierVpnService android:permission="android.permission.BIND_VPN_SERVICE">`
  with `android.net.VpnService` intent filter (what makes the app a VPN client),
  `android:exported="false"`.
* Tile: `BIND_QUICK_SETTINGS_TILE` permission/service + `QS_TILE_PREFERENCES`
  activity alias (long-press opens the app).
* `android:usesCleartextTraffic` is deliberately **not** set.

Runtime consents:

1. **VPN consent** (`VpnService.prepare`): one-time system dialog, revocable
   from system VPN settings. Dart calls `VpnController.prepare()` first; if the
   user declines, `connect()` returns null with `lastError =
   vpn_permission_denied`.
2. **Notifications** (Android 13+): `VpnService.requestNotificationPermission()`;
   screens should surface `VpnNotificationStatus.canShowOngoing`.
3. **Background start restriction** (targetSdk 31+): connecting while the
   activity is not visible can be rejected by the system. The native side maps
   that to `vpn_start_failed`; the UI should ask the user to bring the app
   forward. The quick-settings tile therefore only dispatches to Dart when the
   app is in the foreground, and otherwise opens the app.

## Single-tunnel constraint

Android has exactly one VPN slot per user/profile, and the client exposes one
tunnel:

* `start` tears down any existing tunnel first (`stopTunnel(superseded)` closes
  the old fd and emits `stopped`/`superseded`) before the new
  `startForegroundService` call, so only one TUN and one fd ever exist.
* The service itself also refuses to keep an old interface: a second
  `onStartCommand` releases the previous interface before establishing.
* `onRevoke` (another VPN app connected, or the user disconnected EasyTier from
  system settings) emits `stopped`/`revoked` so Dart can force the UI out of
  "connected". The native side also removes the notification and resets the
  tile.
* `START_NOT_STICKY`: a killed service is never resurrected from a null intent
  (the fd ownership chain would be lost). The UI reconciles via `status()`.

## Notification contract

Ported from the Tauri client's "one ongoing notification per app" contract:

* Channel id `easytier_channel_v2` (the legacy `easytier_channel` is deleted),
  notification id `1355`, both defined only in `VpnNotification.kt`. The Flutter
  app has a single foreground service, so no second ongoing notification can
  exist; `updateNotification` updates the FGS notification in place.
* Copy (values / values-zh-rCN): `EasyTier · Connected` /
  `Network idle · Tunnel active` / `Running in background · Tunnel active`,
  actions `Open` and `Disconnect`. Plain text on purpose — notification text is
  single-typeface, so in-app ET Mono cannot apply to the rate fields.
* Live rates: Dart pushes `updateNotification(rxBps, txBps, connected)` (the
  shell should throttle to ~1 Hz). `connected` keeps `↑ tx · ↓ rx` visible on an
  idle-but-connected tunnel.
* Watchdog: if no sample arrives for 15 s (engine timers throttled in the
  background), the notification switches to the static background sentence
  instead of showing frozen numbers.
* The `Disconnect` action is a `PendingIntent.getService` with
  `ACTION_DISCONNECT`; the service tears down the tunnel without opening the
  app.

## Quick-settings tile

`EasyTierVpnTileService` derives the action from live state
(`EasyTierVpnService.isRunning()`), persists it as a pending action, and:

* if the app is in the foreground and Dart is listening → emits `tileAction`,
  Dart runs the normal consent → start/stop path;
* otherwise → opens the app, which drains the pending action through the
  `consumeTileAction` method.

The tile only shows optimistic state when the action was actually delivered.

## Build

Flutter commands must run through the repository wrapper (podman toolchain):

```bash
bash /home/chance/Projects/.flutter-run.sh \
  /home/chance/Projects/easytier/easytier-flutter build apk --split-per-abi
```

The Rust core is a cdylib loaded by the FFI bridge; build it with the NDK and
place it in the app's `jniLibs` (see `easytier-flutter/tool/build_native.sh`
and `lib/core/client/ffi/README.md` owned by the Rust bridge task):

```bash
cargo ndk -t arm64-v8a -t armeabi-v7a -t x86_64 -t x86 \
  -o easytier-flutter/android/app/src/main/jniLibs \
  build --release -p easytier-ffi
```

The Gradle side was verified in this environment (the image turned out to have
usable SDK licences; the task brief assumed otherwise):

```bash
# inside the flutter toolchain image, in easytier-flutter/android
./gradlew :app:compileDebugKotlin   # Kotlin compiles
./gradlew :app:assembleDebug        # manifest merge + resources + APK packaging
# -> easytier-flutter/build/app/outputs/flutter-apk/app-debug.apk
```

That APK does **not** include the Rust core yet, and no install/run was
possible (no device or emulator), so runtime behaviour is unverified. Target
levels are Flutter 3.47 defaults: `minSdk 24`, `compileSdk 36`, `targetSdk 36`.

## What must be verified on a real device

1. **Consent + fd flow**: fresh install → connect → system VPN consent dialog →
   tunnel up, `set_tun_fd` succeeds, traffic flows both ways (ping a peer,
   webserver).
2. **Notification**: visible in the shade, live `↑/↓` rates, `Disconnect` action
   works without opening the app, channel name/importance correct, no duplicate
   notifications when reconnecting, silent/low importance (no sound/vibration).
3. **POST_NOTIFICATIONS** (Android 13+): deny → tunnel still starts, UI shows
   the warning; grant later → notification appears.
4. **Revoke**: connect another VPN app while EasyTier is up → EasyTier
   notification disappears, Dart receives `stopped(revoked)`, the UI leaves
   "connected", and no fd is leaked.
5. **Single tunnel**: start a second network while connected → first tunnel is
   torn down, only one notification, fd count stable across N reconnects
   (`adb shell ls /proc/<pid>/fd | wc -l`).
6. **Quick-settings tile**: start/stop from the tile with the app foreground;
   background tap opens the app and drains the pending action; tile state and
   label updates; long-press opens the app.
7. **Activity destroy / engine restart while connected**: reopen the app →
   `status()` reports running and the core keeps its earlier fd; stopping from
   the new engine still tears down cleanly. Also swipe-away while connecting.
8. **Background start**: connect while the app is backgrounded → expect a clean
   `vpn_start_failed` (no crash); foregrounding then connecting works.
9. **MTU / routes**: MTU 1300 survives large transfers (adjust down if
   fragmentation appears), routed CIDRs (proxy CIDRs / exit node), DNS server
   pushed to the system resolver.
10. **IPv6**: the default `fd00::1/128` tunnel address is accepted and does not
    break IPv4-only networks.
11. **Own-package exclusion**: the app's own sockets bypass the tunnel
    (`addDisallowedApplication(packageName)`), so peer connections and RPC do not
    loop; verify the core can still reach peers while connected.
12. **Android 14/15 FGS**: `specialUse` start from the tile/notification paths
    does not throw `ForegroundServiceStartNotAllowedException`.

## Known risks

* **Foreground-service type (Play policy / targetSdk 36).** `specialUse` is the
  only fit for a user-initiated VPN (there is no VPN FGS type; `dataSync` is
  semantically wrong and time-limited on Android 15). Play review requires
  declaring the subtype/justification — the manifest property is already there.
* **Background FGS start restrictions** (targetSdk 31+): silently regressed
  behaviour is possible on OEM builds; the Dart layer must treat
  `vpn_start_failed` as "bring the app forward and retry", not as a crash.
* **fd lifetime race on teardown.** Closing the fd while the core still polls it
  produces EBADF logs; that is expected during shutdown and is why the core
  instance should be stopped around `disconnect()`. If the core is left running
  after a `revoked`, it will keep retrying a dead interface until stopped.
* **`detachFd` means no PFD finalizer safety net**: every future teardown path
  must route through `releaseTunnel` or fds leak silently.
* **Notification icon** is a vector drawable; verify it renders as an alpha mask
  on API 24–26 devices.

## Building the APK with the real Rust core

`flutter build apk` alone produces a UI-only APK: the Dart side defaults to
`MockCoreClient` and no `libeasytier_ffi.so` is bundled. To ship the working
client, build the cdylib and bundle it per ABI:

```bash
# ARM64 (device) — NDK r28, Rust with aarch64-linux-android target, protoc
ANDROID_NDK_HOME=$ANDROID_HOME/ndk/28.2.13676358 \
  easytier-flutter/tool/build_android.sh

# -> easytier-flutter/build/app/outputs/flutter-apk/app-release.apk
```

The script builds `easytier-ffi` for `aarch64-linux-android` (with the NDK
clang driver and bionic sysroot for bindgen), copies the cdylib into
`android/app/src/main/jniLibs/arm64-v8a/`, and runs
`flutter build apk --target-platform android-arm64 --dart-define=EASYTIER_USE_FFI=true`.
The jniLibs directory is git-ignored: always rebuild it for the target ABI.
The release variant currently uses the debug signing config, so these APKs are
internal-test builds only.

