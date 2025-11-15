import SwiftUI

struct ImportView: View {
    @StateObject private var viewModel = ImportViewModel()
    @State private var showingSettings = false

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Header
                headerSection

                Spacer()

                // Main action button
                if !viewModel.isImporting {
                    syncButton
                } else {
                    progressSection
                }

                Spacer()

                // Error message
                if let error = viewModel.errorMessage {
                    errorSection(error)
                }

                // Footer info
                footerSection
            }
            .padding()
            .navigationTitle("FlashAir Sync")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .alert("Import Complete", isPresented: $viewModel.showingResult) {
                Button("OK", role: .cancel) { }
            } message: {
                if let result = viewModel.importResult {
                    Text(result.summary)
                }
            }
        }
    }

    // MARK: - Subviews

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.flashAirPrimary)

            Text("FlashAir Photo Importer")
                .font(.title2)
                .fontWeight(.semibold)

            Text(viewModel.statusText)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private var syncButton: some View {
        Button {
            Task {
                await viewModel.startImport()
            }
        } label: {
            Label("Sync from FlashAir", systemImage: "arrow.down.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.flashAirPrimary)
                .foregroundColor(.white)
                .cornerRadius(12)
        }
    }

    private var progressSection: some View {
        VStack(spacing: 16) {
            // Progress bar
            ProgressView(value: viewModel.progress) {
                Text("Importing files...")
                    .font(.headline)
            } currentValueLabel: {
                Text("\(Int(viewModel.progress * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // File list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.importItems) { item in
                        ImportItemRow(item: item)
                    }
                }
                .padding(.horizontal)
            }
            .frame(height: 300)
            .background(Color(uiColor: .systemGroupedBackground))
            .cornerRadius(12)

            // Cancel button
            Button(role: .destructive) {
                viewModel.cancelImport()
            } label: {
                Label("Cancel", systemImage: "xmark.circle")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.flashAirError.opacity(0.1))
                    .foregroundColor(.flashAirError)
                    .cornerRadius(12)
            }
        }
    }

    private func errorSection(_ error: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.flashAirError)
            Text(error)
                .font(.caption)
                .foregroundColor(.flashAirError)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.flashAirError.opacity(0.1))
        .cornerRadius(8)
    }

    private var footerSection: some View {
        VStack(spacing: 8) {
            Text("SSID: \(viewModel.settings.ssid)")
                .font(.caption2)
                .foregroundColor(.secondary)

            Text("Host: \(viewModel.settings.host)")
                .font(.caption2)
                .foregroundColor(.secondary)

            Text("Tap the gear icon to configure settings")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Import Item Row

struct ImportItemRow: View {
    let item: ImportItem

    var body: some View {
        HStack {
            // Icon
            Image(systemName: iconName)
                .foregroundColor(iconColor)
                .frame(width: 24)

            // File name
            VStack(alignment: .leading, spacing: 2) {
                Text(item.entry.name)
                    .font(.caption)
                    .lineLimit(1)

                Text(statusText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Size
            Text(ByteCountFormatter.string(fromByteCount: Int64(item.entry.size), countStyle: .file))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var iconName: String {
        switch item.state {
        case .pending: return "circle"
        case .downloading: return "arrow.down.circle"
        case .saving: return "square.and.arrow.down"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .skipped: return "minus.circle"
        }
    }

    private var iconColor: Color {
        switch item.state {
        case .pending: return .gray
        case .downloading: return .blue
        case .saving: return .orange
        case .completed: return .green
        case .failed: return .red
        case .skipped: return .orange
        }
    }

    private var statusText: String {
        switch item.state {
        case .pending: return "Pending"
        case .downloading(let progress): return "Downloading \(Int(progress * 100))%"
        case .saving: return "Saving..."
        case .completed: return "Completed"
        case .failed(let error): return "Failed: \(error)"
        case .skipped(let reason): return "Skipped: \(reason)"
        }
    }
}

#Preview {
    ImportView()
}
