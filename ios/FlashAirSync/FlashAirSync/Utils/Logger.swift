import Foundation
import os.log

/// Simple logging utility with file export support
actor Logger {
    static let shared = Logger()

    private var logEntries: [LogEntry] = []
    private let maxEntries = 1000 // Keep last 1000 log entries

    private init() {
        logInfo("Logger initialized")
    }

    // MARK: - Logging

    func log(_ message: String, level: LogLevel = .info) {
        let entry = LogEntry(
            timestamp: Date(),
            level: level,
            message: message
        )

        logEntries.append(entry)

        // Trim if needed
        if logEntries.count > maxEntries {
            logEntries.removeFirst(logEntries.count - maxEntries)
        }

        // Print to console
        print("[\(level.emoji) \(level.rawValue)] \(message)")

        // Also log to os_log for system integration
        os_log("%{public}@", log: .default, type: level.osLogType, message)
    }

    func logInfo(_ message: String) {
        log(message, level: .info)
    }

    func logWarning(_ message: String) {
        log(message, level: .warning)
    }

    func logError(_ message: String) {
        log(message, level: .error)
    }

    func logDebug(_ message: String) {
        #if DEBUG
        log(message, level: .debug)
        #endif
    }

    // MARK: - Export

    /// Get all log entries as formatted string
    func exportLogs() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        var lines: [String] = []
        lines.append("FlashAir Sync Logs")
        lines.append("Generated: \(formatter.string(from: Date()))")
        lines.append(String(repeating: "=", count: 60))
        lines.append("")

        for entry in logEntries {
            let timestamp = formatter.string(from: entry.timestamp)
            lines.append("[\(timestamp)] [\(entry.level.rawValue)] \(entry.message)")
        }

        return lines.joined(separator: "\n")
    }

    /// Clear all log entries
    func clearLogs() {
        logEntries.removeAll()
        logInfo("Logs cleared")
    }

    /// Get recent log entries (last N)
    func getRecentLogs(count: Int = 50) -> [LogEntry] {
        Array(logEntries.suffix(count))
    }
}

// MARK: - Supporting Types

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: LogLevel
    let message: String
}

enum LogLevel: String {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"

    var emoji: String {
        switch self {
        case .debug: return "🔍"
        case .info: return "ℹ️"
        case .warning: return "⚠️"
        case .error: return "❌"
        }
    }

    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .default
        case .error: return .error
        }
    }
}
