# FlashAir CSV Format Specification

This document details the CSV response format for FlashAir's `command.cgi?op=100` directory listing API.

## Format Overview

The response is a **CSV (Comma-Separated Values)** file with 6 fields per line (or 5 fields on some models).

### Standard Format (6 fields)

```
<directory>,<name>,<size>,<attribute>,<date>,<time>
```

### Alternate Format (5 fields, legacy models)

Some W-02 cards omit the `<directory>` field:

```
<name>,<size>,<attribute>,<date>,<time>
```

FlashAir Sync supports both formats.

## Field Definitions

### 1. Directory (string)

**Description:** Parent directory path (included in 6-field format only)

**Format:** Absolute path without trailing slash

**Examples:**
- `/DCIM`
- `/DCIM/100CANON`
- `/MP_ROOT/100ANV01`

**Notes:**
- Always matches the `DIR` parameter in the request
- Omitted in 5-field format (must infer from request context)

### 2. Name (string)

**Description:** File or subdirectory name (without path)

**Format:** 8.3 filename (FAT) or long filename (if supported)

**Examples:**
- `IMG_0001.JPG`
- `100CANON` (directory)
- `DCIM` (directory)
- `VIDEO~1.MP4` (8.3 short name)

**Constraints:**
- Case-insensitive (FAT filesystem)
- May contain spaces
- Special characters: avoid `< > : " / \ | ? *`

### 3. Size (integer)

**Description:** File size in bytes

**Format:** Decimal integer

**Examples:**
- `3145728` (3 MB JPEG)
- `52428800` (50 MB video)
- `0` (directory or empty file)

**Notes:**
- Directories always have size `0`
- Maximum file size: 4 GB - 1 byte (FAT32 limit: `4294967295`)

### 4. Attribute (integer)

**Description:** DOS file attributes (16-bit bitmask)

**Format:** Decimal integer

**Bitmask Values:**

| Bit | Value | Name | Description |
|-----|-------|------|-------------|
| 0 | 0x01 | Read-Only | File is read-only |
| 1 | 0x02 | Hidden | File is hidden |
| 2 | 0x04 | System | System file |
| 3 | 0x08 | Volume Label | Volume label (not used for files) |
| 4 | 0x10 | Directory | Entry is a directory |
| 5 | 0x20 | Archive | File modified since last backup |

**Common Values:**
- `16` (`0x10`): Directory
- `32` (`0x20`): Regular file (archive bit set)
- `33` (`0x21`): Read-only file (archive + read-only)
- `48` (`0x30`): Directory + archive (rare)

**Directory Detection:**
```python
is_directory = (attribute & 0x10) != 0
```

**Examples:**
- `IMG_0001.JPG` → `32` (archive bit, regular file)
- `100CANON` → `16` (directory)
- `CONFIG.TXT` → `33` (read-only + archive)

### 5. Date (integer)

**Description:** File modification date (FAT 16-bit packed format)

**Format:** Decimal integer (0-65535)

**Bit Layout:**

| Bits | Field | Range | Description |
|------|-------|-------|-------------|
| 15-9 | Year | 0-127 | Years since 1980 (1980-2107) |
| 8-5 | Month | 1-12 | Month of year |
| 4-0 | Day | 1-31 | Day of month |

**Decoding Formula:**
```python
year = ((date >> 9) & 0x7F) + 1980
month = (date >> 5) & 0x0F
day = date & 0x1F
```

**Example:**
```
Date: 19588
Binary: 0100110010010100
Year: (0x4C >> 0) = 76 → 1980 + 38 = 2018
Month: 0x09 = 9 (September)
Day: 0x14 = 20

Result: 2018-09-20
```

**Edge Cases:**
- `0`: Invalid/unknown date (treat as "unknown")
- Camera not set: Often defaults to `1980-01-01` or `2000-01-01`

### 6. Time (integer)

**Description:** File modification time (FAT 16-bit packed format)

**Format:** Decimal integer (0-65535)

**Bit Layout:**

| Bits | Field | Range | Description |
|------|-------|-------|-------------|
| 15-11 | Hour | 0-23 | Hour of day (24-hour) |
| 10-5 | Minute | 0-59 | Minute of hour |
| 4-0 | Second/2 | 0-29 | Seconds divided by 2 (0-58 even seconds) |

