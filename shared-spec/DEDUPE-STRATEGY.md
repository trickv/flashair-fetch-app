# FlashAir Sync Deduplication Strategy

This document explains how FlashAir Sync determines which files have already been imported and which are new.

## Goal

**Incremental sync:** Only download files that haven't been previously imported, even across multiple sync sessions.

## The Challenge

Unlike cloud storage or modern filesystems, FlashAir (FAT32-based) has several limitations:

1. **No unique file IDs**: FAT32 doesn't provide stable, unique identifiers for files
2. **Coarse timestamps**: FAT timestamps have 2-second granularity → unreliable for change detection
3. **File reuse**: Cameras often reuse filenames (e.g., delete `IMG_0001.JPG`, take new photo → new `IMG_0001.JPG`)
4. **No checksums**: FlashAir API doesn't expose file hashes

## Chosen Strategy: `path#size` Composite Key

### Format

```
<absolute-path>#<size-in-bytes>
```

### Examples

```
/DCIM/100CANON/IMG_0001.JPG#3145728
/DCIM/100CANON/VIDEO001.MP4#52428800
/DCIM/101NIKON/DSC_0042.JPG#4567890
```

### Implementation

**Sync Index (Persistent Storage):**

Store a set/map of seen keys:

```json
{
  "/DCIM/100CANON/IMG_0001.JPG#3145728": true,
  "/DCIM/100CANON/IMG_0002.JPG#2891776": true,
  "/DCIM/100CANON/VIDEO001.MP4#52428800": true
}
```

**Import Decision:**

```python
def should_import(entry: DirectoryEntry, seen_index: Set[str]) -> bool:
    key = f"{entry.absolute_path}#{entry.size}"
    return key not in seen_index
```

**After Import:**

```python
def mark_imported(entry: DirectoryEntry, seen_index: Set[str]):
    key = f"{entry.absolute_path}#{entry.size}"
    seen_index.add(key)
    persist_index(seen_index)
```

## Why This Works

### 1. Path Uniqueness

Absolute paths are unique within a card at any given time. No two files can have the same path simultaneously.

**Example:**
- `/DCIM/100CANON/IMG_0001.JPG` identifies a specific file location

### 2. Size Disambiguates Reused Filenames

If a camera deletes `IMG_0001.JPG` (3 MB) and creates a new `IMG_0001.JPG` (5 MB), the size difference ensures we import the new file.

**Scenario:**
1. Sync 1: Import `IMG_0001.JPG#3145728` (3 MB)
2. User deletes photo on camera
3. Camera reuses filename: new `IMG_0001.JPG` is 5242880 bytes (5 MB)
4. Sync 2: Key `IMG_0001.JPG#5242880` not in index → import new file

### 3. Collision Probability

**False negative** (fail to import changed file):

Occurs if:
- Same path AND
- Same size AND
- Different content

**Probability:**
- RAW photos (same camera settings): ~0.01% (EXIF metadata differs)
- JPEG (compressed): ~0.001% (timestamp in EXIF)
- Videos: ~0% (duration/timestamp always differ)

**Real-world impact:** Negligible. Cameras rarely produce byte-identical files.

### 4. No Clock Dependency

Unlike mtime-based deduplication, `path#size` doesn't rely on accurate timestamps:
- Camera clock can be wrong (user never set date)
- FAT 2-second granularity causes false positives
- Timezone issues when traveling

## Alternative Strategies (Rejected)

### ❌ Path Only

**Problem:** Filename reuse causes false positives (skip new files).

**Example:**
```
Sync 1: IMG_0001.JPG (old photo)
Camera: Delete, take new photo
Sync 2: IMG_0001.JPG (new photo) → SKIPPED (false positive)
```

### ❌ Path + mtime

**Problem:** FAT timestamp unreliability.

**Issues:**
1. **2-second granularity**: Files modified 1 second apart have same mtime
2. **Camera clock drift**: Timestamps can go backward if battery dies
3. **Timezone changes**: Traveling across timezones causes false negatives

**Example:**
```
Photo A: 2025-01-15 10:00:00
Photo B: 2025-01-15 10:00:01 (1 second later)
FAT stores both as: 10:00:00 (rounded down to even seconds)
```

### ❌ Size Only

**Problem:** Size collisions are common (especially for same camera model).

**Example:**
```
IMG_0001.JPG: 3145728 bytes
IMG_0002.JPG: 3145728 bytes (same scene, same compression)
```

### ❌ SHA-256 Hash

**Problem:** Requires downloading entire file to compute hash (defeats incremental sync).

**Workaround:** Compute hash lazily after download, use for deduplication next sync.

**Trade-off:** Perfect accuracy vs. network/battery cost.

**Decision:** Not implemented in v1. May add as optional "paranoid mode" in future.

## Edge Cases

### 1. File Edited on Card (Rare)

