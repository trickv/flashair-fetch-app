# iOS / Android Parity Checklist

What iOS has that Android needs to mirror (and vice versa). The
project's design philosophy is **shared core logic mirrored between
iOS and Android, with only platform glue diverging**. This file is
the living checklist — when iOS or Android lands a feature, mark it
here so the other side knows what's outstanding.

Status legend: ✅ done on both · 🍎 iOS only · 🤖 Android only ·
⏳ in progress · 🔴 missing on both.

## Core data flow

| Component | iOS | Android | Notes |
|---|---|---|---|
| `FlashAirClient` (CSV listing + downloads) | ✅ validated on mock + real card | ✅ validated only on mock listing | Same code shape on both. |
| Recursive `/DCIM` walker | ✅ tolerates Toshiba `100__TSB` + `EOSMISC` + `MISC` siblings | ✅ same (name-agnostic walker) | Comments in `MediaStoreWriter.kt:62` still reference `100CANON` — illustrative only, no code change needed. |
| `SyncIndex` (`path#size` keyed JSON) | ✅ persists to `Documents/FlashAirSync/sync_index_<ssid>.json` | ✅ persists to `filesDir/sync_index_<ssid>.json` | iOS location is user-visible in Files.app; both have monotonic-growth issue. |
| FAT date/time decode | ✅ — but **lacks range validation** the Kotlin side has | ✅ has range validation | iOS deferred fix. |
| Dedupe `path#size` semantics | ✅ proven across 170-file run + back-to-back syncs | ⏳ inherited from iOS proof | Strategy verified at scale; Android just needs to run it. |
| `maxFilesPerSync` per-sync cap | ✅ Settings stepper, `0 = "All"` | 🔴 missing | Android: add `Int?` field to settings, same `0 → "All"` Stepper UX. |
| `alreadySyncedCount` in result UI | ✅ "Already synced: N files" in completion alert | 🔴 missing | Android: thread `allEntries.count - newEntries.count` through to the result UI. |

## Platform glue (where divergence is intentional)

| Concern | iOS implementation | Android implementation | Notes |
|---|---|---|---|
| Wi-Fi join | `NEHotspotConfiguration` (Hotspot Configuration entitlement; paid Apple Developer account required for provisioning) | `WifiNetworkSpecifier` + `bindProcessToNetwork` (`NEARBY_WIFI_DEVICES` Android 13+ / `ACCESS_FINE_LOCATION` 10–12) | Both prompt user per session. |
| Wi-Fi teardown | `removeConfiguration(forSSID:)` in `ImportViewModel`'s post-sync block | `unregisterNetworkCallback` in `WiFiConnector` | iOS validated; Android unverified. |
| Cleartext HTTP | `NSAppTransportSecurity.NSAllowsLocalNetworking = true` in `project.yml` `info.properties` | `network_security_config.xml` whitelist (`10.0.2.2`, `192.168.x.x`) | Both required; neither removable. |
| Save to library | `PHAssetCreationRequest.addResource(with: .photo, fileURL:)` + `PHAssetResourceCreationOptions(originalFilename:)` | `MediaStore.Images.Media.EXTERNAL_CONTENT_URI` + `DISPLAY_NAME` + `RELATIVE_PATH = Pictures/FlashAirImport/` | iOS has `originalFilename` wired (`db4da3b`); Android needs to verify `DISPLAY_NAME` gets the source filename. |
| Dedicated import album | 🔴 missing — imports go into the main library (sorted by FAT capture date) | ✅ `Pictures/FlashAirImport/` already does this | iOS deferred — track in TODO. |
| Source attribution | ✅ "Saved from FlashAir Sync" shown automatically in Photos.app Info | Implicit via the `Pictures/FlashAirImport/` folder | No code work needed either side. |
| Post-sync source preservation through cloud | ✅ `originalFilename` syncs through iCloud to other Apple devices | Verify MediaStore→Google Photos preserves `DISPLAY_NAME` | Required for Immich/Google Photos/iCloud dedupe-by-name. |

## Observability

