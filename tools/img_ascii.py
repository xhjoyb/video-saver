#!/usr/bin/env python3
"""把 PNG 截图压成字符画，用于在没有图形界面的环境里判断布局。

用法:
    python3 tools/img_ascii.py --file release/vs_home.png --cols 64
"""

import argparse
import struct
import sys
import zlib


def read_png(path):
    with open(path, "rb") as fh:
        data = fh.read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "not a png"
    pos = 8
    width = height = bit_depth = color_type = None
    idat = bytearray()
    plte = None
    while pos < len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        ctype = data[pos + 4:pos + 8]
        chunk = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if ctype == b"IHDR":
            width, height, bit_depth, color_type = struct.unpack(">IIBB", chunk[:10])
        elif ctype == b"PLTE":
            plte = chunk
        elif ctype == b"IDAT":
            idat.extend(chunk)
        elif ctype == b"IEND":
            break
    if bit_depth != 8:
        raise SystemExit(f"unsupported bit depth {bit_depth}")
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[color_type]
    raw = zlib.decompress(bytes(idat))
    stride = width * channels
    out = bytearray(width * height * channels)
    prev = bytearray(stride)
    p = 0
    for y in range(height):
        f = raw[p]
        p += 1
        line = bytearray(raw[p:p + stride])
        p += stride
        if f == 1:  # Sub
            for i in range(channels, stride):
                line[i] = (line[i] + line[i - channels]) & 0xFF
        elif f == 2:  # Up
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif f == 3:  # Average
            for i in range(stride):
                a = line[i - channels] if i >= channels else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 0xFF
        elif f == 4:  # Paeth
            for i in range(stride):
                a = line[i - channels] if i >= channels else 0
                b = prev[i]
                c = prev[i - channels] if i >= channels else 0
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 0xFF
        out[y * stride:(y + 1) * stride] = line
        prev = line
    return width, height, channels, bytes(out), color_type, plte


def luminance_grid(path, cols):
    width, height, channels, buf, color_type, plte = read_png(path)
    rows = max(1, int(cols * (height / width) * 0.5))
    bw = max(1, width // cols)
    bh = max(1, height // rows)
    grid = []
    for ry in range(rows):
        line = []
        for rx in range(cols):
            total = 0
            count = 0
            y0 = ry * bh
            y1 = min(height, y0 + bh)
            x0 = rx * bw
            x1 = min(width, x0 + bw)
            step_y = max(1, (y1 - y0) // 4)
            step_x = max(1, (x1 - x0) // 4)
            for y in range(y0, y1, step_y):
                base = y * width * channels
                for x in range(x0, x1, step_x):
                    off = base + x * channels
                    if color_type == 3:
                        idx = buf[off]
                        r, g, b = plte[idx * 3], plte[idx * 3 + 1], plte[idx * 3 + 2]
                    elif channels >= 3:
                        r, g, b = buf[off], buf[off + 1], buf[off + 2]
                    else:
                        r = g = b = buf[off]
                    total += 0.2126 * r + 0.7152 * g + 0.0722 * b
                    count += 1
            line.append(total / max(1, count))
        grid.append(line)
    return grid


CHARS = " .:-=+*#%@"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--file", required=True)
    ap.add_argument("--cols", type=int, default=64)
    args = ap.parse_args()

    grid = luminance_grid(args.file, args.cols)
    for row in grid:
        print("".join(CHARS[min(len(CHARS) - 1, int(v / 255 * (len(CHARS) - 1) + 0.5))] for v in row))
    return 0


if __name__ == "__main__":
    sys.exit(main())