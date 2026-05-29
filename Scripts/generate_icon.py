#!/usr/bin/env python3
import math
import os
import struct
import sys
import zlib


def blend(dst, src):
    sr, sg, sb, sa = src
    if sa <= 0:
        return dst
    dr, dg, db, da = dst
    a = sa / 255.0
    ia = 1.0 - a
    return (
        int(sr * a + dr * ia),
        int(sg * a + dg * ia),
        int(sb * a + db * ia),
        int(255 * (a + da / 255.0 * ia)),
    )


def ellipse(canvas, bounds, color):
    width = len(canvas[0])
    height = len(canvas)
    x0, y0, x1, y1 = bounds
    cx = (x0 + x1) / 2.0
    cy = (y0 + y1) / 2.0
    rx = max(1.0, (x1 - x0) / 2.0)
    ry = max(1.0, (y1 - y0) / 2.0)
    for y in range(max(0, int(y0)), min(height, int(y1) + 1)):
        for x in range(max(0, int(x0)), min(width, int(x1) + 1)):
            dx = (x + 0.5 - cx) / rx
            dy = (y + 0.5 - cy) / ry
            v = dx * dx + dy * dy
            if v <= 1.0:
                alpha = color[3]
                if v > 0.88:
                    alpha = int(alpha * max(0, (1.0 - v) / 0.12))
                canvas[y][x] = blend(canvas[y][x], (color[0], color[1], color[2], alpha))


def stroke_ellipse(canvas, bounds, color, thickness):
    width = len(canvas[0])
    height = len(canvas)
    x0, y0, x1, y1 = bounds
    cx = (x0 + x1) / 2.0
    cy = (y0 + y1) / 2.0
    rx = max(1.0, (x1 - x0) / 2.0)
    ry = max(1.0, (y1 - y0) / 2.0)
    edge = thickness / max(rx, ry)
    for y in range(max(0, int(y0 - thickness)), min(height, int(y1 + thickness) + 1)):
        for x in range(max(0, int(x0 - thickness)), min(width, int(x1 + thickness) + 1)):
            dx = (x + 0.5 - cx) / rx
            dy = (y + 0.5 - cy) / ry
            v = math.sqrt(dx * dx + dy * dy)
            if 1.0 - edge <= v <= 1.0 + edge:
                fade = 1.0 - min(1.0, abs(v - 1.0) / edge)
                canvas[y][x] = blend(canvas[y][x], (color[0], color[1], color[2], int(color[3] * fade)))


def line(canvas, p0, p1, color, thickness):
    x0, y0 = p0
    x1, y1 = p1
    steps = int(max(abs(x1 - x0), abs(y1 - y0)) * 2) + 1
    radius = thickness / 2.0
    for i in range(steps + 1):
        t = i / steps
        x = x0 + (x1 - x0) * t
        y = y0 + (y1 - y0) * t
        ellipse(canvas, (x - radius, y - radius, x + radius, y + radius), color)


def save_png(path, canvas):
    height = len(canvas)
    width = len(canvas[0])
    raw = bytearray()
    for row in canvas:
        raw.append(0)
        for r, g, b, a in row:
            raw.extend([r, g, b, a])

    def chunk(kind, data):
        return (
            struct.pack(">I", len(data))
            + kind
            + data
            + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
        )

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


def render(size):
    canvas = [[(0, 0, 0, 0) for _ in range(size)] for _ in range(size)]
    s = size / 512.0

    ellipse(canvas, (92 * s, 362 * s, 420 * s, 442 * s), (0, 0, 0, 38))
    ellipse(canvas, (118 * s, 166 * s, 394 * s, 426 * s), (130, 223, 184, 255))
    stroke_ellipse(canvas, (118 * s, 166 * s, 394 * s, 426 * s), (67, 139, 109, 255), 12 * s)
    ellipse(canvas, (154 * s, 270 * s, 358 * s, 406 * s), (251, 226, 157, 255))
    ellipse(canvas, (102 * s, 304 * s, 172 * s, 378 * s), (247, 210, 111, 190))
    ellipse(canvas, (340 * s, 304 * s, 410 * s, 378 * s), (247, 210, 111, 190))

    ellipse(canvas, (128 * s, 94 * s, 234 * s, 202 * s), (143, 228, 192, 255))
    ellipse(canvas, (278 * s, 94 * s, 384 * s, 202 * s), (143, 228, 192, 255))
    stroke_ellipse(canvas, (128 * s, 94 * s, 234 * s, 202 * s), (67, 139, 109, 255), 12 * s)
    stroke_ellipse(canvas, (278 * s, 94 * s, 384 * s, 202 * s), (67, 139, 109, 255), 12 * s)
    line(canvas, (229 * s, 148 * s), (283 * s, 148 * s), (67, 139, 109, 255), 16 * s)

    ellipse(canvas, (158 * s, 124 * s, 214 * s, 180 * s), (239, 255, 238, 255))
    ellipse(canvas, (298 * s, 124 * s, 354 * s, 180 * s), (239, 255, 238, 255))
    ellipse(canvas, (174 * s, 138 * s, 202 * s, 166 * s), (21, 39, 47, 255))
    ellipse(canvas, (314 * s, 138 * s, 342 * s, 166 * s), (21, 39, 47, 255))
    ellipse(canvas, (171 * s, 134 * s, 184 * s, 147 * s), (255, 255, 255, 245))
    ellipse(canvas, (311 * s, 134 * s, 324 * s, 147 * s), (255, 255, 255, 245))

    line(canvas, (192 * s, 324 * s), (232 * s, 350 * s), (67, 139, 109, 255), 12 * s)
    line(canvas, (232 * s, 350 * s), (280 * s, 350 * s), (67, 139, 109, 255), 12 * s)
    line(canvas, (280 * s, 350 * s), (320 * s, 324 * s), (67, 139, 109, 255), 12 * s)
    return canvas


def main():
    if len(sys.argv) != 2:
        print("usage: generate_icon.py OUTPUT.icns", file=sys.stderr)
        sys.exit(2)
    output = os.path.abspath(sys.argv[1])
    build_dir = os.path.dirname(output)
    os.makedirs(build_dir, exist_ok=True)

    # Modern ICNS files can store PNG payloads. This avoids relying on iconutil
    # accepting hand-authored PNGs on every runner.
    chunks = []
    for size, code in [
        (16, b"icp4"),
        (32, b"icp5"),
        (64, b"icp6"),
        (128, b"ic07"),
        (256, b"ic08"),
        (512, b"ic09"),
        (1024, b"ic10"),
    ]:
        png_path = os.path.join(build_dir, f"AppIcon-{size}.png")
        save_png(png_path, render(size))
        with open(png_path, "rb") as f:
            payload = f.read()
        chunks.append(code + struct.pack(">I", len(payload) + 8) + payload)

    body = b"".join(chunks)
    with open(output, "wb") as f:
        f.write(b"icns" + struct.pack(">I", len(body) + 8) + body)


if __name__ == "__main__":
    main()
