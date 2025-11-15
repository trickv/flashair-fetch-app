package com.flashairsync.core

import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

/**
 * HTTP client for FlashAir SD card API
 */
class FlashAirClient(private val host: String) {

    companion object {
        private const val TAG = "FlashAirClient"
        private const val TIMEOUT_CONNECT = 10_000 // 10 seconds
        private const val TIMEOUT_READ = 30_000 // 30 seconds
    }

    // MARK: - Directory Listing

    /**
     * List directory contents via command.cgi?op=100
     * @param path Absolute directory path (e.g., "/DCIM")
     * @return List of directory entries
     */
    suspend fun listDirectory(path: String): List<DirectoryEntry> = withContext(Dispatchers.IO) {
        val encodedPath = URLEncoder.encode(path, "UTF-8")
        val urlString = "$host/command.cgi?op=100&DIR=$encodedPath"

        Log.d(TAG, "Listing directory: $path")

        val url = URL(urlString)
        val connection = url.openConnection() as HttpURLConnection

        try {
            connection.connectTimeout = TIMEOUT_CONNECT
            connection.readTimeout = TIMEOUT_READ
            connection.requestMethod = "GET"

            val responseCode = connection.responseCode
            if (responseCode != HttpURLConnection.HTTP_OK) {
                throw FlashAirError.InvalidResponse
            }

            val csvText = connection.inputStream.bufferedReader().use { it.readText() }
            parseCSV(csvText, path)

        } finally {
            connection.disconnect()
        }
    }

    /**
     * Recursively walk directory tree and collect all entries
     * @param rootPath Starting directory path
     * @param filter Optional filter predicate
     * @return List of all file entries (not directories)
     */
    suspend fun walkDirectory(
        rootPath: String,
        filter: ((DirectoryEntry) -> Boolean)? = null
    ): List<DirectoryEntry> = withContext(Dispatchers.IO) {
        val allFiles = mutableListOf<DirectoryEntry>()
        val directoriesToVisit = mutableListOf(rootPath)

        while (directoriesToVisit.isNotEmpty()) {
            val currentDir = directoriesToVisit.removeFirst()

            try {
                val entries = listDirectory(currentDir)

                for (entry in entries) {
                    // Skip hidden files (start with .)
                    if (entry.name.startsWith(".")) {
                        continue
                    }

                    if (entry.isDirectory) {
                        // Add subdirectory to visit queue
                        directoriesToVisit.add(entry.absolutePath)
                    } else {
                        // Apply filter if provided
                        if (filter == null || filter(entry)) {
                            allFiles.add(entry)
                        }
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "Failed to list directory $currentDir: ${e.message}")
            }
        }

        allFiles
    }

    // MARK: - File Download

    /**
     * Download a file from FlashAir card
     * @param path Absolute file path on the card
     * @param destFile Destination file
     * @param progress Optional progress callback (0.0 to 1.0)
     */
    suspend fun downloadFile(
        path: String,
        destFile: File,
        progress: ((Float) -> Unit)? = null
    ): Unit = withContext(Dispatchers.IO) {
        val urlString = "$host$path"
        Log.d(TAG, "Downloading: $path")

        val url = URL(urlString)
        val connection = url.openConnection() as HttpURLConnection

        try {
            connection.connectTimeout = TIMEOUT_CONNECT
            connection.readTimeout = TIMEOUT_READ
            connection.requestMethod = "GET"

            val responseCode = connection.responseCode
            if (responseCode != HttpURLConnection.HTTP_OK) {
                throw FlashAirError.FileNotFound(path)
            }

            val totalBytes = connection.contentLengthLong
            var downloadedBytes = 0L

            connection.inputStream.use { input ->
                destFile.outputStream().use { output ->
                    val buffer = ByteArray(8192)
                    var bytesRead: Int

                    while (input.read(buffer).also { bytesRead = it } != -1) {
                        output.write(buffer, 0, bytesRead)
                        downloadedBytes += bytesRead

                        // Report progress
                        if (totalBytes > 0) {
                            progress?.invoke(downloadedBytes.toFloat() / totalBytes)
                        }
                    }
                }
            }

            Log.d(TAG, "Downloaded: $path (${destFile.length()} bytes)")

        } finally {
            connection.disconnect()
        }
    }

    // MARK: - Card Configuration

    /**
     * Get FlashAir card configuration
     * @return Map of configuration values
     */
    suspend fun getCardConfig(): Map<String, String> = withContext(Dispatchers.IO) {
        val urlString = "$host/command.cgi?op=104"
        val url = URL(urlString)
        val connection = url.openConnection() as HttpURLConnection

        try {
            connection.connectTimeout = TIMEOUT_CONNECT
            connection.readTimeout = TIMEOUT_READ
            connection.requestMethod = "GET"

            val responseCode = connection.responseCode
            if (responseCode != HttpURLConnection.HTTP_OK) {
                throw FlashAirError.InvalidResponse
            }

            val text = connection.inputStream.bufferedReader().use { it.readText() }

            text.lines()
                .filter { it.contains("=") }
                .associate {
                    val parts = it.split("=", limit = 2)
                    parts[0] to parts.getOrElse(1) { "" }
                }

        } finally {
            connection.disconnect()
        }
    }

    // MARK: - CSV Parsing

    /**
     * Parse FlashAir CSV directory listing
     * @param csvText Raw CSV response text
     * @param requestDir Directory path from the request (for 5-field format fallback)
     * @return List of parsed entries
     */
    private fun parseCSV(csvText: String, requestDir: String): List<DirectoryEntry> {
        val entries = mutableListOf<DirectoryEntry>()

        val lines = csvText.lines()

        for (line in lines) {
            val trimmed = line.trim()

            // Skip empty lines
            if (trimmed.isEmpty()) continue

            // Skip header
            if (trimmed.startsWith("WLANSD_FILELIST")) continue

            // Parse CSV fields
            val fields = trimmed.split(",")

            // Support both 6-field and 5-field formats
            val entry = when (fields.size) {
                6 -> parseEntry6Field(fields)
                5 -> parseEntry5Field(fields, requestDir)
                else -> {
                    Log.w(TAG, "Skipping malformed CSV line (expected 5 or 6 fields): $trimmed")
                    null
                }
            }

            entry?.let { entries.add(it) }
        }

        return entries
    }

    /**
     * Parse 6-field CSV format
     */
    private fun parseEntry6Field(fields: List<String>): DirectoryEntry? {
        return try {
            DirectoryEntry(
                directory = fields[0],
                name = fields[1],
                size = fields[2].toLong(),
                attribute = fields[3].toInt(),
                fatDate = fields[4].toInt(),
                fatTime = fields[5].toInt()
            )
        } catch (e: Exception) {
            Log.w(TAG, "Failed to parse 6-field entry: ${e.message}")
            null
        }
    }

    /**
     * Parse 5-field CSV format (legacy)
     */
    private fun parseEntry5Field(fields: List<String>, directory: String): DirectoryEntry? {
        return try {
            DirectoryEntry(
                directory = directory,
                name = fields[0],
                size = fields[1].toLong(),
                attribute = fields[2].toInt(),
                fatDate = fields[3].toInt(),
                fatTime = fields[4].toInt()
            )
        } catch (e: Exception) {
            Log.w(TAG, "Failed to parse 5-field entry: ${e.message}")
            null
        }
    }
}
