import Foundation
import Photos
import UIKit

/// Saves media files to iOS Photos library
actor PhotoSaver {

    /// Check if we have permission to save to Photos
    func checkPermission() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)

        switch status {
        case .authorized, .limited:
            return true
        case .notDetermined:
            // Request permission
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            return newStatus == .authorized || newStatus == .limited
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    /// Save a file to the Photos library
    /// - Parameters:
    ///   - fileURL: Local file URL (must be accessible)
    ///   - originalFilename: Original filename from FlashAir
    ///   - creationDate: Optional creation date to set
    /// - Throws: FlashAirError.permissionDenied if Photos access denied
    func saveToPhotos(fileURL: URL, originalFilename: String, creationDate: Date?) async throws {
        // Check permission first
        guard await checkPermission() else {
            throw FlashAirError.permissionDenied
        }

        // Determine media type
        let ext = fileURL.pathExtension.lowercased()
        let isVideo = ["mp4", "mov", "m4v"].contains(ext)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                if isVideo {
                    // Save video
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: .video, fileURL: fileURL, options: nil)

                    // Set creation date if provided
                    if let date = creationDate {
                        request.creationDate = date
                    }

                } else {
                    // Save photo
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: .photo, fileURL: fileURL, options: nil)

                    // Set creation date if provided
                    if let date = creationDate {
                        request.creationDate = date
                    }
                }

            }, completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(throwing: FlashAirError.invalidResponse)
                }
            })
        }
    }

    /// Request Photos permission explicitly
    /// - Returns: true if granted, false otherwise
    @MainActor
    func requestPermission() async -> Bool {
        await checkPermission()
    }
}