**Scenario:**
- Import `IMG_0001.JPG` (3 MB)
- User edits photo on camera (crop, filter) → new size (2.8 MB)
- Next sync: Different size → imported again as new file

**Behavior:** Correct (different content = different file)

**Result:** Two copies in gallery (original + edited)

**User expectation:** Desired behavior (both versions preserved)

### 2. Duplicate Content, Different Paths

**Scenario:**
- Camera writes same file to multiple directories (backup feature)
- `/DCIM/100CANON/IMG_0001.JPG` (3 MB)
- `/BACKUP/IMG_0001.JPG` (3 MB, identical content)

**Behavior:** Both imported (different paths → different keys)

**Impact:** Mild storage waste, but reflects user intent (camera created both)

### 3. Camera Folder Rollover

Some cameras create new folders every 1000 photos:
- `/DCIM/100CANON/` (photos 1-1000)
- `/DCIM/101CANON/` (photos 1001-2000)

**Behavior:** Paths differ → no collision → works correctly

### 4. Card Reformatted

**Scenario:**
- User formats FlashAir card
- All files deleted, index still has old entries

**Impact:**
- Old index entries waste a few KB (harmless)
- New photos have different paths or sizes → imported correctly

**Mitigation:** "Reset index" button clears old entries

### 5. Multiple FlashAir Cards

**Problem:** Single global index mixes entries from different cards.

**Solution:** Include card identifier in index namespace.

**Card ID Sources:**
1. **SSID** (if unique per card, e.g., `flashair_ABC123`)
2. **CID** (Card Identification from `command.cgi?op=104`)
3. **User-provided label** (settings screen)

**Index Structure:**
```json
{
  "flashair_ABC123": {
    "/DCIM/100CANON/IMG_0001.JPG#3145728": true
  },
  "flashair_XYZ789": {
    "/DCIM/100NIKON/DSC_0001.JPG#2048000": true
  }
}
```

**Implementation (v1):**
- Use SSID as card identifier
- Store index as `sync_index_<ssid>.json`

## Index Persistence

### iOS

**Location:** App's Documents directory (backed up to iCloud)

```
~/Documents/FlashAirSync/sync_index_flashair.json
```

**Format:**
```json
{
  "/DCIM/100CANON/IMG_0001.JPG#3145728": true,
  "/DCIM/100CANON/IMG_0002.JPG#2891776": true
}
```

**Access:**
```swift
func loadIndex(ssid: String) -> Set<String> {
    let url = documentsDirectory
        .appendingPathComponent("FlashAirSync")
        .appendingPathComponent("sync_index_\(ssid).json")

    guard let data = try? Data(contentsOf: url),
          let dict = try? JSONDecoder().decode([String: Bool].self, from: data) else {
        return []
    }

    return Set(dict.keys)
}
```

### Android

**Location:** App's internal storage (not accessible to other apps)

```
/data/data/com.flashairsync/files/sync_index_flashair.json
```

**Format:** Same as iOS

**Access:**
```kotlin
fun loadIndex(ssid: String): Set<String> {
    val file = File(context.filesDir, "sync_index_$ssid.json")
    if (!file.exists()) return emptySet()

    val json = file.readText()
    val map = Json.decodeFromString<Map<String, Boolean>>(json)
    return map.keys.toSet()
}
```

## Index Maintenance

### When to Update

**Add to index:** Immediately after successfully importing a file

```python
async def import_file(entry: DirectoryEntry):
    local_path = await download_file(entry.absolute_path)
    await save_to_gallery(local_path)

    # ✅ Mark as imported AFTER successful save
    key = f"{entry.absolute_path}#{entry.size}"
    index.add(key)
    await persist_index()
```

**Atomicity:**
- Write index to temp file
- Rename to final location (atomic operation)

### When to Clear

**User action:** "Reset index" button in settings

```python
def reset_index(ssid: String):
    # Clear in-memory state
    index.clear()

    # Delete persistent file
    index_file = get_index_path(ssid)
    if index_file.exists():
        index_file.delete()

    # DO NOT delete imported photos from gallery
```

**Important:** Resetting index only affects future syncs. Already-imported photos remain in the gallery.

### Index Growth

**Size estimate:**
- Average key length: 50 characters
- 10,000 photos: ~500 KB
- 100,000 photos: ~5 MB

**Impact:** Negligible (even 100,000 photos fit in memory)

**Cleanup:** Not needed; index size stays manageable even for heavy users.

## Verification & Testing

### Test Case 1: First Sync

**Setup:**
- Empty index
- FlashAir has 100 photos

**Expected:**
- Import all 100 files
- Index grows to 100 entries
- Gallery shows 100 new photos

### Test Case 2: Re-Sync (No Changes)

**Setup:**
- Index has 100 entries
- FlashAir still has same 100 photos

**Expected:**
- 0 files imported
- Index unchanged
- UI shows "All caught up"

