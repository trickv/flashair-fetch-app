import Foundation

/// Orchestrates the sync process: scan, dedupe, download
actor SyncEngine {
    private let client: FlashAirClient
    private let index: SyncIndex
    private let settings: SyncSettings
    private let photoSaver = PhotoSaver()

    private(set) var isCancelled = false

    init(settings: SyncSettings) {
        self.settings = settings
        self.client = FlashAirClient(host: settings.host)
        self.index = SyncIndex(ssid: settings.ssid)
    }

    // MARK: - Sync Operations

    /// Perform a full sync operation
    /// - Parameters:
    ///   - progressCallback: Called for each state change
    /// - Returns: Array of import items with final states
    func sync(
        progressCallback: @MainActor @escaping ([ImportItem]) -> Void,
        phaseCallback: @MainActor @escaping (String?) -> Void
    ) async throws -> ImportResult {
        isCancelled = false
        let startTime = Date()

        // Step 1: Scan DCIM directory recursively
        await phaseCallback("Scanning files on the card…")
        print("📡 Scanning /DCIM…")
        await Logger.shared.logInfo("Scanning /DCIM")
        let allEntries = try await client.walkDirectory("/DCIM") { [settings] entry in
            settings.shouldImport(entry)
        }
        print("📊 Found \(allEntries.count) files on card after extension/size filter")
        await Logger.shared.logInfo("Found \(allEntries.count) files after extension/size filter")

        // Step 2: Filter out already-synced files
        await phaseCallback("Checking sync history (\(allEntries.count) on card)…")
        var newEntries: [DirectoryEntry] = []
        for entry in allEntries {
            if await !index.hasSeen(entry) {
                newEntries.append(entry)
            }
        }
        print("🔁 \(allEntries.count - newEntries.count) already synced, \(newEntries.count) new")
        await Logger.shared.logInfo("\(allEntries.count - newEntries.count) already synced, \(newEntries.count) new")

        // Optional per-sync cap (nil = unlimited). Useful for trying the app
        // on a card with thousands of photos without committing to syncing all.
        if let limit = settings.maxFilesPerSync, limit > 0, newEntries.count > limit {
            print("📋 Capping this sync to \(limit) of \(newEntries.count) new files (maxFilesPerSync setting)")
            newEntries = Array(newEntries.prefix(limit))
        }

        print("✨ \(newEntries.count) new files to import")

        // Step 3: Create import items
        var items = newEntries.map { ImportItem(entry: $0, state: .pending) }
        await progressCallback(items)

        // Hand the header off to the per-file count ("Importing X of N…")
        // that statusText computes from items during the download loop.
        await phaseCallback(newEntries.isEmpty ? "Nothing new to import" : nil)

        // Step 4: Download and import each file
        var totalBytes = 0
        var importedCount = 0
        var failedCount = 0
        var errors: [String] = []

        for i in 0..<items.count {
            if isCancelled {
                items[i].state = .skipped(reason: "Cancelled")
                continue
            }

            let entry = items[i].entry

            do {
                // Update state: downloading
                items[i].state = .downloading(progress: 0.0)
                await progressCallback(items)

                // Download file (TODO: add progress tracking)
                let localURL = try await client.downloadFile(entry.absolutePath)

                // Update state: saving
                items[i].state = .saving
                await progressCallback(items)

                // Save to Photos. saveToPhotos throws on failure, so the
                // markSeen below is only reached on a successful save — a
                // failed file stays un-indexed and will retry on next sync.
                try await photoSaver.saveToPhotos(
                    fileURL: localURL,
                    originalFilename: entry.name,
                    creationDate: entry.modifiedAt
                )

                // Mark as imported (only after the file is safely in Photos)
                await index.markSeen(entry)
                totalBytes += entry.size
                importedCount += 1

                // Clean up temp file
                try? FileManager.default.removeItem(at: localURL)

                // Update state: completed
                items[i].state = .completed
                await progressCallback(items)

                print("✅ Imported: \(entry.name) (\(ByteCountFormatter.string(fromByteCount: Int64(entry.size), countStyle: .file)))")

            } catch {
                failedCount += 1
                let errorMsg = error.localizedDescription
                errors.append("\(entry.name): \(errorMsg)")

                items[i].state = .failed(error: errorMsg)
                await progressCallback(items)

                print("❌ Failed: \(entry.name) - \(errorMsg)")
            }
        }

        // Step 5: Persist index
        try await index.persist()

        let duration = Date().timeIntervalSince(startTime)

        return ImportResult(
            totalFiles: items.count,
            importedCount: importedCount,
            skippedCount: items.count - importedCount - failedCount,
            failedCount: failedCount,
            totalBytes: totalBytes,
            duration: duration,
            errors: errors
        )
    }

    /// Cancel the current sync operation
    func cancel() {
        isCancelled = true
    }

    /// Get sync index statistics
    func getIndexStats() async -> IndexStats {
        await index.getStats()
    }

    /// Reset sync index (re-import all files on next sync)
    func resetIndex() async {
        await index.reset()
    }
}
