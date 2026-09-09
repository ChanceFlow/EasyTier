# EasyTier Agent Guidelines

## Release & Versioning Conventions

- **Prerelease Tags**: For internal or test prereleases, follow the `-chance.N` convention (e.g. `v2.6.4-chance.1`, `v2.6.4-chance.2`, `v2.6.4-chance.3`, etc.).
- **Increment Strategy**: When building and pushing new test releases, increment the number (`chance++`).
- **Remotes & CI Architecture**:
  - Gitea (`http://10.100.0.1:3000/ChanceFlow/easytier.git`) is the primary local forge.
  - GitHub fork (`https://github.com/ChanceFlow/EasyTier.git`) handles cross-platform multi-runner CI builds (Windows, macOS DMG, Linux AppImage/deb/rpm, Android APKs).
  - Artifacts can be monitored and downloaded automatically using `python3 scripts/monitor_and_download.py [tag]`.
  - Downloaded release artifacts are stored in `./release-artifacts/` (which is git-ignored).
