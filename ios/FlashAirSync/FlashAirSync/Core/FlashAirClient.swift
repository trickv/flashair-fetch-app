import Foundation

/// HTTP client for FlashAir SD card API
actor FlashAirClient {
    private let host: String
    private let session: URLSession

    init(host: String) {
        self.host = host.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
    }

    // MARK: - Directory Listing

    /// List directory contents via command.cgi?op=100
    /// - Parameter path: Absolute directory path (e.g., "/DCIM")
    /// - Returns: Array of directory entries
    func listDirectory(_ path: String) async throws -> [DirectoryEntry] {
        let urlString = "\(host)/command.cgi?op=100&DIR=\(path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? path)"

        guard let url = URL(string: urlString) else {
            throw FlashAirError.invalidResponse
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FlashAirError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw FlashAirError.networkError(URLError(.badServerResponse))
        }

        guard let csvText = String(data: data, encoding: .utf8) else {
            throw FlashAirError.invalidResponse
        }

        return try parseCSV(csvText, requestDir: path)
    }

    /// Recursively walk directory tree and collect all entries
    /// - Parameters:
    ///   - rootPath: Starting directory path
    ///   - filter: Optional filter predicate
    /// - Returns: Array of all file entries (not directories)
    func walkDirectory(_ rootPath: String, filter: ((DirectoryEntry) -> Bool)? = nil) async throws -> [DirectoryEntry] {
        var allFiles: [DirectoryEntry] = []
        var directoriesToVisit = [rootPath]
        // Failures at the root mean we can't reach the card at all — surface
        // them. Failures one level deeper are tolerated per the FlashAir
        // protocol gotcha (transient hiccups on deep walks).
        var isRootListing = true

        while !directoriesToVisit.isEmpty {
            let currentDir = directoriesToVisit.removeFirst()

            do {
                print("📂 Listing \(currentDir)…")
                await Logger.shared.logInfo("Listing \(currentDir)")
                let entries = try await listDirectory(currentDir)
                print("   → \(entries.count) entries returned")
                await Logger.shared.logInfo("→ \(entries.count) entries from \(currentDir)")

                for entry in entries {
                    // Skip hidden files (start with .)
                    if entry.name.hasPrefix(".") {
                        continue
                    }

                    if entry.isDirectory {
                        // Add subdirectory to visit queue
                        directoriesToVisit.append(entry.absolutePath)
                    } else {
                        // Apply filter if provided
                        if let filter = filter, !filter(entry) {
                            continue
                        }
                        allFiles.append(entry)
                    }
                }
            } catch {
                if isRootListing {
                    // Don't swallow root-listing errors: previously this returned
                    // [] silently and the UI reported a misleading "Imported 0
                    // files" success when the real cause was a network failure
                    // (VPN, unreachable card, ATS, timeout, …).
                    print("❌ Root listing of \(currentDir) failed: \(error)")
                    await Logger.shared.logError("Root listing of \(currentDir) failed: \(error)")
                    throw error
                }
                print("⚠️ Failed to list subdirectory \(currentDir): \(error) — continuing")
                await Logger.shared.logWarning("Failed to list subdirectory \(currentDir): \(error)")
            }
            isRootListing = false
        }

        return allFiles
    }

    // MARK: - File Download

    /// Download a file from FlashAir card.
    /// - Parameters:
    ///   - path: Absolute file path on the card.
    ///   - expectedSize: Size in bytes the directory listing advertised. The
    ///     downloaded file's byte count is verified against this value before
    ///     this method returns — if it doesn't match (e.g. camera sleep
    ///     truncated the response), the temp file is deleted and the function
    ///     throws `FlashAirError.sizeMismatch`. This is the atomicity
    ///     guarantee for the caller: a returned URL is *always* a complete
    ///     file with the right byte count. PhotoKit never sees a half-baked
    ///     download.
    ///   - progress: Optional progress callback (0.0 to 1.0). Not yet wired
    ///     through URLSession — see TODO.md.
    /// - Returns: Local temporary file URL pointing at a verified-complete
    ///   download.
    func downloadFile(_ path: String, expectedSize: Int, progress: ((Double) -> Void)? = nil) async throws -> URL {
        let urlString = "\(host)\(path)"

        guard let url = URL(string: urlString) else {
            throw FlashAirError.invalidResponse
        }

        // Create temp file
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension((path as NSString).pathExtension)

        // Download with progress tracking
        let (location, response) = try await session.download(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FlashAirError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw FlashAirError.fileNotFound(path)
        }

        // Move to temp location
        try FileManager.default.moveItem(at: location, to: tempFile)

        // Belt-and-braces: verify the downloaded byte count matches what the
        // CSV listing advertised. URLSession *usually* catches a truncated
        // stream via Content-Length mismatch, but a camera-sleep mid-transfer
        // can close the TCP connection cleanly enough that the partial
        // response looks like a successful 200. Without this check we'd save
        // a half-baked JPEG to Photos and mark the file as synced.
        let actualSize = (try? FileManager.default
            .attributesOfItem(atPath: tempFile.path)[.size] as? Int) ?? -1
        guard actualSize == expectedSize else {
            // Clean up the bad file before throwing so we don't leak temp
            // bytes if the caller doesn't catch immediately.
            try? FileManager.default.removeItem(at: tempFile)
            print("⚠️ Size mismatch for \(path): expected \(expectedSize), got \(actualSize)")
            await Logger.shared.logError("Size mismatch for \(path): expected \(expectedSize), got \(actualSize) — partial download")
            throw FlashAirError.sizeMismatch(path: path, expected: expectedSize, actual: actualSize)
        }

        return tempFile
    }

    // MARK: - Card Configuration

    /// Get FlashAir card configuration
    /// - Returns: Dictionary of configuration values
    func getCardConfig() async throws -> [String: String] {
        let urlString = "\(host)/command.cgi?op=104"

        guard let url = URL(string: urlString) else {
            throw FlashAirError.invalidResponse
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw FlashAirError.invalidResponse
        }

        guard let text = String(data: data, encoding: .utf8) else {
            throw FlashAirError.invalidResponse
        }

        var config: [String: String] = [:]
        for line in text.components(separatedBy: .newlines) {
            let parts = line.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                config[String(parts[0])] = String(parts[1])
            }
        }

        return config
    }

    // MARK: - CSV Parsing

    /// Parse FlashAir CSV directory listing
    /// - Parameters:
    ///   - csvText: Raw CSV response text
    ///   - requestDir: Directory path from the request (for 5-field format fallback)
    /// - Returns: Array of parsed entries
    private func parseCSV(_ csvText: String, requestDir: String) throws -> [DirectoryEntry] {
        var entries: [DirectoryEntry] = []

        let lines = csvText.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            // Skip empty lines
            guard !trimmed.isEmpty else { continue }

            // Skip header
            guard !trimmed.hasPrefix("WLANSD_FILELIST") else { continue }

            // Parse CSV fields
            let fields = trimmed.components(separatedBy: ",")

            // Support both 6-field and 5-field formats
            let entry: DirectoryEntry?

            if fields.count == 6 {
                // 6-field format: directory,name,size,attribute,date,time
                entry = parseEntry6Field(fields)
            } else if fields.count == 5 {
                // 5-field format: name,size,attribute,date,time (infer directory)
                entry = parseEntry5Field(fields, directory: requestDir)
            } else {
                print("⚠️ Skipping malformed CSV line (expected 5 or 6 fields): \(trimmed)")
                continue
            }

            if let entry = entry {
                entries.append(entry)
            }
        }

        return entries
    }

    /// Parse 6-field CSV format
    private func parseEntry6Field(_ fields: [String]) -> DirectoryEntry? {
        guard fields.count == 6,
              let size = Int(fields[2]),
              let attribute = Int(fields[3]),
              let date = Int(fields[4]),
              let time = Int(fields[5]) else {
            return nil
        }

        return DirectoryEntry(
            directory: fields[0],
            name: fields[1],
            size: size,
            attribute: attribute,
            fatDate: date,
            fatTime: time
        )
    }

    /// Parse 5-field CSV format (legacy)
    private func parseEntry5Field(_ fields: [String], directory: String) -> DirectoryEntry? {
        guard fields.count == 5,
              let size = Int(fields[1]),
              let attribute = Int(fields[2]),
              let date = Int(fields[3]),
              let time = Int(fields[4]) else {
            return nil
        }

        return DirectoryEntry(
            directory: directory,
            name: fields[0],
            size: size,
            attribute: attribute,
            fatDate: date,
            fatTime: time
        )
    }
}
