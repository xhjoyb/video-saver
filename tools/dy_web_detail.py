#!/usr/bin/env python3
"""用自研 a_bogus 签名请求抖音 web detail 接口，验证签名是否被接受。"""

import gzip
import json
import ssl
import sys
import urllib.error
import urllib.parse
import urllib.request

sys.path.insert(0, "tools")
from abogus import ABogus  # noqa: E402

UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
)
AWEME_ID = "7695215729926784320"


def build_query(aweme_id: str) -> str:
    params = [
        ("device_platform", "webapp"),
        ("aid", "6383"),
        ("channel", "channel_pc_web"),
        ("aweme_id", aweme_id),
        ("pc_client_type", "1"),
        ("version_code", "170400"),
        ("version_name", "17.4.0"),
        ("cookie_enabled", "true"),
        ("screen_width", "1920"),
        ("screen_height", "1080"),
        ("browser_language", "zh-CN"),
        ("browser_platform", "Win32"),
        ("browser_name", "Chrome"),
        ("browser_version", "120.0.0.0"),
        ("browser_online", "true"),
        ("engine_name", "Blink"),
        ("engine_version", "120.0.0.0"),
        ("os_name", "Windows"),
        ("os_version", "10"),
        ("platform", "PC"),
    ]
    return urllib.parse.urlencode(params)


def main():
    query = build_query(AWEME_ID)
    sig = ABogus(UA).get_value(query)
    print("a_bogus len:", len(sig))
    print("a_bogus:", sig[:60], "...")

    url = (
        "https://www.douyin.com/aweme/v1/web/aweme/detail/?"
        + query
        + "&a_bogus="
        + urllib.parse.quote(sig, safe="")
    )
    ctx = ssl.create_default_context()
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": UA,
            "Accept": "application/json, text/plain, */*",
            "Accept-Language": "zh-CN,zh;q=0.9",
            "Referer": "https://www.douyin.com/",
            "Accept-Encoding": "gzip",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=25, context=ctx) as resp:
            raw = resp.read()
            if (resp.headers.get("Content-Encoding") or "").lower() == "gzip":
                raw = gzip.decompress(raw)
            body = raw.decode("utf-8", "replace")
            print("status:", resp.status, "len:", len(body))
            print("head:", body[:400])
            try:
                data = json.loads(body)
                print("keys:", list(data.keys())[:10])
                detail = data.get("aweme_detail")
                if detail:
                    print("aweme_id:", detail.get("aweme_id"))
                    print("desc:", (detail.get("desc") or "")[:40])
                    video = detail.get("video") or {}
                    play = video.get("play_addr") or {}
                    urls = play.get("url_list") or []
                    print("play_addr count:", len(urls))
                    if urls:
                        print("play_addr[0]:", urls[0][:160])
                else:
                    print("no aweme_detail")
            except Exception as e:
                print("json parse fail:", e)
            return 0
    except urllib.error.HTTPError as e:
        body = ""
        try:
            body = e.read().decode("utf-8", "replace")
        except Exception:
            pass
        print("HTTP", e.code, body[:400])
        return 1
    except Exception as e:
        print("ERR", type(e).__name__, e)
        return 1


if __name__ == "__main__":
    sys.exit(main())