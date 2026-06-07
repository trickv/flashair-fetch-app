# FlashAir Sync

> [!WARNING]
> **⚠️ VIBE-CODED PROJECT - iOS validated, Android pending ⚠️**
>
> This project was generated through AI-assisted development ("vibe coding"). The codebase is **partially tested** and should still be considered **experimental**.
>
> **Current Status (Updated 2026-06-05):**
> - ✅ **iOS:** Full M2 sync path **validated end-to-end against real Toshiba FlashAir hardware** (2026-05-29). Full-card stress test on 2026-05-31: **170 files / 0 failures / ~9m39s** at ~10.6 Mbps. Dedupe-at-scale verified by a back-to-back re-sync ("170 already synced, 0 new"). Original filenames preserved into Photos (Immich-friendly). Opt-in Sentry telemetry default-on for the beta. See `docs/REAL-WORLD-FINDINGS.md` for detail.
> - ⚠️ **Android:** M2 stack (`WiFiConnector`, `MediaStoreWriter`, `SyncEngine`, progress UI, retry, debug/release variants) is merged on `main` and CI is green, but only the **M1 directory-listing path** has been run on the emulator. Real-hardware validation pending. iOS validation gives high confidence the core protocol/strategy is right — the gap is platform glue only.
> - ⚠️ **Mock-server CI regression:** the `op=104` config-endpoint test fails after M2's `server.py` edits. Android build/test still pass.
> - ⚠️ **M3 (resilience):** not started — see `TODO.md`.
>
> **Use at your own risk.** Expect bugs and breaking changes.
> See `DEVELOPMENT.md` for build instructions; `docs/PARITY.md` for the iOS↔Android mirror checklist; `TODO.md` for the active backlog.

A robust, cross-platform mobile application for importing photos and videos from Toshiba FlashAir SD cards to iOS and Android devices.

## Features

- **Automatic Wi-Fi Connection**: Seamlessly join FlashAir card networks
- **Incremental Sync**: Only downloads new media files (smart deduplication)
- **Media Library Integration**: Automatically adds files to Photos (iOS) or MediaStore (Android)
- **Resilient UX**: Handles "no internet" Wi-Fi, connection drops, and background constraints
- **Progress Tracking**: Real-time per-file status and cancellation support
- **Configurable**: Customizable SSID, host, file filters, and sync settings

## Supported File Types

JPG, JPEG, PNG, HEIC, MP4, MOV

## Project Structure

```
flashair-sync/
├── shared-spec/         # FlashAir HTTP API protocol documentation
├── tools/mock-flashair/ # Mock server for testing
├── ios/                 # iOS app (Swift/SwiftUI)
└── android/             # Android app (Kotlin/Jetpack Compose)
```

## Quick Start

### iOS App

**Requirements:**
- Xcode 26.5+ (older may work but is untested)
- iOS 16.0+ deployment target
- macOS 14.0+ (for development)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- For real-device installs: a **paid Apple Developer Program account** (needed for the Hotspot Configuration entitlement to provision; personal/free Apple IDs cannot)

**Build Instructions:**
The `.xcodeproj` is generated from `project.yml` and is **not** committed — regenerate after pulling and any `project.yml` change:

```bash
cd ios/FlashAirSync
xcodegen generate
open FlashAirSync.xcodeproj
# Set Team in Signing & Capabilities (intentionally blank in project.yml)
# Build and run on simulator or device (Cmd+R)
```

**Permissions:**
- Hotspot Configuration (joins FlashAir Wi-Fi)
- Photo Library (saves imported media)
- Local Network (reaches the card's `192.168.0.1`)

See `docs/BETA-TESTING.md` for the full pre-submission checklist
(release notes template, privacy defaults, entitlements, etc.).

### Android App

**Requirements:**
- Android Studio Hedgehog (2023.1.1)+
- Android SDK 29+ (Android 10+)
- Kotlin 1.9+

**Build Instructions:**
```bash
cd android
./gradlew assembleDebug
# Or open in Android Studio and run
```

**Permissions:**
- Nearby Wi-Fi Devices (Android 13+) or Fine Location (Android 10-12)
- Foreground Service (for long imports)

## Testing with Mock Server

The mock FlashAir server simulates the card's HTTP API for testing without hardware:

```bash
cd tools/mock-flashair
pip install flask
python server.py
# Server runs at http://localhost:8080
```

Configure the app to use `http://localhost:8080` (or your local machine IP from mobile devices).

## FlashAir Configuration

**Default Settings:**
- SSID: `flashair`
- Passphrase: `12345678`
- Host: `http://192.168.0.1`

Customize these in the app's Settings screen.

## How It Works

1. **Join Network**: App connects to FlashAir Wi-Fi (no internet expected)
2. **Scan DCIM**: Recursively lists all files under `/DCIM` via CSV API
3. **Deduplicate**: Compares against local sync index (`path#size` key)
4. **Download New Files**: Fetches only previously unseen media
5. **Save to Gallery**: Writes to Photos (iOS) or Pictures/FlashAirImport (Android)
6. **Persist State**: Updates sync index for next run

## Architecture

### Core Components

- **FlashAirClient**: HTTP client with CSV parser for `command.cgi?op=100`
- **SyncEngine**: Recursive directory walker and download orchestrator
- **SyncIndex**: Persistent dedupe state (`path#size → synced`)

### Platform Adapters

- **iOS**: `WiFiJoiner` (NEHotspotConfiguration), `PhotoSaver` (PHPhotoLibrary)
- **Android**: `WiFiConnector` (WifiNetworkSpecifier + network binding), `MediaStoreWriter`, `ImportService` (Foreground Service)

### View Layer

- **iOS**: SwiftUI with `ImportViewModel`
- **Android**: Jetpack Compose with `ImportViewModel` + StateFlow

## Development Roadmap

- [x] **M1**: Project setup, connect & list `/DCIM` (both platforms)
- [x] **M2** (iOS): Incremental import + media save + progress UI — **validated against real Toshiba FlashAir hardware 2026-05-29** including a 170-file stress test
- [~] **M2** (Android): code merged on `main` and CI green, but only the M1 listing path has been exercised on the emulator — mock + real-hardware validation pending
- [ ] **M3**: Resilience (retries with backoff, cancellation, background-safe long syncs) — see `TODO.md` and `docs/PARITY.md`
- [ ] **M4**: Polish (logs export, optional WebDAV, etc.)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for build instructions, code style, and PR guidelines.

## License

[MIT License](LICENSE) - See LICENSE file for details.

## Troubleshooting

**iOS: "No Internet Connection" Banner**
- This is expected behavior; FlashAir doesn't provide internet
- The app handles this gracefully

**Android: "Network not available"**
- Ensure you've granted location/Wi-Fi permissions
- Check that FlashAir card is powered on and in range

**Sync Says "0 files" on First Run**
- Verify SSID/passphrase/host in Settings
- Check that camera has photos on the FlashAir card
- Try the mock server to validate app functionality

## Support

For issues, feature requests, or questions:
- GitHub Issues: [trickv/flashair-fetch-app/issues](https://github.com/trickv/flashair-fetch-app/issues)
