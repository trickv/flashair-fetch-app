package com.flashairsync.core

import android.content.Context
import android.net.Network
import android.os.Build
import android.util.Log
import androidx.annotation.RequiresApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import java.io.File

/**
 * Main sync orchestrator
 * Coordinates WiFi connection, file discovery, download, and MediaStore saving
 */
@RequiresApi(Build.VERSION_CODES.Q)
class SyncEngine(
    private val context: Context,
    private val settings: SyncSettings
) {

    companion object {
        private const val TAG = "SyncEngine"
        private const val MAX_RETRIES = 3
        private const val RETRY_DELAY_MS = 2000L
    }

    private val wifiConnector = WiFiConnector(context)
    private val syncIndex = SyncIndex(context, settings.ssid)
    private val mediaStoreWriter = MediaStoreWriter(context)

    private val _syncState = MutableStateFlow<SyncState>(SyncState.Idle)
    val syncState: StateFlow<SyncState> = _syncState.asStateFlow()

    private val _importItems = MutableStateFlow<List<ImportItem>>(emptyList())
    val importItems: StateFlow<List<ImportItem>> = _importItems.asStateFlow()

    private var isCancelled = false

    // MARK: - Public API

    /**
     * Start sync operation
     * @param rootPath Starting directory (e.g., "/DCIM")
     * @return ImportResult with statistics
     */
    suspend fun startSync(rootPath: String = "/DCIM"): ImportResult = withContext(Dispatchers.IO) {
        isCancelled = false
        val startTime = System.currentTimeMillis()

        try {
            // Step 1: Connect to WiFi
            _syncState.value = SyncState.ConnectingWiFi
            Log.d(TAG, "Connecting to WiFi: ${settings.ssid}")

            val network = wifiConnector.connect(settings.ssid, settings.passphrase)
            _syncState.value = SyncState.WiFiConnected(network)

            // Step 2: Discover files
            _syncState.value = SyncState.Discovering
            Log.d(TAG, "Discovering files in $rootPath")

            val client = FlashAirClient(settings.host)
            val allEntries = client.walkDirectory(rootPath) { entry ->
                settings.shouldImport(entry)
            }

            Log.d(TAG, "Found ${allEntries.size} eligible files")

            // Step 3: Filter out already-synced files
            val newEntries = allEntries.filter { !syncIndex.hasSeen(it) }
            Log.d(TAG, "New files to import: ${newEntries.size}, Already synced: ${allEntries.size - newEntries.size}")

            if (newEntries.isEmpty()) {
                _syncState.value = SyncState.Completed(
                    ImportResult(
                        totalFiles = 0,
                        importedCount = 0,
                        skippedCount = allEntries.size,
                        failedCount = 0,
                        totalBytes = 0,
                        duration = System.currentTimeMillis() - startTime,
                        errors = emptyList()
                    )
                )

                // Disconnect WiFi
                wifiConnector.disconnect()

                return@withContext _syncState.value.let { it as SyncState.Completed }.result
            }

            // Step 4: Create import items
            val items = newEntries.map { ImportItem(it) }
            _importItems.value = items
            _syncState.value = SyncState.Downloading(0, items.size)

            // Step 5: Download and save files
            var importedCount = 0
            var failedCount = 0
            var totalBytes = 0L
            val errors = mutableListOf<String>()

            for ((index, item) in items.withIndex()) {
                if (isCancelled) {
                    Log.d(TAG, "Sync cancelled by user")
                    throw FlashAirError.Cancelled
                }

                try {
                    // Update item state
                    updateItemState(item.id, ImportState.Downloading(0f))

                    // Download file with retries
                    val tempFile = downloadFileWithRetry(client, item.entry) { progress ->
                        updateItemState(item.id, ImportState.Downloading(progress))
                    }

                    // Save to MediaStore
                    updateItemState(item.id, ImportState.Saving)
                    val uri = mediaStoreWriter.saveEntry(item.entry, tempFile)
                    Log.d(TAG, "Saved ${item.entry.name} to MediaStore: $uri")

                    // Update sync index
                    syncIndex.markSeen(item.entry)

                    // Mark as completed
                    updateItemState(item.id, ImportState.Completed)
                    importedCount++
                    totalBytes += item.entry.size

                    // Clean up temp file
                    tempFile.delete()

                } catch (e: Exception) {
                    Log.e(TAG, "Failed to import ${item.entry.name}: ${e.message}", e)
                    updateItemState(item.id, ImportState.Failed(e.message ?: "Unknown error"))
                    errors.add("${item.entry.name}: ${e.message}")
                    failedCount++
                }

                // Update progress
                _syncState.value = SyncState.Downloading(index + 1, items.size)
            }

            // Step 6: Persist sync index
            syncIndex.persist()

            // Step 7: Build result
            val result = ImportResult(
                totalFiles = items.size,
                importedCount = importedCount,
                skippedCount = allEntries.size - newEntries.size,
                failedCount = failedCount,
                totalBytes = totalBytes,
                duration = System.currentTimeMillis() - startTime,
                errors = errors
            )

            _syncState.value = SyncState.Completed(result)
            Log.d(TAG, "Sync completed: ${result.summary}")

            result

        } catch (e: Exception) {
            Log.e(TAG, "Sync failed: ${e.message}", e)
            _syncState.value = SyncState.Failed(e.message ?: "Unknown error")
            throw e

        } finally {
            // Always disconnect WiFi
            wifiConnector.disconnect()
        }
    }

    /**
     * Cancel ongoing sync operation
     */
    fun cancel() {
        isCancelled = true
        wifiConnector.disconnect()
        _syncState.value = SyncState.Idle
    }

    /**
     * Reset sync index (clear all seen files)
     */
    suspend fun resetIndex() {
        syncIndex.reset()
    }

    /**
     * Get sync index statistics
     */
    fun getIndexStats(): IndexStats {
        return syncIndex.getStats()
    }

    // MARK: - Private Helpers

    /**
     * Download file with retry logic
     */
    private suspend fun downloadFileWithRetry(
        client: FlashAirClient,
        entry: DirectoryEntry,
        onProgress: (Float) -> Unit
    ): File {
        var lastException: Exception? = null

        repeat(MAX_RETRIES) { attempt ->
            try {
                // Create temp file
                val tempFile = File.createTempFile(
                    "flashair_",
                    "_${entry.name}",
                    context.cacheDir
                )

                // Download
                client.downloadFile(entry.absolutePath, tempFile, onProgress)

                // Verify size
                if (tempFile.length() != entry.size) {
                    tempFile.delete()
                    throw Exception("Size mismatch: expected ${entry.size}, got ${tempFile.length()}")
                }

                return tempFile

            } catch (e: Exception) {
                lastException = e
                Log.w(TAG, "Download attempt ${attempt + 1} failed: ${e.message}")

                if (attempt < MAX_RETRIES - 1) {
                    delay(RETRY_DELAY_MS * (attempt + 1))
                }
            }
        }

        throw lastException ?: Exception("Download failed after $MAX_RETRIES attempts")
    }

    /**
     * Update import item state
     */
    private fun updateItemState(itemId: String, newState: ImportState) {
        val updatedItems = _importItems.value.map { item ->
            if (item.id == itemId) {
                item.copy(state = newState)
            } else {
                item
            }
        }
        _importItems.value = updatedItems
    }
}

// MARK: - Sync State

/**
 * Overall sync operation state
 */
sealed class SyncState {
    object Idle : SyncState()
    object ConnectingWiFi : SyncState()
    data class WiFiConnected(val network: Network) : SyncState()
    object Discovering : SyncState()
    data class Downloading(val current: Int, val total: Int) : SyncState()
    data class Completed(val result: ImportResult) : SyncState()
    data class Failed(val error: String) : SyncState()

    val isActive: Boolean
        get() = this !is Idle && this !is Completed && this !is Failed

    val progressPercent: Float
        get() = when (this) {
            is Downloading -> if (total > 0) current.toFloat() / total else 0f
            is Completed -> 1f
            else -> 0f
        }

    val statusMessage: String
        get() = when (this) {
            is Idle -> "Ready"
            is ConnectingWiFi -> "Connecting to WiFi..."
            is WiFiConnected -> "Connected"
            is Discovering -> "Discovering files..."
            is Downloading -> "Downloading $current of $total files"
            is Completed -> "Sync complete: ${result.importedCount} files imported"
            is Failed -> "Failed: $error"
        }
}
