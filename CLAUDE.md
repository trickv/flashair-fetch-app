# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Status

This is a vibe-coded, partially-tested cross-platform app for pulling photos/videos off Toshiba FlashAir SD cards. **M1 verified, M2 drafted but not validated end-to-end.** The full M2 Android stack (`WiFiConnector`, `MediaStoreWriter`, `SyncEngine`, progress UI, retry, debug/release variants) is merged on `main` and the Android build + unit tests pass on CI, but only the M1 directory-listing path has actually been run against the mock server on an emulator. M3 (resilience) and M4 (polish/WebDAV) are not started.

The iOS app is scaffolded but has never been opened in Xcode. Nothing has been tested against real FlashAir hardware — only the Python mock server in `tools/mock-flashair/`.

**Known regression on `main` as of 2026-05-18:** the mock-server CI job `Test config endpoint` (`op=104`) fails after M2's edits to `tools/mock-flashair/server.py`. Android build/test are unaffected. See `DEVELOPMENT.md` for the "Next Steps" punch list.

See `README.md` and `DEVELOPMENT.md` for the running roadmap; `SESSION-2025-01-18.md` is a historical session log (predates the M2 merge).

## Repository Layout

- `android/` — Kotlin + Jetpack Compose app. Real code lives under `app/src/main/java/com/flashairsync/`.
- `ios/FlashAirSync/` — Swift + SwiftUI app (untested).
- `tools/mock-flashair/server.py` — Flask server that mimics the FlashAir HTTP API.
- `shared-spec/` — Protocol docs: `API.md`, `CSV-FORMAT.md`, `DEDUPE-STRATEGY.md`.
- `.github/workflows/ci.yml` — CI: Android build+test, mock-server smoke test, lint (lint is `continue-on-error`).

## Commands

### Android
```bash
cd android
./gradlew assembleDebug          # Build debug APK
./gradlew installDebug           # Install to connected device/emulator
./gradlew test                   # Unit tests (JUnit, no device needed)
./gradlew connectedAndroidTest   # Instrumentation tests (needs device)
./gradlew lint                   # Lint (warnings only at M1)
```
Single test: `./gradlew test --tests "com.flashairsync.core.ModelsTest.decodesFatDateTime"`

### Mock server
```bash
cd tools/mock-flashair
pip install flask
python server.py    # listens on 0.0.0.0:8080
python test_server.py   # validates server against the API spec
```

### iOS (not yet validated)
```bash
cd ios/FlashAirSync && open FlashAirSync.xcodeproj
xcodebuild test -scheme FlashAirSync -destination 'platform=iOS Simulator,name=iPhone 15'
```

## Local-environment Constraints (important)

- **Gradle does not run locally** in this dev environment — the corporate proxy requires JWT auth that Gradle's HTTP client doesn't handle (curl works fine). Build/test verification happens on GitHub Actions. Don't waste a turn trying to run `./gradlew` locally; push and read CI instead. The `.claude/skills/ci-build-reader.md` skill describes how to pull CI status/logs via the GitHub API with `curl`.
- **Android Studio bundled JDK is fragile**: `buildConfigField()` triggers `JdkImageTransform`/`jlink` failures on the snap-installed Android Studio. Use `resValue()` for build-time values instead — that's how the git commit hash is plumbed into the app (`android/app/build.gradle.kts` → `R.string.git_commit_id`).
- **Cleartext HTTP is required** to reach both the emulator host and FlashAir cards. The whitelist lives in `android/app/src/main/res/xml/network_security_config.xml` (`10.0.2.2`, `192.168.x.x`). Don't remove it.
- **Emulator → host**: use `10.0.2.2`, not `localhost`. Real FlashAir is typically `192.168.0.1`.

## Toolchain Versions (do not casually bump)

- Gradle 8.2 / AGP 8.0.2 / Kotlin 1.8.10 / Compose Compiler 1.4.3 / JDK 17 / compileSdk 34 / minSdk 29.
- AGP 8.2+ has not been tested and may reintroduce the jlink issue above.

