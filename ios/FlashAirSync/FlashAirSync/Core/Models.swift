import Foundation

// MARK: - Directory Entry

/// Represents a file or directory entry from FlashAir CSV listing
struct DirectoryEntry: Identifiable, Equatable {
    let id: String
    let directory: String
    let name: String
    let absolutePath: String
    let size: Int
    let attribute: Int
    let fatDate: Int
    let fatTime: Int
    let modifiedAt: Date?

    var isDirectory: Bool {
        (attribute & 0x10) != 0
    }

    var dedupeKey: String {
        "\(absolutePath)#\(size)"
    }

    init(directory: String, name: String, size: Int, attribute: Int, fatDate: Int, fatTime: Int) {
        self.directory = directory
        self.name = name
        self.size = size
        self.attribute = attribute
        self.fatDate = fatDate
        self.fatTime = fatTime

        // Build absolute path
        if directory.hasSuffix("/") {
            self.absolutePath = "\(directory)\(name)"
        } else {
            self.absolutePath = "\(directory)/\(name)"
        }

        self.id = self.absolutePath
        self.modifiedAt = Self.decodeFATDateTime(date: fatDate, time: fatTime)
    }

    /// Decode FAT date/time into Foundation Date
    static func decodeFATDateTime(date: Int, time: Int) -> Date? {
        guard date > 0 else { return nil }

        let year = ((date >> 9) & 0x7F) + 1980
        let month = (date >> 5) & 0x0F
        let day = date & 0x1F

        let hour = (time >> 11) & 0x1F
        let minute = (time >> 5) & 0x3F
        let second = (time & 0x1F) * 2

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second

        return Calendar.current.date(from: components)
    }
}

// MARK: - Sync Settings

/// User-configurable sync settings
struct SyncSettings: Codable {
    var ssid: String
    var passphrase: String
    var host: String
    var fileExtensions: [String]
    var concurrentDownloads: Int
    var maxFileSizeMB: Int

    #if DEBUG
    // Debug builds default to the local Python mock server
    // (tools/mock-flashair). The iOS Simulator shares the host's network
    // stack, so localhost:8080 is reachable without joining any Wi-Fi.
    // Mirrors Android's debug build variant (flashair-mock / 10.0.2.2:8080).
    static let defaultSSID = "flashair-mock"
    static let defaultHost = "http://localhost:8080"
    #else
    static let defaultSSID = "flashair"
    static let defaultHost = "http://192.168.0.1"
    #endif

    static let `default` = SyncSettings(
        ssid: defaultSSID,
        passphrase: "12345678",
        host: defaultHost,
        fileExtensions: ["jpg", "jpeg", "png", "heic", "mp4", "mov"],
        concurrentDownloads: 1,
        maxFileSizeMB: 2000
    )

    /// True when `host` points at a local mock server. The iOS Simulator
    /// shares the host's network stack, so the Python mock at localhost:8080
    /// is reachable directly — no FlashAir Wi-Fi join needed. Mirrors the
    /// Android SyncEngine predicate (minus 10.0.2.2, the Android-emulator alias).
    var isLocalMockHost: Bool {
        host.contains("localhost") || host.contains("127.0.0.1")
    }

    func shouldImport(_ entry: DirectoryEntry) -> Bool {
        // Skip directories
        guard !entry.isDirectory else { return false }

        // Check file extension
        let ext = (entry.name as NSString).pathExtension.lowercased()
        guard fileExtensions.contains(ext) else { return false }

        // Check file size
        let sizeMB = entry.size / (1024 * 1024)
        guard sizeMB <= maxFileSizeMB else { return false }

        return true
    }
}

// MARK: - Import State

/// State of a file import operation
enum ImportState: Equatable {
    case pending
    case downloading(progress: Double)
    case saving
    case completed
    case failed(error: String)
    case skipped(reason: String)

    var isComplete: Bool {
        if case .completed = self { return true }
        return false
    }

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}

/// Import item with state tracking
struct ImportItem: Identifiable {
    let entry: DirectoryEntry
    var state: ImportState

    var id: String { entry.id }
}

// MARK: - Import Result

/// Summary of an import session
struct ImportResult {
    let totalFiles: Int
    let importedCount: Int
    let skippedCount: Int
    let failedCount: Int
    let totalBytes: Int
    let duration: TimeInterval
    let errors: [String]

    var successRate: Double {
        guard totalFiles > 0 else { return 0 }
        return Double(importedCount) / Double(totalFiles)
    }

    var summary: String {
        """
        Imported: \(importedCount) files (\(ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .file)))
        Skipped: \(skippedCount) files
        Failed: \(failedCount) files
        Duration: \(String(format: "%.1f", duration))s
        """
    }
}

// MARK: - Errors

enum FlashAirError: LocalizedError {
    case networkError(Error)
    case invalidResponse
    case csvParseError(String)
    case fileNotFound(String)
    case permissionDenied
    case cancelled
    case wifiConnectionFailed

    var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from FlashAir card"
        case .csvParseError(let details):
            return "Failed to parse directory listing: \(details)"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .permissionDenied:
            return "Permission denied. Please grant access in Settings."
        case .cancelled:
            return "Operation cancelled"
        case .wifiConnectionFailed:
            return "Failed to connect to FlashAir Wi-Fi network"
        }
    }
}