**Decoding Formula:**
```python
hour = (time >> 11) & 0x1F
minute = (time >> 5) & 0x3F
second = (time & 0x1F) * 2
```

**Example:**
```
Time: 34560
Binary: 1000011100000000
Hour: 0x10 = 16 (4:00 PM)
Minute: 0x38 = 56
Second: 0x00 * 2 = 0

Result: 16:56:00
```

**Granularity Limitation:**
FAT time only stores **even seconds** (0, 2, 4, ..., 58). Odd seconds are rounded down.

**Edge Cases:**
- `0`: Midnight (`00:00:00`) or unknown
- Invalid values (e.g., hour > 23): Treat as `00:00:00`

## Complete Example

### Request
```
GET /command.cgi?op=100&DIR=/DCIM HTTP/1.1
```

### Response (6-field format)
```
WLANSD_FILELIST
/DCIM,100CANON,0,16,19588,0
/DCIM,101NIKON,0,16,19620,0
```

### Response (5-field format, legacy)
```
100CANON,0,16,19588,0
101NIKON,0,16,19620,0
```

### Parsed Result

| Directory | Name | Size | Attr | Date | Time | Decoded DateTime | Is Dir? |
|-----------|------|------|------|------|------|------------------|---------|
| /DCIM | 100CANON | 0 | 16 | 19588 | 0 | 2018-09-20 00:00:00 | Yes |
| /DCIM | 101NIKON | 0 | 16 | 19620 | 0 | 2018-10-20 00:00:00 | Yes |

## Parsing Implementation

### Robust CSV Parser (Pseudocode)

```python
def parse_csv_line(line: str, request_dir: str) -> DirectoryEntry:
    """
    Parse a single CSV line from FlashAir response.

    Args:
        line: Raw CSV line (may have \r\n)
        request_dir: Directory from original request (for 5-field format)

    Returns:
        DirectoryEntry or None if invalid
    """
    # Strip whitespace and line endings
    line = line.strip()

    # Skip empty lines
    if not line:
        return None

    # Skip header line
    if line.startswith("WLANSD_FILELIST"):
        return None

    # Split on comma
    fields = line.split(',')

    # Determine format
    if len(fields) == 6:
        # 6-field format: dir,name,size,attr,date,time
        directory = fields[0]
        name = fields[1]
        size = int(fields[2])
        attribute = int(fields[3])
        date = int(fields[4])
        time = int(fields[5])
    elif len(fields) == 5:
        # 5-field format: name,size,attr,date,time (infer directory)
        directory = request_dir
        name = fields[0]
        size = int(fields[1])
        attribute = int(fields[2])
        date = int(fields[3])
        time = int(fields[4])
    else:
        # Invalid format
        return None

    # Build absolute path
    if directory.endswith('/'):
        absolute_path = directory + name
    else:
        absolute_path = directory + '/' + name

    # Detect directory
    is_directory = (attribute & 0x10) != 0

    # Decode timestamp (optional)
    modified_at = decode_fat_datetime(date, time)

    return DirectoryEntry(
        directory=directory,
        name=name,
        absolute_path=absolute_path,
        size=size,
        attribute=attribute,
        is_directory=is_directory,
        modified_at=modified_at
    )

def decode_fat_datetime(date: int, time: int) -> datetime:
    """Convert FAT date/time integers to datetime."""
    if date == 0:
        return None  # Unknown date

    year = ((date >> 9) & 0x7F) + 1980
    month = (date >> 5) & 0x0F
    day = date & 0x1F

    hour = (time >> 11) & 0x1F
    minute = (time >> 5) & 0x3F
    second = (time & 0x1F) * 2

    # Validate ranges
    if not (1 <= month <= 12 and 1 <= day <= 31 and hour <= 23 and minute <= 59):
        return None

    try:
        return datetime(year, month, day, hour, minute, second)
    except ValueError:
        return None  # Invalid date (e.g., Feb 30)
```

## Edge Cases & Quirks

### 1. Header Line Handling

**Possible Responses:**
```
WLANSD_FILELIST
/DCIM,100CANON,0,16,19588,0
```

or

```
/DCIM,100CANON,0,16,19588,0
```

**Solution:** Skip lines starting with `WLANSD_FILELIST` or non-numeric third field.

### 2. Empty Directories

**Response:** Empty body (0 bytes) or just the header:
```
WLANSD_FILELIST
```

**Solution:** Treat as 0 entries, not an error.

### 3. Special Characters in Filenames

