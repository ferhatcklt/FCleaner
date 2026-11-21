# Security Policy

FCleaner deletes files, so bugs that let it remove something it should not are treated as security issues. That includes:

- deleting a path that `SafetyPolicy` should mark as forbidden or critical,
- bypassing the protection lock, the exclusion list or the confirmation dialogs,
- following a symlink, alias or mount point to data outside the selected item,
- the updater installing a build that is not signed by the project's developer team,
- anything that leaks user data off the machine.

## Reporting a vulnerability

Please **do not open a public issue**. Use GitHub's private reporting instead:
[Report a vulnerability](https://github.com/ferhatcklt/FCleaner/security/advisories/new).

Include the macOS version, the FCleaner version, the exact path(s) involved and steps to reproduce. You should get a reply within a week. Fixes are released as soon as possible and credited in the changelog unless you prefer otherwise.

## Supported versions

Only the latest release receives security fixes.
