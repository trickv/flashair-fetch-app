# Development Guide

## Current Status (M2: iOS mock-validated; Android mock listing only)

**Working / Verified:**
- ✅ Android app scaffold with Jetpack Compose UI
- ✅ FlashAirClient HTTP implementation with CSV parsing
- ✅ Mock FlashAir server for testing (M1 endpoints — see regression below)
- ✅ M1: Connect to FlashAir and list /DCIM directory (verified on emulator + mock)
- ✅ FAT datetime encoding/decoding
- ✅ Network security config for cleartext HTTP
- ✅ Git commit hash displayed in app footer
- ✅ Android build & unit tests green on CI

**Merged but Not Yet Validated End-to-End (M2):**
- ⚠️ `WiFiConnector` — Android 10+ `WifiNetworkSpecifier` + permission flows (code present, not exercised against a real network)
- ⚠️ `MediaStoreWriter` — writes to `Pictures/FlashAirImport/`
- ⚠️ `SyncEngine` — wires `FlashAirClient` + `SyncIndex` + `MediaStoreWriter` together with recursive walk, progress, retry-on-error
- ⚠️ Debug/release **build variants**: `debug` points at the mock server (`10.0.2.2:8080`) and skips the WiFi join; `release` points at the real FlashAir (`192.168.0.1`, SSID `flashair`). See `android/app/build.gradle.kts` `buildTypes`.

**Known Regressions on `main`:**
- ❌ Mock-server CI step `Test config endpoint` (`op=104`) fails after M2's `tools/mock-flashair/server.py` changes. Android build/test still pass.

**iOS — full sync validated against mock (2026-05-27), real Toshiba FlashAir hardware (2026-05-29), AND full-card stress test (2026-05-31):**
- ✅ First built & run on Xcode 26.5 (iOS 16 deployment target)
- ✅ Full M2 sync path end-to-end against the mock in the Simulator: recursive `/DCIM` walk → download → save to Photos → `path#size` dedupe → persisted `SyncIndex`, with a clean incremental re-sync (5 → 2 → 0 new files across three runs)
- ✅ `#if DEBUG` mock-server mode (`flashair-mock` / `localhost:8080`), `NSAllowsLocalNetworking` ATS exception, `WiFiJoiner` join+teardown wired into `ImportViewModel`
- ✅ **Real-hardware first runs** (2026-05-29): signed under a paid Apple Developer team, `NEHotspotConfiguration` joins and tears down cleanly, Toshiba camera subdir (`100__TSB`) walks fine, six unique photos (`IMG_8023`–`IMG_8028`) imported across three back-to-back `maxFilesPerSync=2` runs with three non-overlapping pairs.
- ✅ **Full-card stress test** (2026-05-31): **170 files / 0 failures over ~10 minutes** (~3.5s/file ≈ 13.6 Mbps effective), original filename preserved via `PHAssetResourceCreationOptions.originalFilename` (Immich/iCloud/Google Photos friendly), and an immediate re-sync correctly reported "170 already synced, 0 new" — dedupe-at-scale verified. Debugged live via `xcrun devicectl device process launch --console` over USB tether (tunnel survives the Wi-Fi handoff that breaks Wi-Fi-paired debugging).
- ⚠️ Imports land in the main Photos Library sorted by FAT capture date, not in a dedicated "FlashAir" album (deferred discoverability cleanup — see Next Steps).

**Not Yet Implemented:**
- M3 (resilience), M4 (settings, logs export, WebDAV)

## Quick Start

### Prerequisites
- Android Studio with JDK 17+
- Android SDK 34
- Python 3.7+ (for mock server)

### Build Android App
```bash
cd android
./gradlew assembleDebug
./gradlew installDebug  # Install to connected device/emulator
```

### Run Tests
```bash
cd android
./gradlew test          # Unit tests
./gradlew connectedAndroidTest  # Instrumentation tests (requires device)
```

### Start Mock FlashAir Server
```bash
cd tools/mock-flashair
python server.py
# Server runs on http://0.0.0.0:8080
```

### Test M1 on Emulator
1. Start Android emulator (API 29+)
2. Start mock server: `cd tools/mock-flashair && python server.py`
3. Install app: `cd android && ./gradlew installDebug`
4. Open app and tap "Connect & List /DCIM"
5. Should see: "Connected to FlashAir! Found in /DCIM: 1 directories, 0 files"

## Critical Technical Notes

### Android Network Configuration
**Issue:** Android 9+ blocks cleartext HTTP by default.

