# App Store readiness — open items

Found during the 2026-08-20 review. **None of these are fixed yet** — deferred deliberately.
Ordered by how likely each is to actually stop a release.

---

## 1. Missing privacy manifest — blocks upload

There is no `PrivacyInfo.xcprivacy` in the app target. `UserDefaults` is a "required reason API"
and is used in three files (`SessionStore`, `VineyardBlockLayoutStore`, `PushNotificationManager`).
Uploads without a manifest draw `ITMS-91053: Missing API declaration`.

**Fix:** add `FarmConnect/PrivacyInfo.xcprivacy` declaring
`NSPrivacyAccessedAPICategoryUserDefaults` with reason code `CA92.1` (access to app's own
defaults), plus the collected-data types (email address, coarse location, user content) linked to
the user. Add it to `project.yml` sources so xcodegen keeps it.

---

## 2. App Review cannot get past the access-code wall — near-certain 2.1 rejection

The app is login-gated *and* farm-gated. A reviewer signing up with a fresh account lands on
`AccessCodeView` and stops there — no sensors, no map, nothing to review.

**Fix:** in App Store Connect → App Review Information, supply
- a demo account (email + password), and
- an access code from the inventory batch, ideally on a farm with nodes that are actually
  reporting, so the reviewer sees live data rather than an empty list.

A code with `maxUses` left open is fine; revoke it after approval.

---

## 3. Purpose strings describe features that no longer exist

The feed / map / posts tabs were removed (`FeedView`, `MapFeedView`, `NewPostView` are never
instantiated), but `project.yml` still ships:

| Key | Current text | Reality |
|---|---|---|
| `NSLocationWhenInUseUsageDescription` | "show local farm posts on the map" | used by notification preferences |
| `NSPhotoLibraryUsageDescription` | "upload images in posts" | assistant chat uses `PhotosPicker` |
| `NSPhotoLibraryAddUsageDescription` | "save generated media" | no save path in shipped UI |
| `NSCameraUsageDescription` | "take photos for posts" | **camera never used** |

Inaccurate purpose strings are a 5.1.1 issue.

**Fix:** rewrite location and photo strings to match real usage. Drop the camera entry entirely.
`PhotosPicker` is out-of-process and needs no photo-library permission at all, so
`NSPhotoLibraryUsageDescription` can likely go too — verify before removing.

---

## 4. Fabricated agronomy presented as analysis

`VineyardDemoData.generalInsights` hardcodes claims such as *"5 of 8 canopy blocks are in the
low-risk band; Blocks 4 and 6 are moderate. Block 3 is high—prioritize scouting and spray timing
there."* In the sample layout these read as real findings about the viewer's vineyard.

Now that the sample layout is staff-only this is much less exposed, but the strings still ship.

**Fix:** either derive these from `VineyardCanopyAnalytics` like the per-block insights already
are, or label them unmistakably as sample content.

---

## 5. Sample vineyard geometry is a real property

`VineyardDemoData.defaultRectangles` holds nine coordinates around `41.6846, -71.0010` traced from
satellite imagery of the vineyard used as the demo subject. The name was removed in `77c91d1`;
the parcel outline was not.

**Fix:** replace with fictional coordinates if the demo is kept.

---

## 6. Dead code ships in the binary

`FeedView`, `MapFeedView`, `NewPostView` are never instantiated. They also drag in the location and
photo permissions above.

**Fix:** delete, or move behind a compile flag.

---

## 7. Unit tests are not built by CI

`FarmConnectTests` was removed from `project.yml` while restoring the Xcode Cloud configuration,
because the shipping project has only ever contained the app target. The suite had also stopped
compiling (`XCTAssertEqual(_:_:accuracy:)` on optionals).

As of 2026-08-20 the suite compiles and **all 27 tests pass**. Re-adding the target is safe once an
App Store build is confirmed green — do it as its own change so a build failure is unambiguous.

---

## Already satisfied

- Account deletion in-app (Guideline 5.1.1(v)) — `DELETE /v1/auth/account`
- `ITSAppUsesNonExemptEncryption = false`
- No third-party sign-in, so Sign in with Apple is not required
- `DEVELOPMENT_TEAM`, app icons, and a valid `CFBundleVersion` restored
- Multi-tenancy: a customer can only ever read their own farm's devices
