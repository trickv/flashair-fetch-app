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
- **TestFlight / App Store:** Apple has to grant the capability on
  the bundle ID at the **Apple Developer Portal → Certificates,
  Identifiers & Profiles → Identifiers → `com.flashairsync` →
  Capabilities → Hotspot Configuration**. Then regenerate
  provisioning profiles.
- **Heads-up from the README:** Apple has historically denied this
  capability for hobby apps. **Request it early** — before you've
  invested too much in the iOS path — to fail fast if denied.

### Sentry telemetry default

The app's telemetry is **default ON** for beta testers (commit
`dfa3885`). Disclose this in your TestFlight release notes:

> This beta sends anonymous crash reports and sync metrics (file
> counts, durations, success/failure) to help us improve the app. No
> photo content, no filenames, no personal information. Toggle off
> at any time via Settings → Privacy.

If you want the App Store / general public version to default OFF
instead, flip the binding `?? true` → `?? false` and the
`!= false` check → `== true` in `Utils/Telemetry.swift` and
`Features/Settings/SettingsView.swift` before that release.

### What testers' Sentry events look like

You'll see events tagged:

- `environment: debug` for Debug builds (default for sideload/dev)
- `environment: release` for TestFlight / App Store builds
- `release: com.flashairsync@<version>+<build>`

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

Before submitting a build:

- [ ] **Team set** in Xcode → Signing & Capabilities (`DEVELOPMENT_TEAM`
      is intentionally not committed in `project.yml`).
- [ ] **Hotspot Configuration** capability enabled on the App ID in
      the developer portal.
- [ ] **Privacy strings** in `Info.plist` (XcodeGen-generated from
      `project.yml`):
  - `NSPhotoLibraryAddUsageDescription`
  - `NSPhotoLibraryUsageDescription`
  - `NSLocalNetworkUsageDescription`
- [ ] **Cleartext HTTP exception**:
      `NSAppTransportSecurity.NSAllowsLocalNetworking` in `Info.plist`.
- [ ] **Sentry DSN** is committed in `Info.plist` (`SentryDSN` key,
      populated via `project.yml` `info.properties`) — **public per
      Sentry docs, safe to commit**.
- [ ] Bump `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in
      `project.yml` `targets.FlashAirSync.settings`.
- [ ] Run `xcodegen generate`.
- [ ] **Build Archive** (Product → Archive) — verify the
      `postBuildScripts` git-commit-hash injection ran (visible in
      Settings → About after install).
- [ ] Smoke-test against the local mock server in the Simulator.
- [ ] Smoke-test against the real card on the device.
- [ ] Upload via Xcode Organizer.

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
  improve the app. No photo content, no filenames, no personal info.
- Toggle off via Settings → Privacy at any time.

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
- Team ID lives in your Xcode project settings; not committed in
  these docs to keep team IDs out of grep.

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

- `README.md` "Quick Start" — initial build setup
- `CLAUDE.md` "Local-environment Constraints" — XcodeGen, cleartext,
  signing notes
- `docs/REAL-WORLD-FINDINGS.md` — what beta testers will encounter
- `docs/PARITY.md` — iOS / Android feature mirror status
