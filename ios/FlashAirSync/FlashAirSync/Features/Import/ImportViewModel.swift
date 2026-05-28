import Foundation
import SwiftUI

/// View model for the import flow
@MainActor
class ImportViewModel: ObservableObject {
    // MARK: - Published State

    @Published var importItems: [ImportItem] = []
    @Published var isImporting = false
    @Published var importResult: ImportResult?
    @Published var errorMessage: String?
    @Published var showingResult = false

    // Dependencies
    private let wifiJoiner = WiFiJoiner()
    private var syncEngine: SyncEngine?
    private let photoSaver = PhotoSaver()

    var settings: SyncSettings {
        UserDefaults.standard.syncSettings
    }

    // MARK: - Computed Properties

    var statusText: String {
        if isImporting {
            let completed = importItems.filter { $0.state.isComplete }.count
            return "Importing \(completed) of \(importItems.count)..."
        }
        return "Ready to sync"
    }

    var progress: Double {
        guard !importItems.isEmpty else { return 0 }
        let completed = importItems.filter { $0.state.isComplete }.count
        return Double(completed) / Double(importItems.count)
    }

    // MARK: - Actions

    /// Start the import process
    func startImport() async {
        isImporting = true
        errorMessage = nil
        importItems = []
        importResult = nil

        do {
            // Step 1: Check Photos permission
            let hasPermission = await photoSaver.requestPermission()
            guard hasPermission else {
                throw FlashAirError.permissionDenied
            }

            // Step 2: Connect to FlashAir Wi-Fi (if needed)
            await Logger.shared.logInfo("Connecting to \(settings.ssid)...")

            // Skip the Wi-Fi join when talking to a local mock server;
            // otherwise join the FlashAir's network. (Item 5 will move this
            // into SyncEngine with proper teardown — the predicate lives on
            // SyncSettings so it can be reused there.)
            if settings.isLocalMockHost {
                await Logger.shared.logWarning("Skipping Wi-Fi connection (using mock server)")
            } else {
                try await wifiJoiner.joinNetwork(ssid: settings.ssid, passphrase: settings.passphrase)
            }

            // Step 3: Create sync engine and start sync
            let engine = SyncEngine(settings: settings)
            self.syncEngine = engine

            await Logger.shared.logInfo("Starting sync...")

            let result = try await engine.sync { [weak self] items in
                self?.importItems = items
            }

            // Step 4: Show result
            self.importResult = result
            self.showingResult = true

            await Logger.shared.logInfo("Sync completed: \(result.importedCount) imported, \(result.failedCount) failed")

        } catch {
            errorMessage = error.localizedDescription
            await Logger.shared.logError("Sync failed: \(error.localizedDescription)")
        }

        isImporting = false
    }

    /// Cancel the current import
    func cancelImport() {
        Task {
            await syncEngine?.cancel()
            await Logger.shared.logWarning("Sync cancelled by user")
        }
    }

    /// Reset sync index
    func resetIndex() async {
        await syncEngine?.resetIndex()
        await Logger.shared.logWarning("Sync index reset")
    }

    /// Request Photos permission explicitly
    func requestPhotosPermission() async {
        _ = await photoSaver.requestPermission()
    }
}
