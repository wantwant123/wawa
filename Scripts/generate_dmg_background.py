#!/usr/bin/env python3
import math
import os
import struct
import sys
import zlib


WIDTH = 760
HEIGHT = 420


def blend(dst, src):
    sr, sg, sb, sa = src
    dr, dg, db = dst
    alpha = sa / 255.0
    inverse = 1.0 - alpha
    return (
        int(sr * alpha + dr * inverse),
        int(sg * alpha + dg * inverse),
        int(sb * alpha + db * inverse),
    )


def rect(canvas, x0, y0, x1, y1, color):
    for y in range(max(0, int(y0)), min(HEIGHT, int(y1))):
        for x in range(max(0, int(x0)), min(WIDTH, int(x1))):
            canvas[y][x] = blend(canvas[y][x], color)


def ellipse(canvas, x0, y0, x1, y1, color):
    cx = (x0 + x1) / 2.0
    cy = (y0 + y1) / 2.0
    rx = max(1.0, (x1 - x0) / 2.0)
    ry = max(1.0, (y1 - y0) / 2.0)
    for y in range(max(0, int(y0)), min(HEIGHT, int(y1) + 1)):
        for x in range(max(0, int(x0)), min(WIDTH, int(x1) + 1)):
            dx = (x + 0.5 - cx) / rx
            dy = (y + 0.5 - cy) / ry
            if dx * dx + dy * dy <= 1.0:
                canvas[y][x] = blend(canvas[y][x], color)


def line(canvas, x0, y0, x1, y1, color, thickness):
    steps = int(max(abs(x1 - x0), abs(y1 - y0)) * 2) + 1
    radius = thickness / 2.0
    for index in range(steps + 1):
        t = index / steps
        x = x0 + (x1 - x0) * t
        y = y0 + (y1 - y0) * t
        ellipse(canvas, x - radius, y - radius, x + radius, y + radius, color)


def arrow(canvas):
    line(canvas, 314, 204, 468, 204, (92, 154, 126, 150), 14)
    line(canvas, 468, 204, 436, 172, (92, 154, 126, 150), 14)
    line(canvas, 468, 204, 436, 236, (92, 154, 126, 150), 14)
    line(canvas, 314, 224, 468, 224, (255, 255, 255, 90), 3)


def frog_mark(canvas):
    ellipse(canvas, 124, 108, 240, 224, (126, 222, 181, 255))
    ellipse(canvas, 148, 176, 216, 224, (255, 225, 150, 255))
    ellipse(canvas, 120, 76, 172, 128, (148, 232, 195, 255))
    ellipse(canvas, 192, 76, 244, 128, (148, 232, 195, 255))
    ellipse(canvas, 137, 91, 158, 112, (240, 255, 240, 255))
    ellipse(canvas, 209, 91, 230, 112, (240, 255, 240, 255))
    ellipse(canvas, 144, 96, 156, 108, (25, 42, 48, 255))
    ellipse(canvas, 216, 96, 228, 108, (25, 42, 48, 255))
    line(canvas, 162, 183, 181, 195, (69, 136, 108, 255), 5)
    line(canvas, 181, 195, 203, 195, (69, 136, 108, 255), 5)
    line(canvas, 203, 195, 222, 183, (69, 136, 108, 255), 5)


def save_png(path, canvas):
    raw = bytearray()
    for row in canvas:
        raw.append(0)
        for r, g, b in row:
            raw.extend([r, g, b])

    def chunk(kind, data):
        return (
            struct.pack(">I", len(data))
            + kind
            + data
            + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
        )

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", WIDTH, HEIGHT, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as file:
        file.write(png)


def main():
    if len(sys.argv) != 2:
        print("usage: generate_dmg_background.py OUTPUT.png", file=sys.stderr)
        sys.exit(2)

    output = os.path.abspath(sys.argv[1])
    os.makedirs(os.path.dirname(output), exist_ok=True)

    canvas = []
    for y in range(HEIGHT):
        row = []
        for x in range(WIDTH):
            glow = math.sin((x / WIDTH) * math.pi) * 8
            row.append((240 + int(glow), 250, 246))
        canvas.append(row)

    ellipse(canvas, 70, 40, 310, 280, (204, 246, 226, 135))
    ellipse(canvas, 460, 82, 706, 324, (222, 246, 234, 135))
    rect(canvas, 36, 332, 724, 334, (92, 154, 126, 42))
    arrow(canvas)
    frog_mark(canvas)
    save_png(output, canvas)


if __name__ == "__main__":
    main()
