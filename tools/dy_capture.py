#!/usr/bin/env python3
"""抓包会话里筛 HTTP 请求，找抖音接口。

用法:
    python3 tools/dy_capture.py <sessionId> [关键字...]
"""

import json
import sys

sys.path.insert(0, "tools")
from mcp_capture import rpc  # noqa: E402


def call(name, args):
    out = rpc("tools/call", {"name": name, "arguments": args})
    content = out.get("result", {}).get("content", [])
    if not content:
        return {}
    return json.loads(content[0]["text"])


def main():
    sid = sys.argv[1]
    keys = [k.lower() for k in sys.argv[2:]]

    items = []
    cursor = "0"
    for _ in range(10):
        page = call("network_list", {"sessionId": sid, "limit": 200, "afterId": cursor})
        batch = page.get("items", [])
        items.extend(batch)
        nxt = page.get("nextAfterId")
        if not nxt or not batch:
            break
        cursor = nxt

    http = [x for x in items if x.get("protocol") == "HTTP"]
    print(f"total={len(items)} http={len(http)}")

    from collections import Counter

    hosts = Counter()
    for x in http:
        url = x.get("url") or ""
        host = url.split("/")[2] if "://" in url else "?"
        hosts[host] += 1
    print("hosts:", dict(hosts.most_common(12)))

    print("--- matched ---")
    shown = 0
    for x in http:
        url = x.get("url") or ""
        if keys and not any(k in url.lower() for k in keys):
            continue
        print(f'{x.get("method","?"):4} {x.get("dataSizeBytes",0):>8} {url[:160]}')
        shown += 1
        if shown >= 40:
            break
    return 0


if __name__ == "__main__":
    sys.exit(main())