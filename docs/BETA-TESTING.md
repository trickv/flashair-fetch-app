# Beta Testing Playbook

Practical setup for distributing FlashAir Sync to beta testers via
TestFlight (iOS) and Internal Sharing / Play Console (Android,
pending). Captures the things you need to disclose and the things
you need to configure that aren't obvious from the code.

## What changes when you go wider than your own device

### Hotspot Configuration entitlement (iOS)

The iOS app uses `NEHotspotConfiguration` to join the FlashAir's
Wi-Fi. This is gated by the
`com.apple.developer.networking.HotspotConfiguration` entitlement
(declared in
`ios/FlashAirSync/FlashAirSync/FlashAirSync.entitlements`).

- **Development on your registered device:** works as soon as the
  entitlement is in the file (already there).
- **TestFlight / App Store:** tick the capability on the bundle ID at
  the **Apple Developer Portal → Certificates, Identifiers & Profiles
  → Identifiers → `us.v9n.flashair-sync` → Capabilities → Hotspot**,
  then regenerate the provisioning profile.
- **Correction (2026-08-13):** this doc used to say Apple has to
  "grant" the capability and "has historically denied it for hobby
  apps." That is **wrong**.
  `com.apple.developer.networking.HotspotConfiguration` is an
  *unmanaged* entitlement — a self-serve checkbox available to any
  paid Apple Developer Program membership, with no request form and
  no approval wait. The denial story belongs to `NEHotspotHelper`
  (`…networking.HotspotHelper`) and to
  `…networking.multicast`, both of which are request-gated and
  neither of which this app uses. See
  `docs/APP-STORE-RELEASE.md` step 2 for the click path and for the
  confidence caveat on this claim.

### Sentry telemetry default

The app's telemetry is **default ON** for beta testers (commit
`dfa3885`). Disclose this in your TestFlight release notes:

> This beta sends anonymous crash reports and sync metrics (file
> counts, durations, success/failure) to help us improve the app. No
> photo content and no personal information; if an individual file
> fails to download, its filename is included so the failure is
> actionable. Toggle off at any time via Settings → Privacy.

**Do not claim "no filenames."** `SyncEngine`'s per-file failure path
logs `entry.name` (which `Logger.log` bridges to a Sentry breadcrumb)
and captures `file` / `path` as event extras. Filenames genuinely do
reach Sentry on failures — `PRIVACY.md` says so, and the tester-facing
notes have to match.

If you want the App Store / general public version to default OFF
instead, flip the binding `?? true` → `?? false` and the
`!= false` check → `== true` in `Utils/Telemetry.swift` and
`Features/Settings/SettingsView.swift` before that release.

### What testers' Sentry events look like

You'll see events tagged:

- `environment: debug` for Debug builds (default for sideload/dev)
- `environment: release` for TestFlight / App Store builds
- `release: us.v9n.flashair-sync@<version>+<build>`

Filter by `environment:release` in Sentry to focus on real beta
testers vs. your own dev builds.

## Privacy defaults

Default Sentry config (`Utils/Telemetry.swift`):

| Setting | Value | Why |
|---|---|---|
| `sendDefaultPii` | `false` | No IP/user info captured |
| `attachScreenshot` | `false` | Could capture photo previews mid-sync |
| `attachViewHierarchy` | `false` | Less invasive but unnecessary |
| `sessionReplay.*SampleRate` | `0` | Records UI screens — too invasive for a photo app |
| `tracesSampleRate` | `0.2` | Lightweight HTTP timing only |
| Profiling | not configured (off) | Performance overhead not justified |

Even with these defaults, Sentry's backend infers user geo (city
level) from IP. If that's a no-go for your beta release, layer in a
`beforeSend` hook in `Telemetry.start` that strips geo fields before
the event is sent.

## iOS pre-submission checklist

Before submitting a build. **Note the release is now automated** — see
`docs/APP-STORE-RELEASE.md`; you tag and publish a GitHub Release, and
CI signs, archives and uploads to TestFlight.

- [ ] **Team set** in Xcode → Signing & Capabilities for *local device*
      builds (`DEVELOPMENT_TEAM` is intentionally not committed in
      `project.yml`). CI doesn't need this — fastlane writes the team
      from the `APPLE_TEAM_ID` secret.
- [ ] **Hotspot** capability enabled on the App ID
      (`us.v9n.flashair-sync`) in the developer portal, and present in
      the downloaded profile (`security cms -D -i … | plutil -extract
      Entitlements xml1 -o - -`).
- [ ] **Privacy strings** in `Info.plist` (XcodeGen-generated from
      `project.yml`):
  - `NSPhotoLibraryAddUsageDescription`
  - `NSLocalNetworkUsageDescription`
  - **Not** `NSPhotoLibraryUsageDescription` — `PhotoSaver` only ever
    *adds* (`.addOnly`), and advertising full library read access
    invites a 5.1.1 question at review. Drop it if it's still in
    `project.yml`.
