# Contributing to FlashAir Sync

Thank you for your interest in contributing! This guide will help you get started.

## Development Setup

### Prerequisites

**For iOS Development:**
- macOS 12.0+
- Xcode 14.0+
- Swift 5.7+

**For Android Development:**
- Android Studio Hedgehog (2023.1.1)+
- JDK 17+
- Android SDK 29-34

**For Mock Server:**
- Python 3.8+
- Flask 2.0+

### Initial Setup

1. **Clone the repository:**
   ```bash
   git clone https://github.com/trickv/flashair-fetch-app.git
   cd flashair-fetch-app
   ```

2. **Start the mock server:**
   ```bash
   cd tools/mock-flashair
   pip install flask
   python server.py
   ```

3. **iOS Setup:**
   ```bash
   cd ios/FlashAirSync
   open FlashAirSync.xcodeproj
   ```

4. **Android Setup:**
   ```bash
   cd android
   ./gradlew build
   # Or open in Android Studio
   ```

## Code Style

### Swift (iOS)

- Use SwiftLint with default rules
- Follow Apple's Swift API Design Guidelines
- Prefer value types (structs) over reference types (classes)
- Use `async/await` for asynchronous operations
- Document public APIs with triple-slash comments (`///`)

**Example:**
```swift
/// Downloads a file from the FlashAir card
/// - Parameters:
///   - path: Absolute path on the card (e.g., "/DCIM/100CANON/IMG_0001.JPG")
///   - progress: Optional callback for download progress (0.0-1.0)
/// - Returns: Local file URL of the downloaded file
func downloadFile(path: String, progress: ((Double) -> Void)?) async throws -> URL {
    // Implementation
}
```

### Kotlin (Android)

- Follow official Kotlin coding conventions
- Use ktlint for formatting
- Prefer Kotlin coroutines over callbacks
- Use sealed classes for state/result types
- Document public APIs with KDoc (`/** */`)

**Example:**
```kotlin
/**
 * Downloads a file from the FlashAir card
 * @param path Absolute path on the card (e.g., "/DCIM/100CANON/IMG_0001.JPG")
 * @param onProgress Optional callback for download progress (0.0-1.0)
 * @return Local file URI of the downloaded file
 */
suspend fun downloadFile(path: String, onProgress: ((Float) -> Unit)? = null): Uri {
    // Implementation
}
```

## Project Organization

### Shared Concepts (Both Platforms)

All core logic should be mirrored between iOS and Android:

- **Models**: `DirectoryEntry`, `SyncState`, `ImportResult`
- **Client**: `FlashAirClient` (CSV parsing, HTTP requests)
- **Engine**: `SyncEngine` (walk, dedupe, download orchestration)
- **Index**: `SyncIndex` (persistence of sync state)

### Platform-Specific Code

Only platform integration should differ:

- **iOS**: `WiFiJoiner`, `PhotoSaver`
- **Android**: `WiFiConnector`, `MediaStoreWriter`, `ImportService`

## Testing

### Unit Tests

**iOS (XCTest):**
```bash
cd ios/FlashAirSync
xcodebuild test -scheme FlashAirSync -destination 'platform=iOS Simulator,name=iPhone 15'
```

**Android (JUnit):**
```bash
cd android
./gradlew test
```

**Required Test Coverage:**
- CSV parsing (valid, malformed, directory detection)
- Dedupe logic (seen files, new files, changed files)
- Path sanitization
- Error handling

### Integration Tests

Use the mock server for end-to-end testing:

1. Start mock server with test data
2. Configure app to use `http://localhost:8080`
3. Run sync and verify:
   - Correct file count detected
   - Files saved to media library
   - Re-sync imports 0 files
   - Adding new file imports exactly 1

### Manual Testing Checklist

Before submitting a PR, verify:

- [ ] App builds without warnings on both platforms
- [ ] Unit tests pass (iOS & Android)
- [ ] Mock server integration test passes
- [ ] UI displays correctly in light & dark mode
- [ ] Settings persist across app restarts
- [ ] Cancel operation works mid-sync
- [ ] Error states show actionable messages

## Pull Request Process

