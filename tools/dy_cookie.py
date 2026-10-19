#!/usr/bin/env python3
"""采集 douyin web 的 cookie（ttwid / uifid / msToken 等），并判断是否挑战页。"""

import gzip
import ssl
import urllib.request

PC_UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
)


def fetch(url, ua):
    ctx = ssl.create_default_context()
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": ua,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "zh-CN,zh;q=0.9",
            "Accept-Encoding": "gzip",
        },
    )
    with urllib.request.urlopen(req, timeout=25, context=ctx) as resp:
        raw = resp.read()
        if (resp.headers.get("Content-Encoding") or "").lower() == "gzip":
            raw = gzip.decompress(raw)
        cookies = resp.headers.get_all("Set-Cookie") or []
        return resp.status, resp.geturl(), cookies, raw.decode("utf-8", "replace")


def main():
    for url in ("https://www.douyin.com/", "https://www.douyin.com/discover"):
        try:
            status, final, cookies, body = fetch(url, PC_UA)
        except Exception as e:
            print(url, "ERR", type(e).__name__, e)
            continue
        print("=" * 20)
        print("url:", url, "->", status, final.split("?")[0])
        print("len:", len(body), "challenge:", "jsvmprt" in body or "__ac_nonce" in body)
        for c in cookies:
            print("  cookie:", c[:160])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())