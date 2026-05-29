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
    /// Free-text "what's happening right now" line. Drives the header when set;
    /// when nil, statusText falls back to the per-file "Importing X of N…" count.
    @Published var currentPhase: String?

    // Dependencies
    private let wifiJoiner = WiFiJoiner()
    private var syncEngine: SyncEngine?
    private let photoSaver = PhotoSaver()

    var settings: SyncSettings {
        UserDefaults.standard.syncSettings
    }

    // MARK: - Computed Properties

    var statusText: String {
        if let phase = currentPhase, !phase.isEmpty {
            return phase
        }
        if isImporting {
            guard !importItems.isEmpty else { return "Working…" }
            let completed = importItems.filter { $0.state.isComplete }.count
            return "Importing \(completed) of \(importItems.count)…"
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
        // Set phase BEFORE isImporting so the header has something meaningful
        // the moment the progress UI appears (was showing "Importing 0 of 0...").
        currentPhase = "Preparing..."
        isImporting = true
        errorMessage = nil
        importItems = []
        importResult = nil

        // Capture once so the join and the teardown agree on the same network.
        let ssid = settings.ssid
        let needsWiFi = !settings.isLocalMockHost
        print("🚀 startImport: host=\(settings.host) ssid=\(ssid) needsWiFi=\(needsWiFi)")

        do {
            // Step 1: Check Photos permission
            currentPhase = "Checking Photos permission..."
            let hasPermission = await photoSaver.requestPermission()
            guard hasPermission else {
                throw FlashAirError.permissionDenied
            }
            print("✅ Photos permission OK")

            // Step 2: Join the FlashAir's Wi-Fi (skipped for the local mock server,
            // which the Simulator reaches over the shared host network stack).
            if needsWiFi {
                currentPhase = "Joining Wi-Fi network \"\(ssid)\"..."
                await Logger.shared.logInfo("Connecting to \(ssid)...")
                print("📶 Joining Wi-Fi \"\(ssid)\" via NEHotspotConfiguration...")
                try await wifiJoiner.joinNetwork(ssid: ssid, passphrase: settings.passphrase)
                print("📶 Joined \"\(ssid)\"")
                await Logger.shared.logInfo("Joined \(ssid)")
            } else {
                await Logger.shared.logWarning("Skipping Wi-Fi connection (using mock server)")
            }

            // Step 3: Create sync engine and start sync
            let engine = SyncEngine(settings: settings)
            self.syncEngine = engine

            await Logger.shared.logInfo("Starting sync...")

            let result = try await engine.sync(
                progressCallback: { [weak self] items in self?.importItems = items },
                phaseCallback: { [weak self] phase in self?.currentPhase = phase }
            )

            // Step 4: Show result
            self.importResult = result
            self.showingResult = true

            await Logger.shared.logInfo("Sync completed: \(result.importedCount) imported, \(result.failedCount) failed")

        } catch {
            errorMessage = error.localizedDescription
            print("❌ Sync threw: \(error)")
            await Logger.shared.logError("Sync failed: \(error.localizedDescription)")
        }

        // Step 5: Always tear down a Wi-Fi join we created — on success OR failure —
        // so the phone leaves the internet-less FlashAir network and regains normal
        // connectivity. removeConfiguration is a harmless no-op if the join never
        // actually succeeded.
        if needsWiFi {
            currentPhase = "Disconnecting from \"\(ssid)\"..."
            print("📶 Removing hotspot configuration for \"\(ssid)\"...")
            wifiJoiner.disconnect(ssid: ssid)
            await Logger.shared.logInfo("Disconnected from \(ssid)")
        }

        currentPhase = nil
        isImporting = false
        print("🏁 startImport: done")
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
