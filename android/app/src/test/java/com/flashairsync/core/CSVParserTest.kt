package com.flashairsync.core

import org.junit.Test
import org.junit.Assert.*

/**
 * Unit tests for FlashAir CSV parsing and models
 */
class CSVParserTest {

    @Test
    fun testDirectoryEntryCreation() {
        val entry = DirectoryEntry(
            directory = "/DCIM/100CANON",
            name = "IMG_0001.JPG",
            size = 3145728,
            attribute = 32, // 0x20 = archive (regular file)
            fatDate = 19588,
            fatTime = 34560
        )

        assertEquals("/DCIM/100CANON/IMG_0001.JPG", entry.absolutePath)
        assertFalse(entry.isDirectory)
        assertEquals("/DCIM/100CANON/IMG_0001.JPG#3145728", entry.dedupeKey)
    }

    @Test
    fun testDirectoryDetection() {
        val dirEntry = DirectoryEntry(
            directory = "/DCIM",
            name = "100CANON",
            size = 0,
            attribute = 16, // 0x10 = directory
            fatDate = 19588,
            fatTime = 0
        )

        assertTrue("Entry with attribute 0x10 should be directory", dirEntry.isDirectory)

        val fileEntry = DirectoryEntry(
            directory = "/DCIM/100CANON",
            name = "IMG_0001.JPG",
            size = 3145728,
            attribute = 32, // 0x20 = archive
            fatDate = 19588,
            fatTime = 34560
        )

        assertFalse("Entry with attribute 0x20 should be file", fileEntry.isDirectory)
    }

    @Test
    fun testFATDateTimeDecoding() {
        // Test date: 2018-09-20
        val date = 19588
        // Test time: 16:56:00
        val time = 34560

        val decoded = DirectoryEntry.decodeFATDateTime(date, time)

        assertNotNull("Should decode valid FAT datetime", decoded)

        decoded?.let {
            val calendar = java.util.Calendar.getInstance()
            calendar.time = it

            assertEquals("Year should be 2018", 2018, calendar.get(java.util.Calendar.YEAR))
            assertEquals("Month should be September", 8, calendar.get(java.util.Calendar.MONTH)) // 0-indexed
            assertEquals("Day should be 20", 20, calendar.get(java.util.Calendar.DAY_OF_MONTH))
            assertEquals("Hour should be 16", 16, calendar.get(java.util.Calendar.HOUR_OF_DAY))
            assertEquals("Minute should be 56", 56, calendar.get(java.util.Calendar.MINUTE))
            assertEquals("Second should be 0", 0, calendar.get(java.util.Calendar.SECOND))
        }
    }

    @Test
    fun testDedupeKeyGeneration() {
        val entry = DirectoryEntry(
            directory = "/DCIM/100CANON",
            name = "IMG_0001.JPG",
            size = 3145728,
            attribute = 32,
            fatDate = 19588,
            fatTime = 34560
        )

        val expectedKey = "/DCIM/100CANON/IMG_0001.JPG#3145728"
        assertEquals("Dedupe key should be path#size", expectedKey, entry.dedupeKey)
    }

    @Test
    fun testAbsolutePathWithTrailingSlash() {
        val entry1 = DirectoryEntry(
            directory = "/DCIM/",
            name = "IMG_0001.JPG",
            size = 1024,
            attribute = 32,
            fatDate = 0,
            fatTime = 0
        )
        assertEquals("/DCIM/IMG_0001.JPG", entry1.absolutePath)

        val entry2 = DirectoryEntry(
            directory = "/DCIM",
            name = "IMG_0001.JPG",
            size = 1024,
            attribute = 32,
            fatDate = 0,
            fatTime = 0
        )
        assertEquals("/DCIM/IMG_0001.JPG", entry2.absolutePath)
    }

    @Test
    fun testSyncSettingsDefaults() {
        val settings = SyncSettings()

        assertEquals("flashair", settings.ssid)
        assertEquals("12345678", settings.passphrase)
        assertEquals("http://192.168.0.1", settings.host)
        assertEquals(1, settings.concurrentDownloads)
        assertEquals(2000, settings.maxFileSizeMB)
        assertTrue(settings.fileExtensions.contains("jpg"))
        assertTrue(settings.fileExtensions.contains("mp4"))
    }

    @Test
    fun testShouldImportFileFilter() {
        val settings = SyncSettings()

        // Should import JPG
        val jpgEntry = DirectoryEntry(
            directory = "/DCIM",
            name = "IMG_0001.JPG",
            size = 1024,
            attribute = 32,
            fatDate = 0,
            fatTime = 0
        )
        assertTrue(settings.shouldImport(jpgEntry))

        // Should skip TXT
        val txtEntry = DirectoryEntry(
            directory = "/DCIM",
            name = "README.TXT",
            size = 100,
            attribute = 32,
            fatDate = 0,
            fatTime = 0
        )
        assertFalse(settings.shouldImport(txtEntry))

        // Should skip directory
        val dirEntry = DirectoryEntry(
            directory = "/DCIM",
            name = "100CANON",
            size = 0,
            attribute = 16,
            fatDate = 0,
            fatTime = 0
        )
        assertFalse(settings.shouldImport(dirEntry))

        // Should skip file too large
        val customSettings = settings.copy(maxFileSizeMB = 1)
        val largeEntry = DirectoryEntry(
            directory = "/DCIM",
            name = "LARGE.JPG",
            size = 5L * 1024 * 1024, // 5 MB
            attribute = 32,
            fatDate = 0,
            fatTime = 0
        )
        assertFalse(customSettings.shouldImport(largeEntry))
    }

    @Test
    fun testImportResultCalculations() {
        val result = ImportResult(
            totalFiles = 10,
            importedCount = 8,
            skippedCount = 1,
            failedCount = 1,
            totalBytes = 1024L * 1024 * 50, // 50 MB
            duration = 5000, // 5 seconds
            errors = listOf("Error 1")
        )

        assertEquals(0.8, result.successRate, 0.01)
        assertTrue(result.summary.contains("8 files"))
    }
}
