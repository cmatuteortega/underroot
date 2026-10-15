#!/usr/bin/env python3
"""Bakes the desktop icons out of assets/icon/.

The desktop half of android/icon.py, and built on it: the same two 40px layers
(the dusk behind, the Shelf Fungus on its grass block in front), the same
whole-number scales.

Three files are written into the given directory:

- icon.ico, for the Windows .exe (rcedit puts it in before game.love is fused
  on).
- icon.icns, the macOS app icon: the picture in a rounded square inside the
  transparent margin every Mac icon keeps, so it sits on the dock at the size
  of its neighbours.
- icon.png, 512px square, the Linux AppImage's icon.

PNG-in-ICO and PNG-in-ICNS are both standard, so this is standard library only.

    python3 desktop/icon.py <out-dir>
"""

import io
import os
import struct
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "android"))
from icon import bbox, icon, layers, png  # noqa: E402


def mac(side, bg, fg, box, size):
    """Apple's grid: an 824/1024 rounded square, radius 185/1024, centred."""
    body = size * 824 // 1024
    radius = size * 185 // 1024
    lo = (size - body) // 2
    hi = lo + body
    inner = icon(body, side, bg, fg, 0.9, box)

    def inside(x, y):
        if not (lo <= x < hi and lo <= y < hi):
            return False
        cx = min(max(x, lo + radius), hi - 1 - radius)
        cy = min(max(y, lo + radius), hi - 1 - radius)
        return (x - cx) ** 2 + (y - cy) ** 2 <= radius ** 2

    def pixel(x, y):
        return inner(x - lo, y - lo) if inside(x, y) else (0, 0, 0, 0)

    return pixel


def png_bytes(size, pixels):
    # android/icon.py's png() writes to a path; go through a scratch file
    # rather than fork it.
    path = os.path.join(OUT, ".scratch.png")
    png(path, size, pixels)
    with open(path, "rb") as f:
        data = f.read()
    os.remove(path)
    return data


def ico(path, images):
    """images: [(size, png bytes)]. Width/height 0 means 256."""
    head = struct.pack("<HHH", 0, 1, len(images))
    offset = len(head) + 16 * len(images)
    entries, blobs = b"", b""
    for size, data in images:
        side = 0 if size >= 256 else size
        entries += struct.pack("<BBBBHHII", side, side, 0, 0, 1, 32, len(data), offset)
        blobs += data
        offset += len(data)
    with open(path, "wb") as f:
        f.write(head + entries + blobs)


def icns(path, images):
    """images: [(OSType, png bytes)]."""
    body = io.BytesIO()
    for kind, data in images:
        body.write(kind + struct.pack(">I", 8 + len(data)) + data)
    data = body.getvalue()
    with open(path, "wb") as f:
        f.write(b"icns" + struct.pack(">I", 8 + len(data)) + data)


def main():
    global OUT
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    OUT = sys.argv[1]
    os.makedirs(OUT, exist_ok=True)
    side, bg, fg = layers()
    box = bbox(side, fg)

    ico(os.path.join(OUT, "icon.ico"),
        [(s, png_bytes(s, icon(s, side, bg, fg, 0.95, box))) for s in (16, 32, 48, 64, 128, 256)])

    # ic07..ic10 are the 128..1024 PNG slots; ic12..ic14 the same at @2x of
    # 32..512, which is what Retina docks and Finder ask for.
    icns(os.path.join(OUT, "icon.icns"), [
        (b"ic07", png_bytes(128, mac(side, bg, fg, box, 128))),
        (b"ic08", png_bytes(256, mac(side, bg, fg, box, 256))),
        (b"ic09", png_bytes(512, mac(side, bg, fg, box, 512))),
        (b"ic10", png_bytes(1024, mac(side, bg, fg, box, 1024))),
        (b"ic12", png_bytes(64, mac(side, bg, fg, box, 64))),
        (b"ic13", png_bytes(256, mac(side, bg, fg, box, 256))),
        (b"ic14", png_bytes(512, mac(side, bg, fg, box, 512))),
    ])

    png(os.path.join(OUT, "icon.png"), 512, icon(512, side, bg, fg, 0.95, box))


if __name__ == "__main__":
    main()