**Solution:** Network security config in `android/app/src/main/res/xml/network_security_config.xml`
- Allows HTTP for: `10.0.2.2` (emulator localhost), `192.168.x.x` (FlashAir IPs)
- Referenced in `AndroidManifest.xml` via `android:networkSecurityConfig`

### FAT Date/Time Encoding
**Critical for FlashAir CSV parsing:**

```kotlin
// FAT Date: (year_since_1980 << 9) | (month << 5) | day
val fatDate = 19764  // 2018-09-20 = (38 << 9) | (9 << 5) | 20

// FAT Time: (hour << 11) | (minute << 5) | (second/2)
val fatTime = 34560  // 16:56:00 = (16 << 11) | (56 << 5) | 0
```

See `android/app/src/main/java/com/flashairsync/core/Models.kt:decodeFATDateTime()`

### Git Commit ID in App
**Issue:** Using `buildConfigField()` caused JDK jlink errors with Android Studio's bundled JDK.

**Solution:** Use `resValue()` instead:
```kotlin
// In build.gradle.kts:
val gitCommitId = providers.exec {
    commandLine("git", "rev-parse", "--short", "HEAD")
}.standardOutput.asText.get().trim()
resValue("string", "git_commit_id", gitCommitId)

// In MainActivity.kt:
val gitCommitId = context.getString(R.string.git_commit_id)
```

### Gradle Version Compatibility
- **Gradle:** 8.2
- **AGP:** 8.0.2
- **Kotlin:** 1.8.10
- **Compose Compiler:** 1.4.3

⚠️ **Do not upgrade AGP to 8.2+** without testing - may cause compatibility issues.

### Emulator Networking
- `10.0.2.2` = Host machine's localhost (use this for mock server)
- Real FlashAir cards typically use `192.168.0.1` or similar
- Update `MainActivity.kt:54` host value as needed

## Project Structure

```
flashair-fetch-app/
├── android/                    # Android app (Kotlin + Jetpack Compose)
│   ├── app/
│   │   └── src/main/java/com/flashairsync/
│   │       ├── MainActivity.kt             # Main UI entry point (Compose, progress UI)
│   │       └── core/
│   │           ├── FlashAirClient.kt       # HTTP client for FlashAir API
│   │           ├── Models.kt               # Data models & FAT encoding
│   │           ├── SyncIndex.kt            # Deduplication state (path#size)
│   │           ├── WiFiConnector.kt        # WiFi joining (drafted, unvalidated)
│   │           ├── MediaStoreWriter.kt     # Save to Android gallery (drafted)
│   │           └── SyncEngine.kt           # Main sync logic (drafted)
│   └── app/src/test/java/                  # Unit tests
├── ios/                        # iOS app (Swift + SwiftUI) — validated against mock + real FlashAir hardware
├── tools/mock-flashair/        # Python Flask mock server
│   └── server.py
├── shared-spec/                # Documentation
│   ├── API.md                  # FlashAir HTTP API reference
│   ├── CSV-FORMAT.md           # CSV parsing specification
│   └── DEDUPE-STRATEGY.md      # Deduplication approach
└── .github/workflows/ci.yml    # CI pipeline
```

## Testing Strategy

### Unit Tests (Fast, No Device Required)
```bash
cd android && ./gradlew test
```
- CSV parsing tests
- FAT datetime encoding tests
- Model validation tests
- **Location:** `android/app/src/test/java/com/flashairsync/core/`

### Mock Server Validation (CI)
```bash
cd tools/mock-flashair
python test_server.py
```
- Validates mock server matches FlashAir API spec

### Manual Testing (Emulator)
1. Mock server testing (see Quick Start)
2. Real FlashAir card testing:
   - Join FlashAir network (SSID: "flashair")
   - Update `MainActivity.kt` host to FlashAir IP (usually `192.168.0.1`)
   - Test directory listing

### CI Pipeline (GitHub Actions)
- Runs on every push
- Android build & unit tests
- Mock server validation
- Lint checks (non-blocking for M1)

## Known Issues & Limitations

### Cannot Run Gradle Locally in Claude Code Environment
**Issue:** Gradle requires network access via proxy with JWT auth. Java doesn't handle this proxy configuration properly.

**Workaround:** Use GitHub Actions CI for builds and tests. CI runs quickly (~2 minutes).

