# Changelog

All notable changes to this project are documented here. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed
- Copyright holder is now FCApps; the About window shows "© 2026 FCApps".

## [0.1.0] - 2026-11-21

First public release.

### Added
- Overview with disk and memory usage, Flash Clean and Full Disk Access quick setup (drag-and-drop helper).
- System Junk: app caches, logs, developer leftovers, iOS Simulator devices (removed via `simctl`), iOS updates, installers, Mail attachments, iOS backups, Trash.
- Large Files and Duplicates with size / name / date sorting.
- Deletion History with restore from the Trash.
- App Uninstaller that finds leftovers in user and system libraries, helper tools and temp caches, without touching other installed apps' data.
- Startup Items.
- Memory page: RAM breakdown, memory pressure, per-app usage, Free RAM with optional app quitting and a report of what was freed and closed.
- Disk Analyzer with an expandable tree, Shredder, Maintenance tools and Time Machine local snapshots.
- Safety model: Recommended / Review / Critical levels, Touch ID lock for critical data, forbidden system paths, user exclusion list.
- Menu bar monitor.
- Self-updater using GitHub Releases with Team ID signature verification.

[Unreleased]: https://github.com/ferhatcklt/FCleaner/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/ferhatcklt/FCleaner/releases/tag/v0.1.0
