#!/usr/bin/env python3
"""探测抖音分享页的防护形态：是否返回 _ROUTER_DATA、是否需要 __ac_nonce 等。

用法:
    python3 tools/dy_probe.py --url https://www.iesdouyin.com/share/video/7xxxx
    python3 tools/dy_probe.py --url https://v.douyin.com/xxxxxx/ --follow
"""

import argparse
import gzip
import io
import ssl
import sys
import urllib.error
import urllib.request

MOBILE_UA = (
    "Mozilla/5.0 (Linux; Android 14; PGT-AN20 Build/HONORPGT-AN20) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"
)
PC_UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
)

MARKERS = [
    "_ROUTER_DATA",
    "RENDER_DATA",
    "__ac_nonce",
    "__ac_signature",
    "verify_center",
    "robot",
    "captcha",
    "slardar",
    "window._SSR_DATA",
]


def read_body(resp):
    raw = resp.read()
    enc = (resp.headers.get("Content-Encoding") or "").lower()
    if "gzip" in enc:
        raw = gzip.decompress(raw)
    elif "deflate" in enc:
        import zlib

        raw = zlib.decompress(raw)
    return raw.decode("utf-8", "replace")


def fetch(url, ua, cookies=None, timeout=20):
    ctx = ssl.create_default_context()
    headers = {
        "User-Agent": ua,
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language": "zh-CN,zh;q=0.9",
    }
    if cookies:
        headers["Cookie"] = cookies
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=ctx) as resp:
            body = read_body(resp)
            return resp.status, resp.geturl(), dict(resp.headers), body
    except urllib.error.HTTPError as e:
        body = ""
        try:
            body = read_body(e)
        except Exception:
            pass
        return e.code, url, dict(e.headers or {}), body


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", required=True)
    ap.add_argument("--ua", choices=["mobile", "pc"], default="mobile")
    ap.add_argument("--cookie", default="")
    ap.add_argument("--show", type=int, default=400)
    args = ap.parse_args()

    ua = MOBILE_UA if args.ua == "mobile" else PC_UA
    status, final_url, headers, body = fetch(args.url, ua, args.cookie)

    print(f"status   = {status}")
    print(f"final    = {final_url}")
    set_cookie = headers.get("Set-Cookie") or headers.get("set-cookie") or ""
    print(f"set-cookie = {set_cookie[:200]}")
    print(f"length   = {len(body)}")
    print("markers  =", [m for m in MARKERS if m in body])
    lowered = body.lower()
    if "verify" in lowered:
        print("note     : body contains 'verify'")
    print("--- head ---")
    print(body[: args.show].replace("\n", " ")[: args.show])
    return 0


if __name__ == "__main__":
    sys.exit(main())