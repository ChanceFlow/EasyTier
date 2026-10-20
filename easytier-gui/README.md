# GUI for EasyTier

> **Deprecated — maintenance only.** This Tauri 2 + Vue 3 client is frozen: no new
> features, platforms or redesigns; only security, data-loss, crash and
> build-breakage fixes are accepted. The replacement is the Flutter client in
> [`easytier-flutter/`](../easytier-flutter/). See
> [`DEPRECATED.md`](DEPRECATED.md) for the feature-parity table, the migration
> checklist and the upstream consequences, and
> [`docs/adr/0001-flutter-client.md`](../docs/adr/0001-flutter-client.md) for the
> decision record.

this is a GUI implementation for EasyTier, based on Tauri2.

## Compile

### Install prerequisites

```
apt install npm
npm install -g pnpm
```

### For Desktop (Win/Mac/Linux)

```
cd ../tauri-plugin-vpnservice
pnpm install
pnpm build

cd ../easytier-web/frontend-lib
pnpm install
pnpm build

cd ../../easytier-gui
pnpm install
pnpm tauri build
```

### For Android

Need to install android SDK / emulator / NDK / Java (easy with android studio)

```
# For ArchLinux
sudo pacman -Sy sdkmanager
sudo sdkmanager --install platform-tools platforms\;android-34 ndk\;r26 build-tools
export PATH=/opt/android-sdk/platform-tools:$PATH
export ANDROID_HOME=/opt/android-sdk/
export NDK_HOME=/opt/android-sdk/ndk/26.0.10792818/
rustup target add aarch64-linux-android

install java 20
```

Java version depend on gradle version specified in (easytier-gui\src-tauri\gen\android\build.gradle.kts)

See [Gradle compatibility matrix](https://docs.gradle.org/current/userguide/compatibility.html) for detail .

```
pnpm install
pnpm tauri android init
pnpm tauri android build
```
