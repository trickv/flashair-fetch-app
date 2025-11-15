# FlashAir Sync

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
- Xcode 14.0+
- iOS 15.0+ deployment target
- macOS 12.0+ (for development)

**Build Instructions:**
```bash
cd ios/FlashAirSync
open FlashAirSync.xcodeproj
# Build and run on simulator or device (Cmd+R)
```

**Permissions:**
- Hotspot Configuration (joins FlashAir Wi-Fi)
- Photo Library (saves imported media)

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

- [x] **M1**: Project setup, connect & list `/DCIM`
- [ ] **M2**: Incremental import + media save + progress UI
- [ ] **M3**: Resilience (retries, cancellation, state persistence)
- [ ] **M4**: Polish (settings, logs export, optional WebDAV)

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
