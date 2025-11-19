package com.flashairsync.core

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileInputStream

/**
 * Writes downloaded media files to Android MediaStore
 * Saves to Pictures/FlashAirImport/ with preserved directory structure
 */
class MediaStoreWriter(private val context: Context) {

    companion object {
        private const val TAG = "MediaStoreWriter"
        private const val BASE_FOLDER = "FlashAirImport"

        // Supported file extensions
        private val IMAGE_EXTENSIONS = setOf("jpg", "jpeg", "png", "heic", "gif", "webp")
        private val VIDEO_EXTENSIONS = setOf("mp4", "mov", "avi", "mkv", "3gp")
    }

    // MARK: - Public API

    /**
     * Save a file to MediaStore
     * @param sourceFile Downloaded file (temporary location)
     * @param flashAirPath Original path on FlashAir (e.g., "/DCIM/100CANON/IMG_0001.JPG")
     * @param mimeType MIME type of the file
     * @return MediaStore URI of saved file
     * @throws FlashAirError.PermissionDenied if storage permission not granted
     */
    suspend fun saveToGallery(
        sourceFile: File,
        flashAirPath: String,
        mimeType: String? = null
    ): Uri = withContext(Dispatchers.IO) {

        if (!sourceFile.exists()) {
            throw FlashAirError.FileNotFound(sourceFile.absolutePath)
        }

        val fileName = sourceFile.name
        val extension = fileName.substringAfterLast('.', "").lowercase()

        // Determine media type
        val isImage = IMAGE_EXTENSIONS.contains(extension)
        val isVideo = VIDEO_EXTENSIONS.contains(extension)

        if (!isImage && !isVideo) {
            throw IllegalArgumentException("Unsupported file type: $extension")
        }

        // Build relative path preserving FlashAir directory structure
        // E.g., "/DCIM/100CANON/IMG_0001.JPG" -> "FlashAirImport/DCIM/100CANON"
        val relativePath = buildRelativePath(flashAirPath)

        Log.d(TAG, "Saving $fileName to MediaStore at $relativePath")

        // Determine content URI and MIME type
        val contentUri = if (isImage) {
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        } else {
            MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        }

        val detectedMimeType = mimeType ?: detectMimeType(extension, isImage)

        // Create content values
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
            put(MediaStore.MediaColumns.MIME_TYPE, detectedMimeType)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.MediaColumns.RELATIVE_PATH, "${Environment.DIRECTORY_PICTURES}/$relativePath")
                put(MediaStore.MediaColumns.IS_PENDING, 1) // Mark as pending while writing
            }
        }

        // Insert into MediaStore
        val uri = context.contentResolver.insert(contentUri, values)
            ?: throw FlashAirError.PermissionDenied

        try {
            // Write file content
            context.contentResolver.openOutputStream(uri)?.use { outputStream ->
                FileInputStream(sourceFile).use { inputStream ->
                    inputStream.copyTo(outputStream)
                }
            } ?: throw FlashAirError.PermissionDenied

            // Mark as complete
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val updateValues = ContentValues().apply {
                    put(MediaStore.MediaColumns.IS_PENDING, 0)
                }
                context.contentResolver.update(uri, updateValues, null, null)
            }

            Log.d(TAG, "Successfully saved $fileName to MediaStore: $uri")
            uri

        } catch (e: Exception) {
            // Clean up failed insert
            try {
                context.contentResolver.delete(uri, null, null)
            } catch (cleanupError: Exception) {
                Log.w(TAG, "Failed to clean up failed MediaStore insert: ${cleanupError.message}")
            }
            throw e
        }
    }

    /**
     * Save a downloaded file to MediaStore (convenience method)
     * @param entry Directory entry from FlashAir
     * @param sourceFile Downloaded file
     * @return MediaStore URI
     */
    suspend fun saveEntry(entry: DirectoryEntry, sourceFile: File): Uri {
        return saveToGallery(sourceFile, entry.absolutePath, null)
    }

    // MARK: - Private Helpers

    /**
     * Build relative path for MediaStore from FlashAir absolute path
     * E.g., "/DCIM/100CANON/IMG_0001.JPG" -> "FlashAirImport/DCIM/100CANON"
     */
    private fun buildRelativePath(flashAirPath: String): String {
        // Remove leading slash and filename
        val pathWithoutSlash = flashAirPath.removePrefix("/")
        val dirPath = pathWithoutSlash.substringBeforeLast('/', "")

        return if (dirPath.isNotEmpty()) {
            "$BASE_FOLDER/$dirPath"
        } else {
            BASE_FOLDER
        }
    }

    /**
     * Detect MIME type from file extension
     */
    private fun detectMimeType(extension: String, isImage: Boolean): String {
        return if (isImage) {
            when (extension) {
                "jpg", "jpeg" -> "image/jpeg"
                "png" -> "image/png"
                "heic" -> "image/heic"
                "gif" -> "image/gif"
                "webp" -> "image/webp"
                else -> "image/*"
            }
        } else {
            when (extension) {
                "mp4" -> "video/mp4"
                "mov" -> "video/quicktime"
                "avi" -> "video/x-msvideo"
                "mkv" -> "video/x-matroska"
                "3gp" -> "video/3gpp"
                else -> "video/*"
            }
        }
    }

    /**
     * Check if storage permissions are granted
     */
    fun hasStoragePermission(): Boolean {
        // On Android 10+ with scoped storage, no explicit permission needed for MediaStore writes
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            return true
        }

        // On Android 9 and below, need WRITE_EXTERNAL_STORAGE
        val permission = android.Manifest.permission.WRITE_EXTERNAL_STORAGE
        return context.checkSelfPermission(permission) == android.content.pm.PackageManager.PERMISSION_GRANTED
    }

    /**
     * Get statistics about saved media
     */
    suspend fun getImportedFileStats(): MediaStoreStats = withContext(Dispatchers.IO) {
        var imageCount = 0
        var videoCount = 0
        var totalSize = 0L

        // Query images
        val imageProjection = arrayOf(
            MediaStore.Images.Media._ID,
            MediaStore.Images.Media.SIZE,
            MediaStore.Images.Media.RELATIVE_PATH
        )

        context.contentResolver.query(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            imageProjection,
            null,
            null,
            null
        )?.use { cursor ->
            val sizeColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.SIZE)
            val pathColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.RELATIVE_PATH)

            while (cursor.moveToNext()) {
                val relativePath = cursor.getString(pathColumn)
                if (relativePath?.contains(BASE_FOLDER) == true) {
                    imageCount++
                    totalSize += cursor.getLong(sizeColumn)
                }
            }
        }

        // Query videos
        val videoProjection = arrayOf(
            MediaStore.Video.Media._ID,
            MediaStore.Video.Media.SIZE,
            MediaStore.Video.Media.RELATIVE_PATH
        )

        context.contentResolver.query(
            MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
            videoProjection,
            null,
            null,
            null
        )?.use { cursor ->
            val sizeColumn = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.SIZE)
            val pathColumn = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.RELATIVE_PATH)

            while (cursor.moveToNext()) {
                val relativePath = cursor.getString(pathColumn)
                if (relativePath?.contains(BASE_FOLDER) == true) {
                    videoCount++
                    totalSize += cursor.getLong(sizeColumn)
                }
            }
        }

        MediaStoreStats(
            imageCount = imageCount,
            videoCount = videoCount,
            totalSize = totalSize
        )
    }
}

// MARK: - Supporting Types

/**
 * Statistics about saved media in MediaStore
 */
data class MediaStoreStats(
    val imageCount: Int,
    val videoCount: Int,
    val totalSize: Long
) {
    val totalFiles: Int get() = imageCount + videoCount

    val summary: String
        get() = "$imageCount images, $videoCount videos (${formatBytes(totalSize)})"

    private fun formatBytes(bytes: Long): String {
        val kb = bytes / 1024.0
        val mb = kb / 1024.0
        val gb = mb / 1024.0

        return when {
            gb >= 1.0 -> String.format("%.2f GB", gb)
            mb >= 1.0 -> String.format("%.2f MB", mb)
            kb >= 1.0 -> String.format("%.2f KB", kb)
            else -> "$bytes B"
        }
    }
}
