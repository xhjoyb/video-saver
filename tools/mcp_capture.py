#!/usr/bin/env python3
"""直接通过 HTTP 调用「算法助手Pro」抓包 MCP（绕过 Operit 的 MCP 注册状态）。

用法:
    python3 tools/mcp_capture.py tools
    python3 tools/mcp_capture.py call capture_status
    python3 tools/mcp_capture.py call network_list '{"sessionId":"...","limit":5}'
"""

import json
import sys
import urllib.request

URL = "http://127.0.0.1:8799/mcp"
SESSION = {"id": 1}


def rpc(method, params=None):
    SESSION["id"] += 1
    body = {"jsonrpc": "2.0", "id": SESSION["id"], "method": method}
    if params is not None:
        body["params"] = params
    req = urllib.request.Request(
        URL,
        data=json.dumps(body).encode(),
        headers={
            "Content-Type": "application/json",
            "Accept": "application/json, text/event-stream",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        raw = resp.read().decode("utf-8", "replace")
    # 兼容 SSE 包装
    if raw.startswith("event:") or "data:" in raw[:40]:
        for line in raw.splitlines():
            if line.startswith("data:"):
                raw = line[5:].strip()
                break
    return json.loads(raw) if raw else None


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    cmd = sys.argv[1]
    if cmd == "tools":
        out = rpc("tools/list")
        names = [t["name"] for t in out.get("result", {}).get("tools", [])]
        print(f"{len(names)} tools")
        print("\n".join(names))
        return 0
    if cmd == "call":
        name = sys.argv[2]
        args = json.loads(sys.argv[3]) if len(sys.argv) > 3 else {}
        out = rpc("tools/call", {"name": name, "arguments": args})
        text = json.dumps(out, ensure_ascii=False)
        print(text[:4000])
        return 0
    print("unknown command")
    return 2


if __name__ == "__main__":
    sys.exit(main())