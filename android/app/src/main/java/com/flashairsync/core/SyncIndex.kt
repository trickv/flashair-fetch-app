package com.flashairsync.core

import android.content.Context
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File

/**
 * Manages persistent sync state for deduplication
 */
class SyncIndex(private val context: Context, private val ssid: String) {

    companion object {
        private const val TAG = "SyncIndex"
    }

    private val seenKeys = mutableSetOf<String>()
    private val indexFile: File

    init {
        // Index file path: sync_index_<ssid>.json
        val sanitizedSSID = ssid.replace("/", "_")
        indexFile = File(context.filesDir, "sync_index_$sanitizedSSID.json")

        // Load existing index
        loadFromDisk()
    }

    // MARK: - Public API

    /**
     * Check if an entry has been previously synced
     */
    fun hasSeen(entry: DirectoryEntry): Boolean {
        return seenKeys.contains(entry.dedupeKey)
    }

    /**
     * Mark an entry as synced
     */
    fun markSeen(entry: DirectoryEntry) {
        seenKeys.add(entry.dedupeKey)
    }

    /**
     * Mark multiple entries as synced
     */
    fun markSeen(entries: List<DirectoryEntry>) {
        entries.forEach { seenKeys.add(it.dedupeKey) }
    }

    /**
     * Get count of seen entries
     */
    fun count(): Int = seenKeys.size

    /**
     * Reset the index (clear all entries)
     */
    suspend fun reset() = withContext(Dispatchers.IO) {
        seenKeys.clear()
        if (indexFile.exists()) {
            indexFile.delete()
        }
        Log.i(TAG, "Index reset")
    }

    /**
     * Persist current state to disk
     */
    suspend fun persist() = withContext(Dispatchers.IO) {
        try {
            // Convert set to JSON object
            val jsonObject = JSONObject()
            seenKeys.forEach { key ->
                jsonObject.put(key, true)
            }

            // Atomic write: write to temp file, then rename
            val tempFile = File(context.filesDir, "${indexFile.name}.tmp")
            tempFile.writeText(jsonObject.toString(2))
            tempFile.renameTo(indexFile)

            Log.d(TAG, "Index persisted (${seenKeys.size} entries)")

        } catch (e: Exception) {
            Log.e(TAG, "Failed to persist index: ${e.message}")
        }
    }

    // MARK: - Persistence

    /**
     * Load index from disk
     */
    private fun loadFromDisk() {
        if (!indexFile.exists()) {
            Log.d(TAG, "No existing index found")
            return
        }

        try {
            val jsonText = indexFile.readText()
            val jsonObject = JSONObject(jsonText)

            seenKeys.clear()
            jsonObject.keys().forEach { key ->
                seenKeys.add(key)
            }

            Log.d(TAG, "Loaded index with ${seenKeys.size} entries")

        } catch (e: Exception) {
            Log.e(TAG, "Failed to load index from ${indexFile.path}: ${e.message}")
            seenKeys.clear()
        }
    }

    /**
     * Export index as JSON string (for debugging/support)
     */
    fun exportJSON(): String {
        val jsonObject = JSONObject()
        seenKeys.forEach { key ->
            jsonObject.put(key, true)
        }
        return jsonObject.toString(2)
    }

    /**
     * Get statistics about the index
     */
    fun getStats(): IndexStats {
        return IndexStats(
            totalEntries = seenKeys.size,
            fileURL = indexFile.absolutePath,
            fileSizeBytes = if (indexFile.exists()) indexFile.length() else 0
        )
    }
}

// MARK: - Supporting Types

data class IndexStats(
    val totalEntries: Int,
    val fileURL: String,
    val fileSizeBytes: Long
) {
    val fileSizeFormatted: String
        get() {
            val kb = fileSizeBytes / 1024.0
            val mb = kb / 1024.0
            return when {
                mb >= 1.0 -> String.format("%.2f MB", mb)
                kb >= 1.0 -> String.format("%.2f KB", kb)
                else -> "$fileSizeBytes B"
            }
        }
}
