import Foundation
import NetworkExtension

/// Manages FlashAir Wi-Fi network connection on iOS
@MainActor
class WiFiJoiner: ObservableObject {
    @Published var isConnected = false
    @Published var currentSSID: String?

    /// Join FlashAir Wi-Fi network
    /// - Parameters:
    ///   - ssid: Network SSID
    ///   - passphrase: WPA2 passphrase
    /// - Throws: FlashAirError.wifiConnectionFailed if connection fails
    func joinNetwork(ssid: String, passphrase: String) async throws {
        // Create hotspot configuration
        let configuration = NEHotspotConfiguration(ssid: ssid, passphrase: passphrase, isWEP: false)
        configuration.joinOnce = false // Persist connection for convenience

        do {
            try await NEHotspotConfigurationManager.shared.apply(configuration)

            // Update state
            isConnected = true
            currentSSID = ssid

            print("✅ Connected to \(ssid)")

        } catch {
            isConnected = false
            currentSSID = nil

            // Map NEHotspotConfigurationError to user-friendly messages
            if let hsError = error as? NEHotspotConfigurationError {
                switch hsError.code {
                case .invalid:
                    throw FlashAirError.wifiConnectionFailed
                case .invalidSSID:
                    throw FlashAirError.csvParseError("Invalid SSID: \(ssid)")
                case .invalidWPAPassphrase, .invalidWEPPassphrase:
                    throw FlashAirError.csvParseError("Invalid passphrase")
                case .userDenied:
                    throw FlashAirError.permissionDenied
                case .alreadyAssociated:
                    // Already connected - treat as success
                    isConnected = true
                    currentSSID = ssid
                    return
                default:
                    throw FlashAirError.wifiConnectionFailed
                }
            }

            throw FlashAirError.wifiConnectionFailed
        }
    }

    /// Disconnect from current network
    func disconnect(ssid: String) {
        NEHotspotConfigurationManager.shared.removeConfiguration(forSSID: ssid)
        isConnected = false
        currentSSID = nil
        print("🔌 Disconnected from \(ssid)")
    }

    /// Check if currently connected to a specific SSID
    /// - Note: iOS doesn't provide a reliable API to query current SSID in all cases
    /// - This is a best-effort check based on state
    func isConnectedTo(ssid: String) -> Bool {
        return currentSSID == ssid && isConnected
    }
}