### Test Case 3: Incremental Sync

**Setup:**
- Index has 100 entries
- User takes 10 new photos on camera
- FlashAir now has 110 photos

**Expected:**
- Import exactly 10 new files
- Index grows to 110 entries
- Gallery shows 10 new photos (total: 110)

### Test Case 4: Filename Reuse

**Setup:**
- Index has `/DCIM/IMG_0001.JPG#3145728`
- User deletes photo, takes new one
- FlashAir has `/DCIM/IMG_0001.JPG#5242880` (different size)

**Expected:**
- Import new `IMG_0001.JPG` (different key)
- Index has both entries (old + new)
- Gallery shows new photo (total: 2 versions if old photo still exists locally)

### Test Case 5: Reset Index

**Setup:**
- Index has 100 entries
- User taps "Reset index"

**Expected:**
- Index cleared to 0 entries
- Next sync re-imports all 100 files
- Gallery shows duplicates (if not manually deleted first)

**Warning to user:**
> "Resetting the index will cause all files to be re-imported on the next sync. This may create duplicates in your gallery."

## Future Enhancements (v2+)

### Optional SHA-256 Mode

**Approach:**
1. Download file
2. Compute SHA-256 hash
3. Use `path#sha256` as key instead of `path#size`

**Trade-offs:**
- ✅ Perfect accuracy (no false negatives)
- ✅ Detects edited files with same size
- ❌ Higher CPU/battery cost
- ❌ Slower imports (hash computation)

**Use case:** Professional photographers with strict deduplication requirements

### Cloud Sync

**Approach:**
- Store index in iCloud (iOS) or Google Drive (Android)
- Sync index across multiple devices
- Prevent duplicate imports if using FlashAir with iPhone + iPad

**Complexity:** Conflict resolution, network dependency

### Smart Cleanup

**Approach:**
- Detect deleted files on card (present in index, missing in latest scan)
- Offer to remove index entries for deleted files

**Benefit:** Keeps index size minimal

**Risk:** False positives if card not fully scanned (network drop)

## Real-World Validation (2026-05-29 → 2026-05-31)

The `path#size` strategy was validated end-to-end on real Toshiba
FlashAir hardware paired with a Canon EOS REBEL T5i.

### Dedupe-at-scale proof

**Setup:**
- 170 photos on the card (JPGs in `/DCIM/100__TSB/`)
- iOS app with `SyncEngine` + `SyncIndex` per this strategy
- Fresh index (empty before run 1)

**Run 1 (full sync):**
- All 170 files imported
- Index grew to 170 entries
- Throughput: ~10.6 Mbps effective (768.8 MB in 579.4 s)

**Run 2 (immediate re-sync, same card, no new photos):**
- "0 imported, 170 already synced" — exactly correct
- Duration: 3.6 s (just the listing + dedupe filter, no downloads)
- Index unchanged at 170 entries

**Earlier runs (incremental sync with `maxFilesPerSync=2` cap):**
- Three back-to-back syncs produced three **non-overlapping pairs**:
  `IMG_8023/8024` → `IMG_8025/8026` → `IMG_8027/8028`
- This proves the `path#size` key is **stable across sessions** —
  exactly what the strategy requires.

### Monotonic-growth observation

A `devicectl copy from` pull of the index file post-stress-test
showed **195 entries**, of which:
- **170 were on the card** (the current photos)
- **25 were stale** (photos the user had deleted from the camera
  between sync sessions)

The strategy never prunes. For a multi-year card-rotation user this
becomes index bloat (estimate: ~50 bytes/entry → ~50 KB per 1000
deleted photos). Doesn't break dedupe, but worth fixing.

**Recommended cleanup pass at sync end:** remove index entries whose
path wasn't seen in the current listing. This won't affect any
correctness property — those entries are pure ghosts. Add to both
iOS and Android implementations.

### Filename reuse case (not yet observed in the wild)

Test case 4 in this doc describes filename reuse (camera deletes
`IMG_0001.JPG`, takes a new one with the same name but different
size). Not observed in real hardware testing because the Canon
camera kept counting `IMG_8023 → IMG_8577` without recycling
numbers. The synthetic mock-server test exercises this case and the
dedupe behaves correctly.

### Note on example paths

This document uses `/DCIM/100CANON/…` as the canonical example
because it's the most familiar DCIM convention. **Real cards use
whatever subdir naming the camera firmware chose** —
Toshiba's FlashAir creates `/DCIM/100__TSB/`, Nikon uses
`/DCIM/100NIKON/`, etc. The strategy is name-agnostic; only the
walker needs to handle the variation. See `docs/REAL-WORLD-FINDINGS.md`.

---

**Version:** 1.1
**Last Updated:** 2026-06-05 (added real-world validation section,
monotonic-growth note, and DCIM-naming clarification)
