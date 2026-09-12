#!/usr/bin/env python3
"""Draw the app icon.

The icon is generated rather than drawn by hand so it can be reasoned about and changed: every
number here is a decision, and a decision in a file beats a decision inside a binary nobody can
edit. No image library is used — a PNG is a handful of filtered scanlines inside a zlib stream,
and the drawing is two rounded squares over a gradient.

Run it from the repository root:

    python3 Scripts/make-icon.py

iOS wants a single 1024pt icon with no alpha channel, which is what this writes.
"""
import math
import struct
import sys
import zlib
from pathlib import Path

SIZE = 1024
OUTPUT = Path("DupeSpace/Assets.xcassets/AppIcon.appiconset/icon-1024.png")

# The same two hues the live surfaces use for a running scan, so the icon and the Lock Screen
# are recognisably the same app.
TOP = (10, 132, 255)      # systemBlue
BOTTOM = (50, 215, 235)   # a touch past systemTeal, which keeps the gradient from going flat


def lerp(a, b, t):
    return a + (b - a) * t


def rounded_box_distance(x, y, half_width, half_height, radius):
    """Signed distance to a rounded rectangle centred on the origin. Negative means inside."""
    dx = abs(x) - (half_width - radius)
    dy = abs(y) - (half_height - radius)
    outside = math.hypot(max(dx, 0), max(dy, 0))
    inside = min(max(dx, dy), 0)
    return outside + inside - radius


def coverage(distance, softness=1.2):
    """Anti-aliasing: a pixel on the edge is partly covered, not on or off."""
    if distance <= -softness:
        return 1.0
    if distance >= softness:
        return 0.0
    return (softness - distance) / (2 * softness)


def over(base, colour, alpha):
    return tuple(int(round(lerp(base[i], colour[i], alpha))) for i in range(3))


def render():
    centre = SIZE / 2
    # Two copies of the same thing, offset — which is what this app is about.
    square_half = 215.0
    radius = 62.0
    offset = 78.0

    rows = []
    for py in range(SIZE):
        row = bytearray()
        y = py + 0.5
        for px in range(SIZE):
            x = px + 0.5

            # Background: a diagonal gradient, so the icon has a light source.
            t = (x / SIZE) * 0.35 + (y / SIZE) * 0.65
            background = (
                int(round(lerp(TOP[0], BOTTOM[0], t))),
                int(round(lerp(TOP[1], BOTTOM[1], t))),
                int(round(lerp(TOP[2], BOTTOM[2], t))),
            )
            pixel = background

            # The copy behind: present, but plainly the one you would let go of.
            back = rounded_box_distance(
                x - (centre - offset), y - (centre - offset), square_half, square_half, radius
            )
            pixel = over(pixel, (255, 255, 255), coverage(back) * 0.38)

            # The one you keep, solid and in front.
            front = rounded_box_distance(
                x - (centre + offset), y - (centre + offset), square_half, square_half, radius
            )
            # A band of gradient around the front square, so the two stay two shapes instead
            # of merging into one blob at 60 points.
            gap = rounded_box_distance(
                x - (centre + offset), y - (centre + offset),
                square_half + 22, square_half + 22, radius + 22
            )
            pixel = over(pixel, background, coverage(gap))

            pixel = over(pixel, (255, 255, 255), coverage(front))

            row += bytes(pixel)
        rows.append(row)
    return rows


def write_png(rows, path):
    raw = bytearray()
    for row in rows:
        raw.append(0)  # filter type 0: none. The gradient compresses well enough without one.
        raw += row

    def chunk(tag, payload):
        data = tag + payload
        return struct.pack(">I", len(payload)) + data + struct.pack(">I", zlib.crc32(data))

    header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)  # 8-bit, truecolour, no alpha
    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png)
    return len(png)


def main():
    written = write_png(render(), OUTPUT)
    print(f"wrote {OUTPUT} ({written / 1024:.0f} KB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
