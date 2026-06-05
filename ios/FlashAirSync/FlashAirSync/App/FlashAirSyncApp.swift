import SwiftUI

@main
struct FlashAirSyncApp: App {
    init() {
        // Start Sentry iff the user has previously opted in via Settings.
        // No-op for first-time users / those who left telemetry off — keeps
        // the privacy default intact. Must run before any code that could
        // emit telemetry so crash/hang handlers install for the full session.
        Telemetry.startIfEnabled()

        // Initialize logger
        Task {
            await Logger.shared.logInfo("FlashAir Sync started")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