- [ ] **Cleartext HTTP exception**:
      `NSAppTransportSecurity.NSAllowsLocalNetworking` in `Info.plist`.
- [ ] **Sentry DSN** is committed in `Info.plist` (`SentryDSN` key,
      populated via `project.yml` `info.properties`) — **public per
      Sentry docs, safe to commit**.
- [ ] **Do NOT hand-bump `MARKETING_VERSION` /
      `CURRENT_PROJECT_VERSION`.** The release pipeline derives the
      marketing version from the git tag and the build number from
      `GITHUB_RUN_NUMBER`; the values in `project.yml` are a fallback
      for local builds only.
- [ ] Run `xcodegen generate` and commit
      `ios/FlashAirSync/FlashAirSync/Info.plist` if it changed —
      otherwise CI regenerates it, the tree goes dirty, and every
      shipped build is stamped `GitCommitHash = <sha>-dirty`.
- [ ] Smoke-test against the local mock server in the Simulator.
- [ ] Smoke-test against the real card on the device.
- [ ] **Ship it:** `git tag vX.Y.Z && git push origin vX.Y.Z`, then
      publish a GitHub Release — that's what triggers the build and
      the TestFlight upload. Xcode Organizer is no longer part of the
      path. Full walkthrough in `docs/APP-STORE-RELEASE.md`.
- [ ] After install, verify the `postBuildScripts` git-commit-hash
      injection landed (Settings → About).

## What to put in TestFlight release notes

A template:

```
What's new in this build
- Sync your FlashAir SD card to your iOS Photos library
- Smart dedupe — only new photos sync each time
- "Files per sync" cap in Settings → Performance for trying things on a big card

Known limitations
- Requires iOS 16+
- Don't lock the screen during sync (will resume in a later build)
- The "FlashAir wants to join Wi-Fi" prompt appears every sync — tap Join
- iOS may pop "FlashAir has no internet — switch?" mid-sync — tap Stay
- Long syncs (full card) take ~10 minutes — keep the app open

Privacy
- Anonymous crash reports and sync metrics are sent to Sentry to help us
  improve the app. No photo content and no personal info. If a file fails
  to download, its filename is included so we can chase the bug.
- Toggle off via Settings → Privacy at any time.
- Full policy: https://github.com/trickv/flashair-fetch-app/blob/main/PRIVACY.md

Troubleshooting
- If sync fails with "request timed out": your camera may have gone to sleep.
  Wake it with a shutter half-press and try again.
- If "Unable to join the network 'flashair'": make sure the card is broadcasting
  (camera on, Wi-Fi mode enabled in the camera menu).
```

## Required iOS version

iOS 16.0+ (per `project.yml` `IPHONEOS_DEPLOYMENT_TARGET`).
`ShareLink` and the `.fontWeight(_:)` view modifier in `SettingsView`
need 16+. Don't try to bump down to iOS 15 without gating those
calls.

## Required Apple Developer account

- **Paid Apple Developer Program account** required for the Hotspot
  entitlement to provision (see above). Personal/free Apple IDs
  cannot generate provisioning profiles that include this
  entitlement.
- The team ID now lives in `fastlane/Appfile` (and in the
  `APPLE_TEAM_ID` repo secret) rather than only in local Xcode
  settings — `DEVELOPMENT_TEAM` is still deliberately absent from
  `project.yml`.

## Android (when it's ready for beta)

The Android side isn't yet at beta-ready quality (M2 not validated
end-to-end). When it gets there:

- **Sentry telemetry** should be wired with the same defaults and
  same opt-in toggle (mirror `Utils/Telemetry.swift`).
- **No Hotspot entitlement equivalent** — Android uses runtime
  permissions only (`NEARBY_WIFI_DEVICES` API 33+,
  `ACCESS_FINE_LOCATION` 29–32). No portal capability to request.
- **`ImportService` foreground service** needs to land before any
  long-sync beta — Android 8+ background limits will kill imports
  >15 seconds otherwise. Already mentioned as a planned component in
  `README.md`; not yet implemented.
- **Play Console internal testing track** for initial distribution.

## See also

- `docs/APP-STORE-RELEASE.md` — one-time Apple/GitHub setup, the
  automated release path, and App Store submission
- `PRIVACY.md` — the published privacy policy (required URL for
  TestFlight external testing and App Store submission)
- `README.md` "Quick Start" — initial build setup
- `CLAUDE.md` "Local-environment Constraints" — XcodeGen, cleartext,
  signing notes
- `docs/REAL-WORLD-FINDINGS.md` — what beta testers will encounter
- `docs/PARITY.md` — iOS / Android feature mirror status
