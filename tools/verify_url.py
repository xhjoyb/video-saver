#!/usr/bin/env python3
"""验证抖音视频直链是否可用、是否无水印（下载前 256KB 检查容器头）。

用法:
    python3 tools/verify_url.py --url-file /tmp/dy_url.txt
"""

import argparse
import ssl
import sys
import urllib.error
import urllib.request

UA = (
    "Mozilla/5.0 (Linux; Android 14; PGT-AN20 Build/HONORPGT-AN20) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"
)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url-file", required=True)
    ap.add_argument("--bytes", type=int, default=262144)
    args = ap.parse_args()

    with open(args.url_file, "r", encoding="utf-8") as fh:
        url = fh.read().strip()
    if not url.startswith("http"):
        print("no url in file")
        return 2

    print("url len =", len(url))
    print("has watermark param =", "watermark" in url)
    print("host =", url.split("/")[2])

    ctx = ssl.create_default_context()
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": UA,
            "Range": f"bytes=0-{args.bytes - 1}",
            "Accept": "*/*",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=25, context=ctx) as resp:
            data = resp.read()
            print("status =", resp.status)
            print("content-type =", resp.headers.get("Content-Type"))
            print("content-range =", resp.headers.get("Content-Range"))
            print("content-length =", resp.headers.get("Content-Length"))
            print("read bytes =", len(data))
            head = data[:32]
            print("head hex =", head[:16].hex())
            # MP4 的 ftyp box 在偏移 4
            print("is mp4 (ftyp) =", b"ftyp" in data[:64])
            return 0
    except urllib.error.HTTPError as e:
        print("HTTP", e.code, e.read()[:200])
        return 1
    except Exception as e:
        print("ERR", type(e).__name__, e)
        return 1


if __name__ == "__main__":
    sys.exit(main())