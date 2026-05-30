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

        // Determine media type from the original filename (the temp file on
        // disk is named with a UUID and has no useful extension by itself).
        let ext = (originalFilename as NSString).pathExtension.lowercased()
        let isVideo = ["mp4", "mov", "m4v"].contains(ext)
        let resourceType: PHAssetResourceType = isVideo ? .video : .photo

        // Tell PhotoKit the original filename explicitly. Without this it falls
        // back to the temp file's name (a UUID), which is what shows up in the
        // Photos Info panel and — more importantly — what iCloud/Google Photos/
        // Immich uploaders see when they enumerate PHAssetResources. Setting
        // it preserves IMG_NNNN.JPG end-to-end through the library and out to
        // any photo-sync service.
        let resourceOptions = PHAssetResourceCreationOptions()
        resourceOptions.originalFilename = originalFilename

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: resourceType, fileURL: fileURL, options: resourceOptions)

                // Use the FAT-decoded capture timestamp so the asset slots into
                // the library at when the photo was actually taken.
                if let date = creationDate {
                    request.creationDate = date
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