## Architecture

The design assumes **shared core logic mirrored between iOS and Android, with only platform glue diverging**. When adding to one platform, mirror to the other (or note explicitly that you're not).

### Core (both platforms)
- `FlashAirClient` — HTTP client that calls `command.cgi?op=100&DIR=…`, parses CSV directory listings. Files use FAT-encoded date/time fields:
  - FAT date: `(year-1980) << 9 | month << 5 | day`
  - FAT time: `hour << 11 | minute << 5 | (second/2)`
  - Decoder: `android/app/src/main/java/com/flashairsync/core/Models.kt` (`decodeFATDateTime`)
- `SyncEngine` — recursive walker + download orchestrator. Drafted in `core/SyncEngine.kt`; wires `FlashAirClient` + `SyncIndex` + `MediaStoreWriter` together and emits progress to the Compose UI. Unvalidated end-to-end.
- `SyncIndex` — persistent dedupe state. Key is **`path#size`**, deliberately not timestamp (FAT has 2s granularity) and not filename alone. See `shared-spec/DEDUPE-STRATEGY.md` for the rationale.

### Platform glue
- iOS: `WiFiJoiner` (NEHotspotConfiguration), `PhotoSaver` (PHPhotoLibrary). All untested.
- Android:
  - `WiFiConnector` — `WifiNetworkSpecifier` + per-network binding, permission flow for `NEARBY_WIFI_DEVICES` (API 33+) / `ACCESS_FINE_LOCATION` (29–32). Drafted, never run against a real network.
  - `MediaStoreWriter` — writes to `Pictures/FlashAirImport/` via `MediaStore`.
  - `ImportService` is mentioned in `README.md` / `CONTRIBUTING.md` as a planned Foreground Service for long imports (Android 8+ background limits would kill them otherwise); **no such file exists yet** — the M2 draft runs sync from `MainActivity` coroutines, which is fine for short jobs but will need promoting to a Foreground Service before M3.

### Android build variants
- `debug` build → mock server: `flashair_host = http://10.0.2.2:8080`, `flashair_ssid = flashair-mock`, `use_mock_server = true`. Code paths that read `use_mock_server` skip the WiFi join, so the debug app talks straight to the emulator's host loopback.
- `release` build → real FlashAir: `flashair_host = http://192.168.0.1`, `flashair_ssid = flashair`, `use_mock_server = false`.
- These are wired via `resValue(...)` inside `buildTypes { debug { ... } release { ... } }` in `android/app/build.gradle.kts`. Same `resValue`-not-`buildConfigField` rationale as the git-hash story above.

### FlashAir protocol gotchas
- CSV API (`op=100`) is supported on all card models — that's the primary path. WebDAV is W-03/W-04 only and is optional/future.
- FlashAir networks have **no internet**; OS-level "no internet" banners and captive-portal flows are expected and must be tolerated, not "fixed."
- `/DCIM` usually contains only camera-vendor subdirectories (e.g. `100CANON`); photos are one level deeper. A listing showing "1 directory, 0 files" at `/DCIM` is correct, not a bug.

## Where to Pick Up

M2 Android code is on disk but unproven. The cheapest next slice is to **validate it against the mock server in the debug variant** and **fix the `op=104` mock-server regression** so CI goes green. After that: real-hardware validation, then M3 (resilience: retries with backoff, cancellation, durable `SyncIndex`). iOS still needs first-ever Xcode validation. See `DEVELOPMENT.md` "Next Steps" for the punch list.

## Branch / history note

The repo previously lived on a long Claude-generated branch name with no `main`. On 2026-05-18 the M1 default branch was merged with the side branch `claude/m2-android-development-…` and the result was promoted to `main`; both `claude/*` branches were deleted. Going forward there is one branch — work directly on `main`.
