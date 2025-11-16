package com.flashairsync.core

import java.text.SimpleDateFormat
import java.util.*

// MARK: - Directory Entry

/**
 * Represents a file or directory entry from FlashAir CSV listing
 */
data class DirectoryEntry(
    val directory: String,
    val name: String,
    val size: Long,
    val attribute: Int,
    val fatDate: Int,
    val fatTime: Int
) {
    val absolutePath: String = buildAbsolutePath(directory, name)
    val isDirectory: Boolean = (attribute and 0x10) != 0
    val dedupeKey: String = "$absolutePath#$size"
    val modifiedAt: Date? = decodeFATDateTime(fatDate, fatTime)

    companion object {
        private fun buildAbsolutePath(dir: String, name: String): String {
            return if (dir.endsWith("/")) {
                "$dir$name"
            } else {
                "$dir/$name"
            }
        }

        /**
         * Decode FAT date/time into Java Date
         */
        fun decodeFATDateTime(date: Int, time: Int): Date? {
            if (date == 0) return null

            val year = ((date shr 9) and 0x7F) + 1980
            val month = (date shr 5) and 0x0F
            val day = date and 0x1F

            val hour = (time shr 11) and 0x1F
            val minute = (time shr 5) and 0x3F
            val second = (time and 0x1F) * 2

            // Validate ranges
            if (month !in 1..12 || day !in 1..31 || hour > 23 || minute > 59) {
                return null
            }

            return try {
                Calendar.getInstance().apply {
                    set(year, month - 1, day, hour, minute, second)
                    set(Calendar.MILLISECOND, 0)
                }.time
            } catch (e: Exception) {
                null
            }
        }
    }
}

// MARK: - Sync Settings

/**
 * User-configurable sync settings
 */
data class SyncSettings(
    val ssid: String = "flashair",
    val passphrase: String = "12345678",
    val host: String = "http://192.168.0.1",
    val fileExtensions: List<String> = listOf("jpg", "jpeg", "png", "heic", "mp4", "mov"),
    val concurrentDownloads: Int = 1,
    val maxFileSizeMB: Int = 2000
) {
    fun shouldImport(entry: DirectoryEntry): Boolean {
        // Skip directories
        if (entry.isDirectory) return false

        // Check file extension
        val ext = entry.name.substringAfterLast('.', "").lowercase()
        if (ext !in fileExtensions) return false

        // Check file size
        val sizeMB = entry.size / (1024 * 1024)
        if (sizeMB > maxFileSizeMB) return false

        return true
    }
}

// MARK: - Import State

/**
 * State of a file import operation
 */
sealed class ImportState {
    object Pending : ImportState()
    data class Downloading(val progress: Float) : ImportState()
    object Saving : ImportState()
    object Completed : ImportState()
    data class Failed(val error: String) : ImportState()
    data class Skipped(val reason: String) : ImportState()

    val isComplete: Boolean get() = this is Completed
    val isFailed: Boolean get() = this is Failed
}

/**
 * Import item with state tracking
 */
data class ImportItem(
    val entry: DirectoryEntry,
    var state: ImportState = ImportState.Pending
) {
    val id: String get() = entry.absolutePath
}

// MARK: - Import Result

/**
 * Summary of an import session
 */
data class ImportResult(
    val totalFiles: Int,
    val importedCount: Int,
    val skippedCount: Int,
    val failedCount: Int,
    val totalBytes: Long,
    val duration: Long, // milliseconds
    val errors: List<String>
) {
    val successRate: Double
        get() = if (totalFiles > 0) importedCount.toDouble() / totalFiles else 0.0

    val summary: String
        get() = """
            Imported: $importedCount files (${formatBytes(totalBytes)})
            Skipped: $skippedCount files
            Failed: $failedCount files
            Duration: ${duration / 1000.0}s
        """.trimIndent()

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

// MARK: - Errors

/**
 * FlashAir-specific errors
 */
sealed class FlashAirError : Exception() {
    data class NetworkError(override val cause: Throwable) : FlashAirError() {
        override val message: String = "Network error: ${cause.message}"
    }

    object InvalidResponse : FlashAirError() {
        override val message: String = "Invalid response from FlashAir card"
    }

    data class CSVParseError(val details: String) : FlashAirError() {
        override val message: String = "Failed to parse directory listing: $details"
    }

    data class FileNotFound(val path: String) : FlashAirError() {
        override val message: String = "File not found: $path"
    }

    object PermissionDenied : FlashAirError() {
        override val message: String = "Permission denied. Please grant access in Settings."
    }

    object Cancelled : FlashAirError() {
        override val message: String = "Operation cancelled"
    }

    object WiFiConnectionFailed : FlashAirError() {
        override val message: String = "Failed to connect to FlashAir Wi-Fi network"
    }
}
