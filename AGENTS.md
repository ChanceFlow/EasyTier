# EasyTier Agent Guidelines

## Release & Versioning Conventions

- **Prerelease Tags**: For internal or test prereleases, follow the `-chance.N` convention (e.g. `v2.6.4-chance.1`, `v2.6.4-chance.2`, `v2.6.4-chance.3`, etc.).
- **Increment Strategy**: When building and pushing new test releases, increment the number (`chance++`).
- **Remotes & CI Architecture**:
  - Gitea (`http://10.100.0.1:3000/ChanceFlow/easytier.git`) is the primary local forge.
  - GitHub fork (`https://github.com/ChanceFlow/EasyTier.git`) handles cross-platform multi-runner CI builds (Windows, macOS DMG, Linux AppImage/deb/rpm, Android APKs).
  - Artifacts can be monitored and downloaded automatically using `python3 scripts/monitor_and_download.py [tag]`.
  - GitHub suppresses Actions for forks of high-usage upstreams (fork-scale policy). Release builds therefore run on the non-fork mirror `ChanceFlow/easytier-build`; the Gitea `github-bridge.yml` syncs `main` + tags there and `mirror-github-release.yml` copies the resulting release assets back to Gitea.
  - Downloaded release artifacts are stored in `./release-artifacts/` (which is git-ignored).

## Client architecture

- **New client work goes to `easytier-flutter/`** (Flutter; Android, Linux, Windows, macOS, iOS). Flutter commands in this environment must run through the podman toolchain wrapper, e.g. `bash /home/chance/Projects/.flutter-run.sh /home/chance/Projects/easytier/easytier-flutter analyze` (same for `test`, `run`, `build`). The wrapper mounts `/home/chance/Projects`, keeps a persistent pub cache in `.pub-cache/`, and runs the `flutter-3.47-android:latest` image with host networking.
- **`easytier-gui/` (Tauri 2 + Vue 3 + Vuetify) is deprecated — maintenance only.** Accepted there: security, data-loss, crash and build/toolchain fixes. Features, new platforms and redesigns belong in `easytier-flutter/`. The crate stays in the Cargo workspace until the release pipeline is migrated; see `easytier-gui/DEPRECATED.md`.
- **The Flutter client is Google Material 3**: seeded M3 colour (`ColorScheme.fromSeed`, Google blue), **system fonts** (platform UI font + platform monospace; no bundled text fonts), Material Symbols icons, M3 components. The written spec is `design-system/easytier-flutter/MASTER.md` (v5, Material 3 + Expressive layer). Do not reintroduce the old custom "Instrument" visual language into client work.
- **The web console is separate and not deprecated.** `easytier-web/frontend-lib` and `design-system/easytier/` (Vue) are still current for the web console; they simply no longer govern the client. Client UI follows `design-system/easytier-flutter/`.
- **This repo is a fork.** `upstream` (github.com/EasyTier/EasyTier) ships a Tauri GUI, so future upstream GUI changes cannot be merged — only core and other non-GUI changes can. Keep client-specific code out of crates upstream owns. Rationale and consequences: `docs/adr/0001-flutter-client.md`.
