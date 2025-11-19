#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.8"
# dependencies = [
#     "flask>=3.0.0",
#     "pillow>=10.0.0",
# ]
# ///
"""
Mock FlashAir HTTP Server

Simulates Toshiba FlashAir SD card HTTP API for testing without hardware.

Serves:
- command.cgi?op=100 (directory listing in CSV format)
- Direct file downloads from test-data/ directory
- command.cgi?op=104 (card configuration)
- Dynamically generates test images with filename rendered as text
- Simulates "taking photos" by adding new images on each sync

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
from PIL import Image, ImageDraw, ImageFont
import io

app = Flask(__name__)

# Base directory for test files
TEST_DATA_DIR = Path(__file__).parent / "test-data"

# State tracking for simulating "taking photos"
SYNC_COUNT = 0
BASE_IMAGE_COUNT = 3  # Start with 3 images


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


def generate_test_image(filename: str, width: int = 800, height: int = 600) -> bytes:
    """
    Generate a test image with the filename rendered as text.

    Args:
        filename: The filename to render in the image
        width: Image width in pixels
        height: Image height in pixels

    Returns:
        JPEG image data as bytes
    """
    # Create a new image with a gradient background
    image = Image.new('RGB', (width, height), color=(240, 240, 240))
    draw = ImageDraw.Draw(image)

    # Draw gradient background
    for y in range(height):
        color_value = int(200 + (y / height) * 55)
        draw.rectangle([(0, y), (width, y+1)], fill=(color_value, color_value, 255))

    # Try to load a font, fall back to default if not available
    try:
        font_large = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 60)
        font_small = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 30)
    except:
        font_large = ImageFont.load_default()
        font_small = ImageFont.load_default()

    # Draw filename in center
    text = filename
    bbox = draw.textbbox((0, 0), text, font=font_large)
    text_width = bbox[2] - bbox[0]
    text_height = bbox[3] - bbox[1]
    x = (width - text_width) // 2
    y = (height - text_height) // 2

    # Draw shadow
    draw.text((x+2, y+2), text, font=font_large, fill=(0, 0, 0, 128))
    # Draw main text
    draw.text((x, y), text, font=font_large, fill=(50, 50, 50))

    # Draw "Mock FlashAir Test Image" at bottom
    footer_text = "Mock FlashAir Test Image"
    bbox = draw.textbbox((0, 0), footer_text, font=font_small)
    footer_width = bbox[2] - bbox[0]
    draw.text(((width - footer_width) // 2, height - 60), footer_text,
              font=font_small, fill=(100, 100, 100))

    # Save to bytes
    buffer = io.BytesIO()
    image.save(buffer, format='JPEG', quality=85)
    buffer.seek(0)
    return buffer.getvalue()


def get_directory_csv(dir_path: str) -> str:
    """
    Generate CSV directory listing for the given path.

    Dynamically generates file listings based on current image count.

    Args:
        dir_path: Directory path (e.g., "/DCIM" or "/DCIM/100CANON")

    Returns:
        CSV string in FlashAir format
    """
    global SYNC_COUNT, BASE_IMAGE_COUNT

    # Normalize path
    dir_path = dir_path.rstrip('/')
    if not dir_path:
        dir_path = '/'

    # Build CSV response
    lines = ["WLANSD_FILELIST"]

    # Handle /DCIM directory
    if dir_path == '/DCIM':
        # Return the 100CANON subdirectory
        now = datetime.now()
        fat_date = fat_encode_date(now)
        fat_time = fat_encode_time(now)
        csv_line = f"{dir_path},100CANON,0,16,{fat_date},{fat_time}"
        lines.append(csv_line)

    # Handle /DCIM/100CANON directory - dynamically generate files
    elif dir_path == '/DCIM/100CANON':
        # Calculate current number of images (increases with each sync)
        current_image_count = BASE_IMAGE_COUNT + (SYNC_COUNT * 2)  # Add 2 images per sync

        now = datetime.now()
        fat_date = fat_encode_date(now)
        fat_time = fat_encode_time(now)

        # Generate file entries
        for i in range(1, current_image_count + 1):
            filename = f"IMG_{i:04d}.JPG"
            # Approximate JPEG size (will be generated dynamically)
            size = 25000 + (i * 100)  # Vary size slightly
            attribute = 32  # Archive file
            csv_line = f"{dir_path},{filename},{size},{attribute},{fat_date},{fat_time}"
            lines.append(csv_line)

    # For other paths, fall back to filesystem
    else:
        fs_path = TEST_DATA_DIR / dir_path.lstrip('/')
        if not fs_path.exists() or not fs_path.is_dir():
            return ""  # Empty response for non-existent directories

        for item in sorted(fs_path.iterdir()):
            name = item.name
            is_dir = item.is_dir()
            stat = item.stat()
            size = 0 if is_dir else stat.st_size
            attribute = 16 if is_dir else 32
            mtime = datetime.fromtimestamp(stat.st_mtime)
            fat_date = fat_encode_date(mtime)
            fat_time = fat_encode_time(mtime)
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
    Serve files - either dynamically generated test images or from filesystem.

    Supports partial downloads via Range header.
    """
    global SYNC_COUNT

    # Check if this is a dynamically generated test image
    if file_path.startswith('DCIM/100CANON/IMG_') and file_path.endswith('.JPG'):
        filename = file_path.split('/')[-1]

        # Increment sync count after first file download (simulates "taking photos")
        # This happens once per sync session
        if filename == "IMG_0001.JPG":
            SYNC_COUNT += 1
            print(f"[Mock Server] Sync #{SYNC_COUNT} detected - will add 2 new photos for next sync")

        # Generate the image dynamically
        image_data = generate_test_image(filename)

        # Return the generated image
        return Response(image_data, mimetype='image/jpeg')

    # Fall back to filesystem for other files
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

Dynamic Features:
  • Starts with {BASE_IMAGE_COUNT} test images
  • Each sync adds 2 new images (simulates "taking photos")
  • Images are generated on-the-fly with filename rendered as text
  • Test incremental sync by running multiple syncs!

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
