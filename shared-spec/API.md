# FlashAir HTTP API Specification

This document describes the Toshiba FlashAir SD card HTTP API used by FlashAir Sync.

## Overview

FlashAir SD cards run an embedded HTTP server accessible when connected to the card's Wi-Fi access point. The API provides directory listing, file downloads, and optional configuration capabilities.

## Connection Details

**Default Network:**
- SSID: `flashair` (or `flashair_XXXXXX` with card-specific suffix)
- Passphrase: `12345678` (configurable via SD card config files)
- IP Address: `192.168.0.1`
- Hostname: `flashair` (may work on some networks)

**No Internet:**
- FlashAir AP does not provide internet connectivity
- Mobile devices will show "No Internet Connection" warnings
- This is expected behavior

## Base URL

All API requests use the base URL:
```
http://192.168.0.1
```

## API Endpoints

### 1. Directory Listing

**Endpoint:** `/command.cgi?op=100&DIR=<path>`

**Method:** GET

**Parameters:**
- `op=100`: Command code for directory listing
- `DIR=<path>`: Directory path to list (URL-encoded)

**Example Request:**
```
GET /command.cgi?op=100&DIR=/DCIM HTTP/1.1
Host: 192.168.0.1
```

**Response Format:**
CSV (Comma-Separated Values) with 5 fields per line:

```
<directory>,<name>,<size>,<attribute>,<date>,<time>
```

**CSV Fields:**

1. **Directory** (string): Parent directory path (always `/DCIM` for root)
2. **Name** (string): File or subdirectory name
3. **Size** (integer): File size in bytes (0 for directories)
4. **Attribute** (integer): DOS file attributes (bitmask)
   - `0x10` (16): Directory
   - `0x20` (32): Archive
   - `0x01` (1): Read-only
   - Directories always have `attribute & 0x10 == 0x10`
5. **Date** (integer): FAT date (16-bit packed format)
   - Bits 15-9: Year (since 1980)
   - Bits 8-5: Month (1-12)
   - Bits 4-0: Day (1-31)
6. **Time** (integer): FAT time (16-bit packed format)
   - Bits 15-11: Hour (0-23)
   - Bits 10-5: Minute (0-59)
   - Bits 4-0: Second / 2 (0-29)

**Example Response:**
```
WLANSD_FILELIST
/DCIM,100CANON,0,16,19588,0
/DCIM/100CANON,IMG_0001.JPG,3145728,32,19588,34560
/DCIM/100CANON,IMG_0002.JPG,2891776,32,19588,34592
/DCIM/100CANON,VIDEO001.MP4,52428800,32,19588,35120
```

**Parsing Notes:**
- First line may be a header (`WLANSD_FILELIST`) or data row
- Some cards omit the header entirely
- Lines may end with `\r\n` (CRLF) or `\n` (LF)
- Entries with `attribute & 0x10` are directories
- Recursive listing requires separate requests for each subdirectory

**Error Responses:**
- Empty response: Directory doesn't exist or is empty
- HTTP 404: Invalid path
- HTTP 500: Card error or not ready

### 2. File Download

**Endpoint:** `/<absolute-path>`

**Method:** GET

**Parameters:** None (path is in URL)

**Example Request:**
```
GET /DCIM/100CANON/IMG_0001.JPG HTTP/1.1
Host: 192.168.0.1
Range: bytes=0-1048575
```

**Response:**
- HTTP 200: Full file content
- HTTP 206: Partial content (if Range header used)
- Content-Type: `image/jpeg`, `video/mp4`, etc. (or `application/octet-stream`)
- Content-Length: File size in bytes

**Partial Downloads:**
FlashAir supports HTTP Range requests for resuming interrupted downloads:
```
Range: bytes=<start>-<end>
```

**Example:**
```
GET /DCIM/100CANON/VIDEO001.MP4 HTTP/1.1
Range: bytes=0-1048575
```

Response headers:
```
HTTP/1.1 206 Partial Content
Content-Range: bytes 0-1048575/52428800
Content-Length: 1048576
```

**Error Responses:**
- HTTP 404: File not found
- HTTP 416: Invalid range
- HTTP 500: Card read error

### 3. Card Configuration (Read-Only)

**Endpoint:** `/command.cgi?op=104`

**Method:** GET

**Response Format:**
Plain text, one setting per line:
```
VERSION=<firmware-version>
CID=<card-id>
PRODUCT=<product-name>
VENDOR=<vendor-id>
```

**Example:**
```
VERSION=3.00.01
CID=02544d53413136472002cb3000000000
PRODUCT=FlashAir
VENDOR=TOSHIBA
```

**Use Case:**
- Identify card for per-card sync indexes
- Detect FlashAir model (W-02, W-03, W-04)

### 4. WebDAV (W-03/W-04 Only)

**Endpoint:** `/` (WebDAV PROPFIND)

**Method:** PROPFIND