| Concern | iOS | Android | Notes |
|---|---|---|---|
| In-process logger | ✅ `Logger.shared` (actor, 1000-entry ring buffer, exportable via Settings → View Logs) | ✅ similar in `Log.d` / file-based logger | OK as-is. |
| Crash + error telemetry | ✅ Sentry Cocoa SDK 9.16.1 wired, opt-in default-on via Settings → Privacy. `Utils/Telemetry.swift` thin wrapper. Bridges `Logger.shared` calls as breadcrumbs. | 🔴 missing | **Android: add `sentry-android` with the same wrapper pattern.** DSN is in `Info.plist` on iOS via `project.yml`; Android can hardcode in `build.gradle.kts` `resValue` or read from `BuildConfig`. |
| `sync_completed` event with aggregate metrics | ✅ emitted in `ImportViewModel.startImport` success path | 🔴 missing | Same payload shape: total/imported/alreadySynced/skipped/failed counts, total_bytes, duration_seconds, throughput_mbps. |
| Privacy hardening (no replay, no PII, no screenshots) | ✅ locked in `Telemetry.start` | (apply same when wiring sentry-android) | Critical for a photo app. |

## UX

| Concern | iOS | Android | Notes |
|---|---|---|---|
| Inline navigation title | ✅ `.navigationBarTitleDisplayMode(.inline)` so "FlashAir Sync" doesn't overlap the 80pt Wi-Fi icon | (verify) | iOS fixed in `f593aac`. |
| Build info in Settings (commit + date) | ✅ `postBuildScripts` injects `GitCommitHash` + `BuildDate` into bundle Info.plist; Settings → About displays both | ✅ git hash via `resValue` in `R.string.git_commit_id`; build date not currently shown | Android: add build date to mirror. |
| Auto-scroll import list to active row | 🔴 missing — for 100+ file runs the live row scrolls off-screen | 🔴 missing | `ScrollViewReader` + reverse list order; do once, mirror. |
| Last-imported thumbnail preview | 🔴 missing | 🔴 missing | Real-shoot feedback — small thumbnail of most recent save, glanceable mid-shoot. |
| "Live shooting mode" (stay-connected polling) | 🔴 missing | 🔴 missing | Real-shoot feedback — useful during active shoots; both platforms. |
| Retry-with-coachmark on "card not found" | 🔴 missing | 🔴 missing | M3 item; both. |

## M3 backgrounding (the big shared problem)

| Aspect | iOS plan | Android plan |
|---|---|---|
| Mid-sync app suspension | `URLSessionConfiguration.background(withIdentifier:)` + `UIRequiresPersistentWiFi` in Info.plist + coachmark (deferred until feasibility deep-dive) | `ImportService` foreground service (`README.md` already mentions; not yet implemented) |
| Long-sync power management | Same `UIRequiresPersistentWiFi` keeps Wi-Fi radio alive | Foreground service notification keeps the OS from killing the process |
| Mid-sync OS prompts | Connection Assistant "no internet — switch?" prompt; suppression unknown | Wi-Fi auto-switch behavior; verify equivalent prompt |
| User instruction | Coachmark "Keep the app open during sync" | Same coachmark, plus foreground notification |

**Tackle as one project across both platforms** — same logical
problem, same UX requirements, and the design decisions for one
inform the other.

## Real-hardware validation status

| Sync stage | iOS (Toshiba FlashAir + Canon T5i) | Android |
|---|---|---|
| Hotspot entitlement provisions on-device | ✅ verified under a paid Apple Developer team | n/a — `WifiNetworkSpecifier` uses runtime permissions, no portal entitlement |
| Wi-Fi join succeeds | ✅ | 🔴 untested |
| `/DCIM` walks the Toshiba `100__TSB` layout | ✅ | 🔴 untested |
| Cleartext HTTP downloads | ✅ | 🔴 untested |
| Save to library with original filename + EXIF | ✅ (`db4da3b`) | 🔴 untested |
| Post-sync Wi-Fi teardown returns to home Wi-Fi | ✅ | 🔴 untested |
| Dedupe at scale (170-file re-sync) | ✅ (`170 already synced, 0 new`) | 🔴 untested |
| Full-card stress sync | ✅ (170 / 0 failures / ~9m39s) | 🔴 untested |

The iOS validation gives us very high confidence the protocol +
strategy are correct. **Android's gap is *only* the platform glue
path** (Wi-Fi binding, MediaStore write). Validate against the mock
first (close the `op=104` CI regression while you're there), then
real hardware.

## See also

- `docs/REAL-WORLD-FINDINGS.md` — what real hardware taught us
- `docs/BETA-TESTING.md` — distribution + privacy setup
- `TODO.md` — concrete backlog with effort estimates
- `CLAUDE.md` "Where to Pick Up" — per-platform next-step pointers
