# Contributing to FCleaner

Thanks for helping! Issues and pull requests are welcome in English or Turkish.

## Getting started

```bash
git clone https://github.com/ferhatcklt/FCleaner.git
cd FCleaner
swift build && swift test
./scripts/build-app.sh && open build/FCleaner.app
```

Requires macOS 14+ and Xcode 16+.

## Ground rules

1. **Safety first.** Every deletion must go through `Trasher.remove` (`Sources/FCleaner/Services/FileSystem.swift`). Never call `FileManager.removeItem`, `NSWorkspace.recycle` or shell `rm` anywhere else.
2. **Classify, don't assume.** New scan results must be built as `CleanableItem(url:size:base:)` so `SafetyPolicy` can raise their level. Pick the lowest `base` level you can defend: `.safe` only for data the system regenerates on its own.
3. **Changes to `SafetyPolicy` need tests.** Add a case to `Tests/FCleanerTests/SafetyPolicyTests.swift` for every path you allow or forbid.
4. **Default to the Trash.** Permanent deletion is reserved for the Trash itself, the Shredder and `simctl`.
5. **No network calls** besides the existing update check.

## Adding a junk category

1. Add a case to `JunkCategory.Kind` with its `baseSafety`, `title`, `icon` and `detail` (`Models/Models.swift`).
2. Return its items from `JunkScanner.items(for:)` (`Services/JunkScanner.swift`).
3. Run the app and check that the safety badges look right.

## Pull requests

- Keep PRs focused; one feature or fix per PR.
- Make sure `swift test` passes (CI runs it on every PR).
- Follow the existing style: SwiftUI + `@Observable`, comments explain *why*, user-facing strings in Turkish until localization lands.
- Update `CHANGELOG.md` under **Unreleased**.