1. **Create a feature branch:**
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make your changes:**
   - Write tests first (TDD preferred)
   - Implement the feature
   - Update documentation if needed

3. **Verify quality:**
   ```bash
   # iOS
   xcodebuild test -scheme FlashAirSync

   # Android
   ./gradlew test lint
   ```

4. **Commit with clear messages:**
   ```bash
   git commit -m "Add support for WebDAV directory listing"
   ```

5. **Push and create PR:**
   ```bash
   git push origin feature/your-feature-name
   # Create PR on GitHub
   ```

6. **PR Requirements:**
   - Description explains what/why
   - Tests included for new features
   - No merge conflicts with main
   - CI passes (builds + tests)
   - Code review approved

## Commit Message Format

Use conventional commits:

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation only
- `style`: Formatting (no code change)
- `refactor`: Code restructure (no behavior change)
- `test`: Adding tests
- `chore`: Build process, dependencies

**Examples:**
```
feat(ios): add WebDAV directory listing support

Implements WebDAV PROPFIND requests for W-03/W-04 cards.
Falls back to CSV API if WebDAV not available.

Closes #42
```

```
fix(android): correct network binding on API 29-30

WifiNetworkSpecifier behaves differently on Android 10-11.
Now uses ConnectivityManager.requestNetwork callback.

Fixes #58
```

## Architecture Decisions

### Why CSV First, WebDAV Optional?

All FlashAir models support CSV API (`command.cgi?op=100`), but only W-03/W-04 support WebDAV. CSV ensures universal compatibility.

### Why `path#size` Dedupe Key?

- **FAT timestamps** have 2-second granularity → unreliable for change detection
- **Filename alone** insufficient (same name, different content)
- **Path + size** catches 99% of duplicates; false negatives rare (edited file, same size)
- Future: optional SHA-256 hash for paranoid mode

### Why Foreground Service (Android)?

Background execution limits on Android 8+ would kill long imports. Foreground Service with notification ensures reliable completion.

### Why No Background Transfers (iOS)?

`URLSession` background tasks require internet connectivity verification. FlashAir has no internet, so background transfers would fail silently.

## Adding a New Feature

### Example: Add File Size Filter

1. **Update Models:**
   ```swift
   // iOS: Core/Models.swift
   struct SyncSettings {
       var maxFileSizeMB: Int = 500
   }
   ```

2. **Modify Engine:**
   ```swift
   // iOS: Core/SyncEngine.swift
   func shouldImport(_ entry: DirectoryEntry) -> Bool {
       let sizeMB = entry.size / (1024 * 1024)
       return sizeMB <= settings.maxFileSizeMB
   }
   ```

3. **Add Settings UI:**
   ```swift
   // iOS: Features/Settings/SettingsView.swift
   Stepper("Max File Size: \(maxFileSizeMB) MB", value: $maxFileSizeMB, in: 10...2000)
   ```

4. **Mirror in Android:**
   ```kotlin
   // Android: core/Models.kt
   data class SyncSettings(val maxFileSizeMB: Int = 500)
   ```

5. **Add Tests:**
   ```swift
   func testFileSizeFilter() {
       let largeFile = DirectoryEntry(size: 600_000_000) // 600 MB
       XCTAssertFalse(engine.shouldImport(largeFile))
   }
   ```

6. **Update Docs:**
   - README.md (feature list)
   - shared-spec/DEDUPE-STRATEGY.md (if logic changed)

## Release Process

1. Update version in:
   - `ios/FlashAirSync/Info.plist` (CFBundleShortVersionString)
   - `android/app/build.gradle.kts` (versionName)

2. Update CHANGELOG.md with release notes

3. Create release tag:
   ```bash
   git tag -a v1.0.0 -m "Release 1.0.0"
   git push origin v1.0.0
   ```

4. CI builds and uploads artifacts

## Getting Help

- **Questions**: Open a GitHub Discussion
- **Bugs**: File a GitHub Issue with logs + reproduction steps
- **Security**: Email directly (see SECURITY.md)

## Code of Conduct

- Be respectful and inclusive
- Provide constructive feedback
- Focus on the best technical solution
- Welcome newcomers

Thank you for contributing! 🚀
