# Mock FlashAir Server

A Python HTTP server that simulates the Toshiba FlashAir SD card API for testing without hardware.

## Features

- **Directory Listing**: Serves CSV responses for `command.cgi?op=100`
- **File Downloads**: Directly serves files from `test-data/` directory
- **Partial Downloads**: Supports HTTP Range requests (for resume testing)
- **Card Configuration**: Returns mock config via `command.cgi?op=104`
- **FAT Timestamps**: Encodes file mtimes in FAT date/time format

## Prerequisites

```bash
pip install flask
```

## Usage

### Start the Server

```bash
python server.py
```

Default: http://0.0.0.0:8080

### Custom Host/Port

```bash
python server.py --host 192.168.1.100 --port 9000
```

### Configure Your App

Point your iOS/Android app to the mock server:

- **Host**: `http://localhost:8080` (simulator/emulator)
- **Host**: `http://<your-local-ip>:8080` (physical device)
- **SSID**: Not needed (no actual Wi-Fi connection)
- **Passphrase**: Not needed

**Finding Your Local IP:**

```bash
# macOS/Linux
ifconfig | grep "inet " | grep -v 127.0.0.1

# Windows
ipconfig | findstr IPv4
```

## Test Data

### Default Structure

```
test-data/
└── DCIM/
    └── 100CANON/
        ├── IMG_0001.JPG
        └── IMG_0002.JPG
```

### Adding Test Files

1. **Create directories:**
   ```bash
   mkdir -p test-data/DCIM/100CANON
   mkdir -p test-data/DCIM/101NIKON
   ```

2. **Add sample photos:**
   ```bash
   cp ~/Pictures/sample1.jpg test-data/DCIM/100CANON/IMG_0001.JPG
   cp ~/Pictures/sample2.jpg test-data/DCIM/100CANON/IMG_0002.JPG
   ```

3. **Add sample videos:**
   ```bash
   cp ~/Movies/test.mp4 test-data/DCIM/100CANON/VIDEO001.MP4
   ```

### Generate Dummy Files

If you don't have real media files, create dummy files:

```bash
# 3 MB JPEG (random data)
dd if=/dev/urandom of=test-data/DCIM/100CANON/IMG_0001.JPG bs=1m count=3

# 50 MB video (random data)
dd if=/dev/urandom of=test-data/DCIM/100CANON/VIDEO001.MP4 bs=1m count=50
```

**Note:** These won't be valid images/videos, but work for testing file transfer logic.

## API Examples

### Directory Listing

**Request:**
```bash
curl "http://localhost:8080/command.cgi?op=100&DIR=/DCIM"
```

**Response:**
```
WLANSD_FILELIST
/DCIM,100CANON,0,16,19588,0
/DCIM,101NIKON,0,16,19620,0
```

### Subdirectory Listing

**Request:**
```bash
curl "http://localhost:8080/command.cgi?op=100&DIR=/DCIM/100CANON"
```

**Response:**
```
WLANSD_FILELIST
/DCIM/100CANON,IMG_0001.JPG,3145728,32,19588,34560
/DCIM/100CANON,IMG_0002.JPG,2891776,32,19588,34592
```

### File Download

**Request:**
```bash
curl "http://localhost:8080/DCIM/100CANON/IMG_0001.JPG" -o downloaded.jpg
```

### Partial Download (Range Request)

**Request:**
```bash
curl -H "Range: bytes=0-1048575" "http://localhost:8080/DCIM/100CANON/VIDEO001.MP4" -o chunk.mp4
```

**Response Headers:**
```
HTTP/1.1 206 Partial Content
Content-Range: bytes 0-1048575/52428800
Content-Length: 1048576
```

### Card Configuration

**Request:**
```bash
curl "http://localhost:8080/command.cgi?op=104"
```

**Response:**
```
VERSION=3.00.01
CID=02544d53413136472002cb3000000000
PRODUCT=FlashAir
VENDOR=TOSHIBA
APPMODE=5
APPNETWORKKEY=12345678
```

## Testing Scenarios

### Test 1: First Sync

1. Start server with 3 files in `test-data/DCIM/100CANON/`
2. Run app sync → should import 3 files
3. Verify app's sync index has 3 entries

### Test 2: Incremental Sync

1. Re-run sync (without adding files)
2. App should report "0 new files"
3. Verify no duplicate imports

### Test 3: Add New Files

1. Add new file to `test-data/DCIM/100CANON/IMG_0003.JPG`
2. Run sync → should import only the new file (1 file)
3. Verify total is now 4 files

### Test 4: Simulate Network Drop

1. Start sync
2. Stop server mid-download (Ctrl+C)
3. App should detect error and allow retry

### Test 5: Large File

1. Create 500 MB video:
   ```bash
   dd if=/dev/urandom of=test-data/DCIM/100CANON/LARGE.MP4 bs=1m count=500
   ```
2. Run sync → verify progress UI updates during download

### Test 6: Subdirectories

1. Create nested structure:
   ```bash
   mkdir -p test-data/DCIM/100CANON/SUBFOLDER
   cp sample.jpg test-data/DCIM/100CANON/SUBFOLDER/IMG_0001.JPG
   ```
2. Run sync → verify recursive directory walking works

## Troubleshooting

### "Address already in use"

Another process is using port 8080:

```bash
# Find the process
lsof -i :8080

# Kill it or use a different port
python server.py --port 9000
```

### "Connection refused" from Mobile Device

1. Ensure server is running
2. Verify firewall allows incoming connections on port 8080
3. Use local IP, not `localhost` (e.g., `http://192.168.1.100:8080`)
4. Ensure device and computer are on the same network

### CSV Response is Empty

Check that `test-data/DCIM/` directory exists:

```bash
ls -la test-data/DCIM/
```

If empty, add test files as described above.

## Advanced Usage

### Simulate Slow Network

Add delays to test timeout handling:

```python
# In server.py, add to download_file():
import time
time.sleep(2)  # 2-second delay per chunk
```

### Simulate Random Errors

Test retry logic:

```python
# In server.py, add to command_cgi():
import random
if random.random() < 0.3:  # 30% failure rate
    return Response("Card error", status=500)
```

### Enable Debug Mode

See Flask request logs:

```python
app.run(host=args.host, port=args.port, debug=True)
```

## Production Server Note

This mock server is **for testing only**. Do not use in production:

- No authentication
- No rate limiting
- Minimal error handling
- Debug mode enabled

For testing against a real FlashAir card, configure your app with:

- **Host**: `http://192.168.0.1`
- **SSID**: `flashair` (or your card's SSID)
- **Passphrase**: Your card's passphrase (default: `12345678`)

## License

MIT - See LICENSE file in repository root.
