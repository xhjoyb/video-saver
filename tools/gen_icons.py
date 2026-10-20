#!/usr/bin/env python3
"""生成青绿主题 launcher 图标 PNG（纯标准库，不依赖 Pillow）。

图标结构：深墨绿圆角矩形底 + 右上青绿光晕 + 青绿渐变圆 + 深墨绿播放三角。
Android 26+ 实际用 mipmap-anydpi-v26 的自适应图标（vector），
这里生成的 PNG 用于旧启动器兜底与圆角/方形显示。

用法：
    python3 tools/gen_icons.py            # 写入 mipmap-*dpi
    python3 tools/gen_icons.py --preview  # 额外打印字符画预览
"""

import argparse
import os
import struct
import zlib

# 与 res/values/colors.xml 保持一致
BG_START = (12, 43, 37)      # #0C2B25
BG_END = (3, 11, 9)          # #030B09
MINT_BRIGHT = (107, 255, 221)  # #6BFFDD
MINT = (25, 232, 190)        # #19E8BE
MINT_DEEP = (0, 169, 138)    # #00A98A
INK = (4, 18, 15)            # #04120F

SIZES = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}
SS = 4  # 超采样倍数，用于抗锯齿

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "android",
                    "app", "src", "main", "res")


def mix(c1, c2, t):
    t = 0.0 if t < 0 else (1.0 if t > 1 else t)
    return (c1[0] + (c2[0] - c1[0]) * t,
            c1[1] + (c2[1] - c1[1]) * t,
            c1[2] + (c2[2] - c1[2]) * t)


def inside_round_rect(x, y, w, h, r):
    if x < 0 or y < 0 or x >= w or y >= h:
        return False
    cx = min(max(x, r), w - r)
    cy = min(max(y, r), h - r)
    dx, dy = x - cx, y - cy
    return dx * dx + dy * dy <= r * r


def in_triangle(x, y, tri):
    (x1, y1), (x2, y2), (x3, y3) = tri
    d1 = (x - x2) * (y1 - y2) - (x1 - x2) * (y - y2)
    d2 = (x - x3) * (y2 - y3) - (x2 - x3) * (y - y3)
    d3 = (x - x1) * (y3 - y1) - (x3 - x1) * (y - y1)
    has_neg = d1 < 0 or d2 < 0 or d3 < 0
    has_pos = d1 > 0 or d2 > 0 or d3 > 0
    return not (has_neg and has_pos)


def render(size):
    n = size * SS
    radius = n * 0.22
    cx = cy = n / 2.0
    body_r = n * 0.30
    tri = ((0.415 * n, 0.365 * n), (0.705 * n, 0.5 * n), (0.415 * n, 0.635 * n))
    glow_c = (0.82 * n, 0.16 * n)
    glow_r = 0.62 * n

    buf = bytearray(n * n * 4)
    for y in range(n):
        row = y * n
        for x in range(n):
            ax, ay = x + 0.5, y + 0.5
            if not inside_round_rect(ax, ay, n, n, radius):
                continue

            t = (ax + ay) / (2.0 * n)
            col = mix(BG_START, BG_END, t)

            gd = ((ax - glow_c[0]) ** 2 + (ay - glow_c[1]) ** 2) ** 0.5
            glow = 1.0 - gd / glow_r if gd < glow_r else 0.0
            col = mix(col, MINT, glow * glow * 0.22)

            dc = ((ax - cx) ** 2 + (ay - cy) ** 2) ** 0.5
            if dc <= body_r:
                tt = ((ax - 0.30 * n) + (ay - 0.26 * n)) / (1.15 * n)
                if tt < 0.5:
                    col = mix(MINT_BRIGHT, MINT, tt / 0.5)
                else:
                    col = mix(MINT, MINT_DEEP, (tt - 0.5) / 0.5)
                if dc > body_r - 1.6 * SS:
                    col = mix(col, (255, 255, 255), 0.28)
            if in_triangle(ax, ay, tri):
                col = INK

            i = (row + x) * 4
            buf[i] = int(col[0] + 0.5)
            buf[i + 1] = int(col[1] + 0.5)
            buf[i + 2] = int(col[2] + 0.5)
            buf[i + 3] = 255

    # 超采样降采样（按 alpha 加权，边缘不会发黑）
    out = bytearray(size * size * 4)
    for y in range(size):
        for x in range(size):
            r = g = b = a = 0
            for sy in range(SS):
                base = ((y * SS + sy) * n + x * SS) * 4
                for sx in range(SS):
                    i = base + sx * 4
                    av = buf[i + 3]
                    r += buf[i] * av
                    g += buf[i + 1] * av
                    b += buf[i + 2] * av
                    a += av
            o = (y * size + x) * 4
            if a == 0:
                continue
            out[o] = r // a
            out[o + 1] = g // a
            out[o + 2] = b // a
            out[o + 3] = a // (SS * SS)
    return bytes(out)


def encode_png(size, rgba):
    stride = size * 4
    raw = bytearray()
    for y in range(size):
        raw.append(0)  # filter: none
        raw += rgba[y * stride:(y + 1) * stride]

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data +
                struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    ihdr = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) +
            chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b""))


def preview(size=48):
    rgba = render(size)
    chars = " .:-=+*#%@"
    for y in range(0, size, 2):
        line = []
        for x in range(size):
            i = (y * size + x) * 4
            a = rgba[i + 3]
            if a < 40:
                line.append(" ")
                continue
            lum = (0.3 * rgba[i] + 0.6 * rgba[i + 1] + 0.1 * rgba[i + 2]) / 255.0
            line.append(chars[min(len(chars) - 1, int(lum * len(chars)))])
        print("".join(line))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", action="store_true")
    args = ap.parse_args()

    if args.preview:
        print("--- preview (48px) ---")
        preview()

    for density, size in SIZES.items():
        data = encode_png(size, render(size))
        folder = os.path.join(ROOT, "mipmap-" + density)
        os.makedirs(folder, exist_ok=True)
        path = os.path.join(folder, "ic_launcher.png")
        with open(path, "wb") as fh:
            fh.write(data)
        print("wrote %-6s %3dpx %6d B  %s" % (density, size, len(data), path))


if __name__ == "__main__":
    main()