Some cameras create filenames with spaces or Unicode:
```
/DCIM,My Photo.JPG,2048000,32,19588,0
```

**Caution:** Commas in filenames will break naive CSV parsing.

**Solution:** FlashAir escapes commas in filenames as `%2C` (URL encoding). Always URL-decode names.

### 4. Inconsistent Line Endings

**Possible:** `\r\n` (Windows) or `\n` (Unix)

**Solution:** Use `line.strip()` to remove both.

### 5. Case Sensitivity

FAT filesystem is case-insensitive but case-preserving:
- `IMG_0001.jpg` and `IMG_0001.JPG` are the same file
- Request `/DCIM/100canon` works even if listed as `100CANON`

**Solution:** Normalize paths to lowercase for deduplication.

### 6. Root Directory Listing

Requesting `DIR=/` may return:
```
/,DCIM,0,16,19588,0
/,MP_ROOT,0,16,19588,0
```

Typical structure:
- `/DCIM/` - Photos/videos (standard)
- `/MP_ROOT/` - MP4 videos (some cameras)
- `/PRIVATE/` - Proprietary data

**Recommendation:** Start with `/DCIM` for photos.

## Validation Checklist

When implementing a CSV parser, verify:

- [ ] Handles both 5-field and 6-field formats
- [ ] Skips `WLANSD_FILELIST` header
- [ ] Tolerates `\r\n` and `\n` line endings
- [ ] Detects directories via `attribute & 0x10`
- [ ] Parses size as integer (handles 0 for directories)
- [ ] Decodes FAT date/time correctly
- [ ] Handles empty responses (0 entries)
- [ ] URL-decodes filenames (for special characters)
- [ ] Constructs correct absolute paths

## Test Cases

### Input: Standard Response
```
WLANSD_FILELIST
/DCIM/100CANON,IMG_0001.JPG,3145728,32,19588,34560
/DCIM/100CANON,IMG_0002.JPG,2891776,32,19588,34592
/DCIM/100CANON,VIDEO001.MP4,52428800,32,19588,35120
```

**Expected Output:**
```json
[
  {
    "name": "IMG_0001.JPG",
    "path": "/DCIM/100CANON/IMG_0001.JPG",
    "size": 3145728,
    "isDirectory": false,
    "modifiedAt": "2018-09-20T16:56:00"
  },
  {
    "name": "IMG_0002.JPG",
    "path": "/DCIM/100CANON/IMG_0002.JPG",
    "size": 2891776,
    "isDirectory": false,
    "modifiedAt": "2018-09-20T16:57:04"
  },
  {
    "name": "VIDEO001.MP4",
    "path": "/DCIM/100CANON/VIDEO001.MP4",
    "size": 52428800,
    "isDirectory": false,
    "modifiedAt": "2018-09-20T17:13:36"
  }
]
```

### Input: Directory Listing
```
WLANSD_FILELIST
/DCIM,100CANON,0,16,19588,0
/DCIM,101NIKON,0,16,19620,0
```

**Expected Output:**
```json
[
  {
    "name": "100CANON",
    "path": "/DCIM/100CANON",
    "size": 0,
    "isDirectory": true,
    "modifiedAt": "2018-09-20T00:00:00"
  },
  {
    "name": "101NIKON",
    "path": "/DCIM/101NIKON",
    "size": 0,
    "isDirectory": true,
    "modifiedAt": "2018-10-20T00:00:00"
  }
]
```

### Input: Empty Directory
```
WLANSD_FILELIST
```

**Expected Output:**
```json
[]
```

### Input: Malformed Line
```
WLANSD_FILELIST
/DCIM,100CANON,0,16,19588,0
/DCIM,IMG_0001.JPG,not-a-number,32,19588,34560
/DCIM,IMG_0002.JPG,2891776,32,19588,34592
```

**Expected Behavior:**
- Parse first line successfully
- Skip second line (invalid size)
- Parse third line successfully
- Log warning about malformed line

## References

- [FAT Filesystem Specification](https://en.wikipedia.org/wiki/Design_of_the_FAT_file_system#Directory_entry)
- [DOS File Attributes](https://en.wikipedia.org/wiki/File_attribute#DOS_and_Windows)
- [FlashAir API Documentation](https://flashair-developers.com/en/documents/api/commandcgi/)

---

**Version:** 1.0
**Last Updated:** 2025-01-15
