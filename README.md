<p align="center"><img src="Resources/AppIcon.png" width="140" alt="FCleaner icon"></p>

<h1 align="center">FCleaner</h1>

<p align="center">
  <b>A free, open-source Mac cleaner that refuses to break your system.</b><br>
  No paywalls, no "upgrade to Pro", no telemetry.
</p>

<p align="center">
  <a href="https://github.com/ferhatcklt/FCleaner/actions/workflows/ci.yml"><img src="https://github.com/ferhatcklt/FCleaner/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/ferhatcklt/FCleaner/releases/latest"><img src="https://img.shields.io/github/v/release/ferhatcklt/FCleaner?include_prereleases" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="macOS 14+">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green" alt="MIT license"></a>
</p>

<p align="center"><a href="README.tr.md">Türkçe</a></p>

> The interface is currently in Turkish. English localization is on the [roadmap](#roadmap).

## Features

**Cleanup**
- **Flash Clean**: one click removes only items marked *Recommended* (caches, logs, build artifacts).
- **System Junk**: app caches, logs, Xcode / npm / Gradle / pip leftovers, iOS Simulator devices, iOS update files, old installers, Mail attachments, iOS backups, Trash.
- **Large Files** and **Duplicates** (SHA-256 content match; one copy is always kept).
- **Deletion History**: everything FCleaner removed, with one-click restore from the Trash.

**Apps**
- **Uninstaller**: removes an app with all of its traces in `~/Library` and `/Library`: support files, caches, preferences, containers, saved state, launch agents/daemons, privileged helpers, crash reports, temp caches. It never touches data that belongs to another installed app.
- **Startup Items**: third-party launch agents and daemons.

**Toolkit**
- **Memory**: what is using your RAM (per app, helpers grouped), memory pressure, swap. *Free RAM* clears the file cache, optionally quits apps you choose, and reports exactly what was freed and what was closed.
- **Disk Analyzer**: expandable folder tree with sizes, percentages and keyboard navigation.
- **Shredder**: overwrite-then-delete for files you drop on it.
- **Maintenance**: Time Machine local snapshots, flush DNS, reindex Spotlight, rebuild Launch Services, reset Quick Look / font caches, restart Dock / Finder.
- **Menu bar monitor**: disk and RAM at a glance, Flash Clean from the menu bar.
- **Self-updating** from GitHub Releases, with code-signature verification.

## Safety model

Every file is classified before anything can be deleted:

| Level | Examples | Behavior |
|---|---|---|
| 🟢 **Recommended** | caches, logs, build artifacts | Pre-selected; the only thing Flash Clean removes |
| 🟠 **Review** | downloads, large files, app data | Must be selected by hand |
| 🔒 **Critical** | Keychain, iCloud Drive, iPhone backups, Messages, Mail, Photos, browser profiles, password managers, crypto wallets, SSH/GPG keys, Apple app data, and any folder that contains one of these | **Locked.** Cannot be selected or deleted until you unlock with Touch ID or your Mac password; relocks after 5 minutes |

On top of that, system locations (`/System`, `/usr`, `/Library` itself, `~/Documents`, whole disks, other users' homes, …) can **never** be deleted, even when unlocked. You can also add your own folders to an **exclusion list** (Settings → Excluded), and FCleaner will neither show nor delete them.

- Everything except the Shredder and emptying the Trash goes **to the Trash**, so it can be undone.
- Every deletion asks for confirmation and is recorded in Deletion History.
- Admin tasks use macOS's own password prompt; FCleaner never sees your password.
- The only network request is the update check against GitHub (can be turned off).

All rules live in one file, [`Services/Safety.swift`](Sources/FCleaner/Services/Safety.swift), and every deletion goes through a single function, `Trasher.remove` in [`Services/FileSystem.swift`](Sources/FCleaner/Services/FileSystem.swift). Both are covered by tests.

## Install

Download the latest `FCleaner-x.y.z.zip` from [Releases](https://github.com/ferhatcklt/FCleaner/releases/latest), unzip it and move **FCleaner.app** to your Applications folder.

> Builds are not notarized yet. On first launch, right-click the app and choose **Open**. If macOS still blocks it, open **System Settings → Privacy & Security** and click **Open Anyway**.

For full functionality, grant **Full Disk Access**: the Overview page has a *Quick Setup* button that opens the right settings pane and lets you drag FCleaner into the list.

## Build from source

Requires macOS 14+ and Xcode 16+.

```bash
git clone https://github.com/ferhatcklt/FCleaner.git
cd FCleaner
./scripts/build-app.sh      # → build/FCleaner.app
swift test                  # run the test suite
```

`build-app.sh` signs the app with the first *Apple Development* identity in your keychain (so Full Disk Access survives rebuilds), or ad-hoc if none is found. Override with `SIGN_IDENTITY=<hash>`.

## Project layout

```
Sources/FCleaner/
├── App/        entry point, sidebar, settings keys
├── Models/     view models
├── Services/   scanners, safety policy, Trasher, history, updater, memory monitor
└── Views/      SwiftUI screens and shared components
Tests/FCleanerTests/   one file per area (safety, trasher, app scanner, history, …)
scripts/        build-app.sh, release.sh, make-icon.swift
```

## Roadmap

- [ ] English localization
- [ ] Notarized releases (Developer ID)
- [ ] Browser privacy cleanup (history, cookies) with per-browser safeguards
- [ ] Sunburst view in the Disk Analyzer
- [ ] iOS companion app: photo, video and contact cleanup

## Contributing

Bug reports and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md). Please report security issues privately as described in [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE) © 2026 [FCApps](https://fcapps.com.tr) and FCleaner contributors
