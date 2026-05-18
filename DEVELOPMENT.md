# Development Guide

## Current Status (M2 Drafted, Unvalidated)

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

**Not Yet Implemented:**
- iOS app (scaffolded but untested)
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
├── ios/                        # iOS app (Swift + SwiftUI) - UNTESTED
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

### iOS App Untested
The iOS app is fully scaffolded but has not been tested in Xcode. Should work based on Android implementation, but needs validation.

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

5. **iOS validation** — open in Xcode, build, mirror the Android changes (`WiFiJoiner` via `NEHotspotConfiguration`, `PhotoSaver` via `PHPhotoLibrary`).

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
