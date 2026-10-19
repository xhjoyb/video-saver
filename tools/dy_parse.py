#!/usr/bin/env python3
"""抖音分享页解析原型（Dart 解析器的蓝本）。

用法:
    python3 tools/dy_parse.py --input "https://v.douyin.com/xxxxx/"
    python3 tools/dy_parse.py --input 7312345678901234567

流程:
    分享文本 → 提取短链 → 跟随 302 拿 aweme_id → share 页 SSR 的 _ROUTER_DATA
    → videoInfoRes.item_list[0] → 取 play_addr / images / music → playwm 去水印
"""

import argparse
import json
import re
import ssl
import sys
import urllib.error
import urllib.request

MOBILE_UA = (
    "Mozilla/5.0 (Linux; Android 14; PGT-AN20 Build/HONORPGT-AN20) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"
)
URL_RE = re.compile(r"https?://[^\s\u4e00-\u9fa5]+")
ID_RE = re.compile(r"/(?:video|note)/(\d{15,20})")
MODAL_RE = re.compile(r"[?&]modal_id=(\d{15,20})")
SHORT_HOSTS = ("v.douyin.com", "v.iesdouyin.com")


def http_get(url, ua=MOBILE_UA, timeout=20, max_bytes=None):
    ctx = ssl.create_default_context()
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": ua,
            "Accept-Language": "zh-CN,zh;q=0.9",
            "Accept": "text/html,application/json,*/*",
        },
    )
    with urllib.request.urlopen(req, timeout=timeout, context=ctx) as resp:
        data = resp.read() if max_bytes is None else resp.read(max_bytes)
        return resp.status, resp.geturl(), dict(resp.headers), data


def extract_url(text):
    m = URL_RE.search(text or "")
    return m.group(0) if m else None


def resolve_aweme_id(raw):
    """接受分享文本 / 短链 / 长链 / 纯 id，返回 (aweme_id, 中间跳转链)。"""
    raw = (raw or "").strip()
    if re.fullmatch(r"\d{15,20}", raw):
        return raw, []
    url = extract_url(raw)
    if not url:
        raise SystemExit("输入里找不到链接或 id")

    trail = [url]
    host = url.split("/")[2]
    if any(h in host for h in SHORT_HOSTS):
        status, final, _, _ = http_get(url)
        trail.append(final)
        m = ID_RE.search(final) or MODAL_RE.search(final)
        if m:
            return m.group(1), trail
        # 部分短链 LOCATION 里只有 modal_id
        if "modal_id=" in final:
            m2 = MODAL_RE.search(final)
            if m2:
                return m2.group(1), trail
        raise SystemExit(f"短链未能解析出 aweme_id，最终地址：{final}")

    m = ID_RE.search(url) or MODAL_RE.search(url)
    if m:
        return m.group(1), trail
    raise SystemExit(f"链接里没有 video/note id：{url}")


def fetch_router_data(aweme_id):
    url = f"https://www.iesdouyin.com/share/video/{aweme_id}"
    status, final, headers, raw = http_get(url)
    body = raw.decode("utf-8", "replace")
    idx = body.find("window._ROUTER_DATA")
    if idx < 0:
        raise SystemExit(f"页面里没有 _ROUTER_DATA（status={status} len={len(body)}）")
    start = body.find("{", idx)
    try:
        obj, _ = json.JSONDecoder().raw_decode(body[start:])
    except json.JSONDecodeError as e:
        raise SystemExit(f"_ROUTER_DATA JSON 解析失败: {e}")
    return obj, status, final


def pick_video_info(router):
    loader = router.get("loaderData") or {}
    for key, value in loader.items():
        if isinstance(value, dict) and isinstance(value.get("videoInfoRes"), dict):
            return value["videoInfoRes"], key
    return None, None


def first_url(node):
    """兼容 {"url_list": [...]} / ["url"] / "url" 三种形态。"""
    if not node:
        return None
    if isinstance(node, str):
        return node
    if isinstance(node, list):
        return node[0] if node else None
    if isinstance(node, dict):
        lst = node.get("url_list") or node.get("urlList")
        if lst:
            return lst[0]
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True, help="分享文本 / 短链 / 长链 / 纯 aweme_id")
    ap.add_argument("--json", action="store_true", help="输出完整 JSON")
    args = ap.parse_args()

    aweme_id, trail = resolve_aweme_id(args.input)
    print(f"aweme_id = {aweme_id}")
    for t in trail:
        print(f"  hop: {t}")

    router, status, final = fetch_router_data(aweme_id)
    info, key = pick_video_info(router)
    print(f"share page status={status} key={key}")

    if not info:
        print("!! 页面里没有 videoInfoRes（可能是无效 id、已删除、或需要登录/cookie）")
        if args.json:
            print(json.dumps(router, ensure_ascii=False)[:1200])
        return 2

    items = info.get("item_list") or []
    if not items:
        print("!! videoInfoRes.item_list 为空")
        print("   filter_list:", json.dumps(info.get("filter_list"), ensure_ascii=False)[:300])
        return 2

    item = items[0]
    video = item.get("video") or {}
    play = first_url(video.get("play_addr")) or first_url(video.get("playAddr"))
    playwm = first_url(video.get("play_addr_h264")) or first_url(video.get("download_addr"))
    images = item.get("images") or []
    music = first_url((item.get("music") or {}).get("play_url"))

    print(f"title    = {(item.get('desc') or '')[:60]}")
    print(f"author   = {(item.get('author') or {}).get('nickname')}")
    print(f"duration = {video.get('duration')} ms")
    print(f"cover    = {first_url(video.get('cover'))}")
    print(f"play(raw)= {play}")
    if play and "playwm" in play:
        print(f"play(nowm)= {play.replace('playwm', 'play')}")
    print(f"h264/dl  = {playwm}")
    print(f"music    = {music}")
    print(f"images   = {len(images)} 张")
    if images:
        print(f"  first  = {first_url(images[0])}")

    if args.json:
        print(json.dumps(item, ensure_ascii=False)[:2000])
    return 0


if __name__ == "__main__":
    sys.exit(main())