**Support:** Only on W-03 (16GB/32GB) and W-04 (16GB/32GB/64GB) models

**Request:**
```xml
<?xml version="1.0" encoding="utf-8"?>
<propfind xmlns="DAV:">
  <prop>
    <getcontentlength/>
    <getlastmodified/>
    <resourcetype/>
  </prop>
</propfind>
```

**Response:** XML with directory/file properties

**Note:**
FlashAir Sync v1 uses CSV API for universal compatibility. WebDAV support is optional and may be added in future versions.

## Implementation Guidelines

### Directory Traversal

1. Start with `/DCIM` (or other root directory)
2. Request `command.cgi?op=100&DIR=/DCIM`
3. Parse CSV response
4. For each entry with `attribute & 0x10`:
   - Construct subdirectory path: `<parent>/<name>`
   - Recursively request listing for subdirectory
5. Build complete file list

**Example Traversal:**
```
GET /command.cgi?op=100&DIR=/DCIM
  → Found: 100CANON (directory)

GET /command.cgi?op=100&DIR=/DCIM/100CANON
  → Found: IMG_0001.JPG, IMG_0002.JPG, VIDEO001.MP4 (files)
```

### File Deduplication

Use `<absolute-path>#<size>` as the dedupe key:

**Example:**
```
/DCIM/100CANON/IMG_0001.JPG#3145728
/DCIM/100CANON/VIDEO001.MP4#52428800
```

**Rationale:**
- Path alone insufficient (camera may reuse filenames)
- Size + path catches 99% of duplicates
- FAT timestamps have 2-second granularity (unreliable for change detection)

### Download Strategy

1. **Chunked Download:** Read file in 1MB chunks to avoid memory pressure
2. **Atomic Write:** Download to temp file, rename on success
3. **Retry Logic:** 3 attempts with exponential backoff (1s, 2s, 4s)
4. **Cancellation:** Support mid-download cancellation, clean up partial files

**Pseudocode:**
```python
def download_file(path, size):
    temp_file = create_temp_file()
    for attempt in range(3):
        try:
            response = http_get(f"http://192.168.0.1{path}")
            with open(temp_file, 'wb') as f:
                for chunk in response.iter_content(chunk_size=1048576):
                    f.write(chunk)
                    check_cancellation()
            return move_to_final_location(temp_file)
        except NetworkError:
            if attempt < 2:
                sleep(2 ** attempt)
            else:
                raise
```

### Error Handling

| Error | Cause | Mitigation |
|-------|-------|------------|
| Empty CSV response | Directory empty or doesn't exist | Skip directory, continue |
| HTTP 404 | File deleted between list and download | Log warning, skip file |
| HTTP 500 | Card error or camera sleeping | Retry with backoff |
| Connection reset | Wi-Fi drop or card power-off | Detect, notify user, allow retry |
| Partial download | Network interrupted | Delete partial, retry from start |

### Network Binding (Android)

On Android, ensure traffic routes over the FlashAir network:

```kotlin
val networkRequest = NetworkRequest.Builder()
    .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
    .setNetworkSpecifier(WifiNetworkSpecifier.Builder()
        .setSsid("flashair")
        .setWpa2Passphrase("12345678")
        .build())
    .build()

connectivityManager.requestNetwork(networkRequest) { network ->
    connectivityManager.bindProcessToNetwork(network)
    // All HTTP requests now use FlashAir network
}
```

### Timeout Configuration

Recommended timeout values:

- **Connection timeout:** 10 seconds
- **Read timeout:** 30 seconds (for large files)
- **Directory listing timeout:** 5 seconds

**Rationale:**
- Card may be slow to respond when camera is busy writing
- Large videos (>500MB) need generous read timeout
- Directory listings should be fast; long timeout indicates card issue

## Security Considerations

### Authentication

FlashAir cards do not require HTTP authentication by default. WPA2 passphrase protects the Wi-Fi network.

**Optional:** Some cards support HTTP Basic Auth if configured in `config.cgi`.

### Data Privacy

- All traffic is local (no internet egress)
- SSID/passphrase should be stored securely (iOS Keychain, Android EncryptedSharedPreferences)
- Downloaded files inherit device security (encrypted storage on modern devices)

### Configuration Updates (Advanced)

FlashAir supports updating card configuration via `/config.cgi`:

**⚠️ WARNING:** Requires `MASTERCODE` (default: `00000000`). Changing config can brick the card if done incorrectly.

FlashAir Sync **does not** implement configuration updates in v1 for safety.

## Reference Links

- [Official FlashAir Developers Site](https://flashair-developers.com/en/)
- [FlashAir API Documentation](https://flashair-developers.com/en/documents/api/)
- [LUA Tutorial (advanced)](https://flashair-developers.com/en/documents/tutorial/)

## Changelog

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-01-15 | Initial specification for FlashAir Sync v1 |
