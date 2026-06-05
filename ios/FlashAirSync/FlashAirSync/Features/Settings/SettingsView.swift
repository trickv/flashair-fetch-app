import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var settings = UserDefaults.standard.syncSettings
    @State private var showingResetAlert = false
    @State private var showingLogsSheet = false

    var body: some View {
        NavigationView {
            Form {
                // Network settings
                Section {
                    TextField("SSID", text: $settings.ssid)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    TextField("Passphrase", text: $settings.passphrase)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    TextField("Host", text: $settings.host)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .keyboardType(.URL)
                } header: {
                    Text("FlashAir Network")
                } footer: {
                    Text("Default: flashair / 12345678 / http://192.168.0.1")
                }

                // File type filter
                Section {
                    ForEach(availableExtensions, id: \.self) { ext in
                        Toggle(ext.uppercased(), isOn: binding(for: ext))
                    }
                } header: {
                    Text("File Types")
                } footer: {
                    Text("Select which file types to import")
                }

                // Performance settings
                Section {
                    Stepper("Concurrent Downloads: \(settings.concurrentDownloads)", value: $settings.concurrentDownloads, in: 1...3)

                    Stepper("Max File Size: \(settings.maxFileSizeMB) MB", value: $settings.maxFileSizeMB, in: 10...5000, step: 50)

                    Stepper(value: maxFilesPerSyncBinding, in: 0...100) {
                        Text("Files per sync: \(settings.maxFilesPerSync.map(String.init) ?? "All")")
                    }
                } header: {
                    Text("Performance")
                } footer: {
                    Text("Higher concurrency may be faster but uses more battery. \"Files per sync\" caps how many new files each Sync transfers; \"All\" syncs every new file.")
                }

                // Privacy / telemetry
                Section {
                    Toggle("Send Anonymous Telemetry", isOn: telemetryEnabledBinding)
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("""
                    Off by default. When on, sends anonymous crash reports and \
                    sync metrics (file counts, durations, success/failure) to help \
                    improve the app. No photo content, no filenames, no personal \
                    information. Takes effect immediately; full crash-report \
                    coverage starts on next app launch.
                    """)
                }

                // Advanced actions
                Section {
                    Button(role: .destructive) {
                        showingResetAlert = true
                    } label: {
                        Label("Reset Sync Index", systemImage: "trash")
                    }

                    Button {
                        showingLogsSheet = true
                    } label: {
                        Label("View Logs", systemImage: "doc.text")
                    }
                } header: {
                    Text("Advanced")
                } footer: {
                    Text("Resetting the index will cause all files to be re-imported on the next sync")
                }

                // About section
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersion)
                            .foregroundColor(.secondary)
                    }

                    Link(destination: URL(string: "https://github.com/trickv/flashair-fetch-app")!) {
                        Label("View on GitHub", systemImage: "link")
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveSettings()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .alert("Reset Sync Index?", isPresented: $showingResetAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) {
                    resetIndex()
                }
            } message: {
                Text("This will cause all files to be re-imported on the next sync. Already imported photos will remain in your library.")
            }
            .sheet(isPresented: $showingLogsSheet) {
                LogsView()
            }
        }
    }

    // MARK: - Helpers

    private let availableExtensions = ["jpg", "jpeg", "png", "heic", "mp4", "mov"]

    /// Bridge the Optional Int storage (nil = unlimited) to a Stepper-friendly
    /// non-Optional Int where 0 displays as "All".
    private var maxFilesPerSyncBinding: Binding<Int> {
        Binding(
            get: { settings.maxFilesPerSync ?? 0 },
            set: { settings.maxFilesPerSync = $0 == 0 ? nil : $0 }
        )
    }

    /// Telemetry toggle takes effect *immediately* (persists to UserDefaults
    /// and starts/stops Sentry on flip) — different from the rest of the
    /// settings which only apply on Save. The "apply now" UX is appropriate
    /// for a privacy toggle: tapping it should feel decisive, not stage a
    /// pending change.
    private var telemetryEnabledBinding: Binding<Bool> {
        Binding(
            get: { settings.telemetryEnabled ?? false },
            set: { newValue in
                settings.telemetryEnabled = newValue
                // Persist immediately so Cancel doesn't undo a privacy choice.
                var stored = UserDefaults.standard.syncSettings
                stored.telemetryEnabled = newValue
                UserDefaults.standard.syncSettings = stored
                if newValue {
                    Telemetry.start()
                } else {
                    Telemetry.stop()
                }
            }
        )
    }

    private func binding(for extension: String) -> Binding<Bool> {
        Binding(
            get: { settings.fileExtensions.contains(`extension`) },
            set: { enabled in
                if enabled {
                    if !settings.fileExtensions.contains(`extension`) {
                        settings.fileExtensions.append(`extension`)
                    }
                } else {
                    settings.fileExtensions.removeAll { $0 == `extension` }
                }
            }
        )
    }

    private func saveSettings() {
        UserDefaults.standard.syncSettings = settings
    }

    private func resetIndex() {
        Task {
            let engine = SyncEngine(settings: settings)
            await engine.resetIndex()
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

// MARK: - Logs View

struct LogsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var logs: String = ""

    var body: some View {
        NavigationView {
            ScrollView {
                Text(logs)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("Logs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    ShareLink(item: logs)
                }
            }
            .task {
                logs = await Logger.shared.exportLogs()
            }
        }
    }
}

#Preview {
    SettingsView()
}
