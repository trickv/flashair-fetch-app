import SwiftUI

@main
struct FlashAirSyncApp: App {
    init() {
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
