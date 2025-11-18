#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.8"
# dependencies = [
#     "flask>=3.0.0",
# ]
# ///
"""
Mock FlashAir HTTP Server

Simulates Toshiba FlashAir SD card HTTP API for testing without hardware.

Serves:
- command.cgi?op=100 (directory listing in CSV format)
- Direct file downloads from test-data/ directory
- command.cgi?op=104 (card configuration)

Usage:
    uv run server.py [--port 8080] [--host 0.0.0.0]
    # or
    python server.py [--port 8080] [--host 0.0.0.0]
"""

import os
import argparse
import time
from pathlib import Path
from datetime import datetime
from flask import Flask, request, send_file, Response

app = Flask(__name__)

# Base directory for test files
TEST_DATA_DIR = Path(__file__).parent / "test-data"


def fat_encode_date(dt: datetime) -> int:
    """
    Encode datetime as FAT date (16-bit integer).

    Bits 15-9: Year since 1980
    Bits 8-5: Month (1-12)
    Bits 4-0: Day (1-31)
    """
    year = (dt.year - 1980) & 0x7F
    month = dt.month & 0x0F
    day = dt.day & 0x1F
    return (year << 9) | (month << 5) | day


def fat_encode_time(dt: datetime) -> int:
    """
    Encode datetime as FAT time (16-bit integer).

    Bits 15-11: Hour (0-23)
    Bits 10-5: Minute (0-59)
    Bits 4-0: Second / 2 (0-29)
    """
    hour = dt.hour & 0x1F
    minute = dt.minute & 0x3F
    second = (dt.second // 2) & 0x1F
    return (hour << 11) | (minute << 5) | second


def get_directory_csv(dir_path: str) -> str:
    """
    Generate CSV directory listing for the given path.

    Args:
        dir_path: Directory path (e.g., "/DCIM" or "/DCIM/100CANON")

    Returns:
        CSV string in FlashAir format
    """
    # Normalize path
    dir_path = dir_path.rstrip('/')
    if not dir_path:
        dir_path = '/'

    # Map to filesystem path
    if dir_path == '/':
        fs_path = TEST_DATA_DIR
    else:
        fs_path = TEST_DATA_DIR / dir_path.lstrip('/')

    if not fs_path.exists() or not fs_path.is_dir():
        return ""  # Empty response for non-existent directories

    # Build CSV response
    lines = ["WLANSD_FILELIST"]

    for item in sorted(fs_path.iterdir()):
        name = item.name
        is_dir = item.is_dir()

        # Get file stats
        stat = item.stat()
        size = 0 if is_dir else stat.st_size
        attribute = 16 if is_dir else 32  # 0x10 = directory, 0x20 = archive

        # Get modification time
        mtime = datetime.fromtimestamp(stat.st_mtime)
        fat_date = fat_encode_date(mtime)
        fat_time = fat_encode_time(mtime)

        # Build CSV line: directory,name,size,attribute,date,time
        csv_line = f"{dir_path},{name},{size},{attribute},{fat_date},{fat_time}"
        lines.append(csv_line)

    return "\r\n".join(lines) + "\r\n"


@app.route('/command.cgi')
def command_cgi():
    """Handle FlashAir command.cgi requests."""
    op = request.args.get('op')

    if op == '100':
        # Directory listing
        dir_path = request.args.get('DIR', '/DCIM')
        csv_data = get_directory_csv(dir_path)
        return Response(csv_data, mimetype='text/plain')

    elif op == '104':
        # Card configuration
        config = """VERSION=3.00.01
CID=02544d53413136472002cb3000000000
PRODUCT=FlashAir
VENDOR=TOSHIBA
APPMODE=5
APPNETWORKKEY=12345678
"""
        return Response(config, mimetype='text/plain')

    else:
        return Response("Unknown operation", status=400)


@app.route('/<path:file_path>')
def download_file(file_path):
    """
    Serve files directly from test-data directory.

    Supports partial downloads via Range header.
    """
    # Map to filesystem path
    fs_path = TEST_DATA_DIR / file_path.lstrip('/')

    if not fs_path.exists() or fs_path.is_dir():
        return Response("File not found", status=404)

    # Handle Range requests (for partial downloads)
    range_header = request.headers.get('Range')
    if range_header:
        # Parse Range: bytes=start-end
        try:
            byte_range = range_header.replace('bytes=', '')
            start, end = byte_range.split('-')
            start = int(start) if start else 0
            file_size = fs_path.stat().st_size
            end = int(end) if end else file_size - 1

            # Read partial content
            with open(fs_path, 'rb') as f:
                f.seek(start)
                data = f.read(end - start + 1)

            # Return 206 Partial Content
            response = Response(data, status=206)
            response.headers['Content-Range'] = f'bytes {start}-{end}/{file_size}'
            response.headers['Content-Length'] = str(len(data))
            return response
        except Exception as e:
            return Response(f"Invalid range: {e}", status=416)

    # Full file download
    return send_file(fs_path)


@app.route('/')
def index():
    """Simple status page."""
    return """
    <html>
    <head><title>Mock FlashAir Server</title></head>
    <body>
        <h1>Mock FlashAir Server</h1>
        <p>Simulating Toshiba FlashAir SD card HTTP API</p>
        <h2>Available Endpoints:</h2>
        <ul>
            <li><a href="/command.cgi?op=100&DIR=/DCIM">/command.cgi?op=100&DIR=/DCIM</a> - List /DCIM directory</li>
            <li><a href="/command.cgi?op=100&DIR=/DCIM/100CANON">/command.cgi?op=100&DIR=/DCIM/100CANON</a> - List subdirectory</li>
            <li><a href="/command.cgi?op=104">/command.cgi?op=104</a> - Card configuration</li>
        </ul>
        <h2>File Structure:</h2>
        <pre>{}</pre>
    </body>
    </html>
    """.format(get_directory_tree())


def get_directory_tree():
    """Generate a simple directory tree for the status page."""
    tree_lines = []

    def walk_dir(path: Path, prefix=""):
        items = sorted(path.iterdir())
        for i, item in enumerate(items):
            is_last = i == len(items) - 1
            connector = "└── " if is_last else "├── "
            tree_lines.append(f"{prefix}{connector}{item.name}")
            if item.is_dir():
                extension = "    " if is_last else "│   "
                walk_dir(item, prefix + extension)

    tree_lines.append("test-data/")
    walk_dir(TEST_DATA_DIR, "")
    return "\n".join(tree_lines)


def main():
    parser = argparse.ArgumentParser(description='Mock FlashAir HTTP Server')
    parser.add_argument('--host', default='0.0.0.0', help='Host to bind to (default: 0.0.0.0)')
    parser.add_argument('--port', type=int, default=8080, help='Port to listen on (default: 8080)')
    args = parser.parse_args()

    print(f"""
╔═══════════════════════════════════════════════════════════════╗
║           Mock FlashAir Server                                ║
╚═══════════════════════════════════════════════════════════════╝

Starting server at http://{args.host}:{args.port}

Configure your app with:
  • Host: http://{args.host}:{args.port}
  • SSID: flashair (not needed for mock server)
  • Passphrase: 12345678 (not needed for mock server)

Available endpoints:
  • GET /command.cgi?op=100&DIR=/DCIM   (directory listing)
  • GET /command.cgi?op=104             (card config)
  • GET /DCIM/100CANON/IMG_0001.JPG     (file download)

Test data location: {TEST_DATA_DIR}

Press Ctrl+C to stop.
""")

    # Ensure test data directory exists
    TEST_DATA_DIR.mkdir(parents=True, exist_ok=True)
    (TEST_DATA_DIR / "DCIM").mkdir(exist_ok=True)

    # Run server
    app.run(host=args.host, port=args.port, debug=False)


if __name__ == '__main__':
    main()