### iOS App — Validated on Mock + Real FlashAir Hardware
The iOS full sync path is validated against the mock server in the Simulator (2026-05-27) and against a real Toshiba FlashAir card (2026-05-29). Signing uses a paid Apple Developer team so the Hotspot Configuration entitlement provisions on-device. See `CLAUDE.md` "Project Status" for detail.

### Lint Warnings
Lint is currently non-blocking in CI (M1 scaffold). Known warnings:
- Missing string translations
- Unused resources
- Will be cleaned up in later milestones

## Next Steps

Note: `shared-spec/MILESTONES.md` is referenced by older docs but does not exist — the roadmap lives in `README.md`.

The Android M2 code is merged but unexercised. The natural progression:

1. **Validate M2 end-to-end against the mock server (debug build)**
   - Build the `debug` variant; verify it picks up `flashair_host = http://10.0.2.2:8080` and `use_mock_server = true` (so it skips the WiFi join).
   - Run a sync from `MainActivity` and confirm files land in `Pictures/FlashAirImport/`.
   - Re-run; confirm `SyncIndex` dedupes to 0 new files.

2. **Fix the mock-server `op=104` regression** in `tools/mock-flashair/server.py` so CI goes green.

3. **Validate against real FlashAir hardware (release build)**
   - Use SSID `flashair`, host `http://192.168.0.1`. Permission flow for `NEARBY_WIFI_DEVICES` (Android 13+) or `ACCESS_FINE_LOCATION` (10–12) needs real-world testing.
   - Confirm the "no internet" banner is tolerated and the per-network binding actually routes traffic to the FlashAir.

4. **M3 work** — retries with backoff, cancellation, durable `SyncIndex` persistence across app restarts.

5. **iOS** — mock + real-hardware paths both validated (2026-05-27 / 2026-05-29). Next: **M3** (resilience: retry-with-backoff on transient timeouts like the card-powered-down case, cancellation, durable index across app restarts). Deferred cleanups:
   - **Backgrounding kills long syncs.** If the app loses foreground mid-sync (user switches apps, screen lock, memory pressure), `URLSession` downloads stall and the `NEHotspotConfiguration` Wi-Fi link can drop. Real-hardware syncs of large cards take 30+ minutes, so this matters. Likely fix: switch to `URLSessionConfiguration.background(withIdentifier:)` so the system resumes downloads across suspensions, set `UIRequiresPersistentWiFi` in Info.plist, plus a coachmark. iOS analog of Android's planned `ImportService` foreground-service.
   - **iOS Connection Assistant prompt** ("flashair has no internet, switch?") interrupts long syncs — evaluate `UIRequiresPersistentWiFi`, otherwise coachmark.
   - **Auto-scroll the import list to the active item** — `ScrollViewReader` + reverse list order. Currently for 100+ file runs the active row scrolls off-screen.
   - **Dedicated "FlashAir" album.** Imports go into the general Photos Library, not an album (Android: `Pictures/FlashAirImport/`).
   - **`SyncIndex` grows monotonically.** Files deleted on the card stay in the index forever (post-stress-test pull: 195 entries = 170 on-card + 25 stale). Multi-year card-rotation use case → index bloat. Fix at sync end: prune entries whose path wasn't in the current listing.
   - `downloadFile`'s `progress:` param is never invoked.
   - The Swift FAT decode lacks the Kotlin range validation.
   - The CSV parse tests are vacuous (`parseCSV` private — needs `@testable`/internal).
   - `SyncIndex` should move from `Documents/` to Application Support.
   - The import footer needs the mock-vs-real indicator + git hash.

## Development Tips

### Debugging Network Issues
```kotlin
// Add logging to FlashAirClient.kt:
println("Connecting to: $urlString")
println("Response code: ${connection.responseCode}")
println("Response body: ${responseBody}")
```

### Testing with Different Mock Data
Edit `tools/mock-flashair/server.py` to add/remove mock files in the `files` dictionary.

### Viewing CI Logs
- Go to: https://github.com/trickv/flashair-fetch-app/actions
- Click on latest run
- Click on failed job to see logs
- Look for actual error messages (don't guess!)

### Updating Build Version
The git commit hash is automatically embedded at build time. No manual updates needed - just rebuild and the footer will show the latest commit.

## References

- [FlashAir API Documentation](shared-spec/API.md)
- [CSV Format Specification](shared-spec/CSV-FORMAT.md)
- [Deduplication Strategy](shared-spec/DEDUPE-STRATEGY.md)
- [Android Jetpack Compose](https://developer.android.com/jetpack/compose)
- [Android Network Security Config](https://developer.android.com/training/articles/security-config)
