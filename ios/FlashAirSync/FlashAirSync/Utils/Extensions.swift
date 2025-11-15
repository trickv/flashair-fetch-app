import Foundation
import SwiftUI

// MARK: - View Extensions

extension View {
    /// Apply a modifier conditionally
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - UserDefaults Extensions

extension UserDefaults {
    private enum Keys {
        static let syncSettings = "syncSettings"
    }

    var syncSettings: SyncSettings {
        get {
            guard let data = data(forKey: Keys.syncSettings),
                  let settings = try? JSONDecoder().decode(SyncSettings.self, from: data) else {
                return .default
            }
            return settings
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            set(data, forKey: Keys.syncSettings)
        }
    }
}

// MARK: - String Extensions

extension String {
    /// Format as file size (e.g., "3.5 MB")
    var asFileSize: String {
        guard let bytes = Int(self) else { return self }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

// MARK: - Date Extensions

extension Date {
    /// Format as relative time (e.g., "2 minutes ago")
    var relativeFormatted: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: Date())
    }

    /// Format as short date/time
    var shortFormatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }
}

// MARK: - Color Extensions

extension Color {
    static let flashAirPrimary = Color.blue
    static let flashAirSuccess = Color.green
    static let flashAirWarning = Color.orange
    static let flashAirError = Color.red
}
