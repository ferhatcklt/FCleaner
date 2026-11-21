## What does this change?

## Safety checklist
- [ ] All deletions go through `Trasher.remove`
- [ ] New scan results use `CleanableItem(url:size:base:)` with the lowest defensible base level
- [ ] `SafetyPolicy` changes have tests
- [ ] `swift test` passes
- [ ] `CHANGELOG.md` updated under **Unreleased**
