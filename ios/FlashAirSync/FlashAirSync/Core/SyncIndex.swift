import Foundation

/// Manages persistent sync state for deduplication
actor SyncIndex {
    private var seenKeys: Set<String>
    private let ssid: String
    private let fileURL: URL

    init(ssid: String) {
        self.ssid = ssid
        self.seenKeys = []

        // Determine storage location
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let syncDir = docsDir.appendingPathComponent("FlashAirSync", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(at: syncDir, withIntermediateDirectories: true)

        // Index file path: sync_index_<ssid>.json
        let sanitizedSSID = ssid.replacingOccurrences(of: "/", with: "_")
        self.fileURL = syncDir.appendingPathComponent("sync_index_\(sanitizedSSID).json")

        // Load existing index
        self.seenKeys = Self.loadFromDisk(url: fileURL)
    }

    // MARK: - Public API

    /// Check if an entry has been previously synced
    func hasSeen(_ entry: DirectoryEntry) -> Bool {
        seenKeys.contains(entry.dedupeKey)
    }

    /// Mark an entry as synced
    func markSeen(_ entry: DirectoryEntry) {
        seenKeys.insert(entry.dedupeKey)
    }

    /// Mark multiple entries as synced
    func markSeen(_ entries: [DirectoryEntry]) {
        for entry in entries {
            seenKeys.insert(entry.dedupeKey)
        }
    }

    /// Get count of seen entries
    func count() -> Int {
        seenKeys.count
    }

    /// Reset the index (clear all entries)
    func reset() {
        seenKeys.removeAll()
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Persist current state to disk
    func persist() throws {
        // Convert set to dictionary for JSON encoding
        let dict = Dictionary(uniqueKeysWithValues: seenKeys.map { ($0, true) })

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(dict)

        // Atomic write: write to temp file, then rename
        let tempURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent(UUID().uuidString)

        try data.write(to: tempURL)
        try FileManager.default.replaceItemAt(fileURL, withItemAt: tempURL)
    }

    // MARK: - Persistence

    /// Load index from disk
    private static func loadFromDisk(url: URL) -> Set<String> {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: url)
            let dict = try JSONDecoder().decode([String: Bool].self, from: data)
            return Set(dict.keys)
        } catch {
            print("⚠️ Failed to load sync index from \(url.path): \(error)")
            return []
        }
    }

    /// Export index as JSON string (for debugging/support)
    func exportJSON() throws -> String {
        let dict = Dictionary(uniqueKeysWithValues: seenKeys.map { ($0, true) })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(dict)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// Get statistics about the index
    func getStats() -> IndexStats {
        IndexStats(
            totalEntries: seenKeys.count,
            fileURL: fileURL.path,
            fileSizeBytes: (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
        )
    }
}

// MARK: - Supporting Types

struct IndexStats {
    let totalEntries: Int
    let fileURL: String
    let fileSizeBytes: Int

    var fileSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(fileSizeBytes), countStyle: .file)
    }
}
