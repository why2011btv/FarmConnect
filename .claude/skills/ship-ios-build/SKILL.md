---
name: ship-ios-build
description: >
  How to ship a FarmConnect iOS build through Xcode Cloud to App Store Connect, and how to fix
  "Prepare Build for App Store Connect failed". Use whenever pushing an iOS change that must build,
  or when an Xcode Cloud build fails at the "Prepare Build for App Store Connect" step.
---

# Shipping a FarmConnect iOS build

## The two facts that cause almost every wasted hour here

1. **Xcode Cloud builds from the `farmconnect` remote, NOT `origin`.**
   - `farmconnect` → `github.com/why2011btv/FarmConnect.git` (this is what builds)
   - `origin` → `github.com/why2011btv/farm-alert-pwa.git` (a decoy — pushing here builds nothing)

   Always: `git push farmconnect main` then verify `git rev-parse farmconnect/main` equals local `main`.
   Do not trust the push command's echo alone.

2. **"Preparing build for App Store Connect failed" = the build number is stale.**
   It means `CFBundleVersion` is not higher than a build already accepted for the same marketing
   version (`CFBundleShortVersionString`). It is a version-number rejection — NOT icons, entitlements,
   privacy manifest, or the `ci_scripts` location. Do not go theorizing from the generic message.

## How the build number is set

- `FarmConnect/Info.plist`: `CFBundleVersion = $(CURRENT_PROJECT_VERSION)`, `CFBundleShortVersionString = $(MARKETING_VERSION)`.
- `project.yml` holds the literals; `xcodegen generate` writes them into `FarmConnect.xcodeproj/project.pbxproj`.
- `ci_scripts/ci_post_clone.sh` (next to the `.xcodeproj` — the correct location, leave it) overwrites
  `CURRENT_PROJECT_VERSION` with `CI_BUILD_NUMBER` (the Xcode Cloud run number) at build time.

## To fix a "Prepare Build … failed" / to cut a new build

1. **Ask the user for the next build number** (they can read it off Xcode Cloud / App Store Connect).
   The already-accepted build numbers are not visible from git, so do not deduce it — ask.
2. Set it in `communication-platform/ios-app/project.yml`:
   `CURRENT_PROJECT_VERSION: "<n>"`
3. `cd communication-platform/ios-app && xcodegen generate`
4. Sanity build: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project FarmConnect.xcodeproj -scheme FarmConnect -destination 'generic/platform=iOS Simulator' -configuration Release build`
   then confirm the built `FarmConnect.app/Info.plist` reports the expected `CFBundleVersion`.
5. Commit, `git push farmconnect main`, verify `git rev-parse farmconnect/main`.

## Do NOT

- Hand-set `CURRENT_PROJECT_VERSION` ABOVE the Xcode Cloud run counter. It poisons the version space:
  a `max(literal, CI_BUILD_NUMBER)` floor above the counter makes consecutive builds collide on the
  floor value and every one after the first is rejected as a duplicate.
- Add a second `ci_scripts` at the repo root. The existing one is correctly placed.
- Propose a non-build-number cause without the specific `ITMS-####` code (from the "App Store Connect
  Operation Error" email, or by expanding the failed step in Xcode Cloud).

## Escaping a genuinely poisoned version space

If `1.0.0`'s build numbers are burned above the run counter, bump `MARKETING_VERSION` (e.g. `1.0.1`)
to start a fresh build-number train — but confirm with the user first, since it changes the
user-visible version.
