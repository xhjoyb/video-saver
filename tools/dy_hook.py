#!/usr/bin/env python3
"""通过抓包 MCP 的 Frida 能力向抖音注入脚本并读日志。

用法:
    python3 tools/dy_hook.py import          # 导入/更新 tools/dy_hook.js 并启用
    python3 tools/dy_hook.py log [offset]    # 读 Frida 日志
    python3 tools/dy_hook.py disable
"""

import json
import sys

sys.path.insert(0, "tools")
from mcp_capture import rpc  # noqa: E402

PKG = "com.ss.android.ugc.aweme"
NAME = "dy_probe"


def call(name, args):
    out = rpc("tools/call", {"name": name, "arguments": args})
    content = out.get("result", {}).get("content", [])
    if not content:
        return out
    text = content[0]["text"]
    try:
        return json.loads(text)
    except Exception:
        return text


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    cmd = sys.argv[1]

    if cmd == "import":
        with open("tools/dy_hook.js", "r", encoding="utf-8") as fh:
            js = fh.read()
        print("import:", call("app_importScript", {"packageName": PKG, "name": NAME, "jsCode": js}))
        print("enable:", call("enable_script", {"packageName": PKG, "scriptName": NAME}))
        return 0

    if cmd == "log":
        offset = int(sys.argv[2]) if len(sys.argv) > 2 else 0
        data = call("frida_get_log", {"packageName": PKG, "offset": offset, "size": 200})
        text = json.dumps(data, ensure_ascii=False)
        print(text[:6000])
        return 0

    if cmd == "logf":
        keep = ("PLAY", "RETURNERS", "HOOK_DONE", "FAIL", "METHODS", "CLASS_HITS")
        data = call("frida_get_log", {"packageName": PKG, "offset": 0, "size": 800})
        items = data.get("items", []) if isinstance(data, dict) else []
        print(f"total={data.get('totalCount') if isinstance(data, dict) else '?'}")
        for it in items:
            p = it.get("payload", "")
            if any(k in p for k in keep):
                print(p[:4000])
        return 0

    if cmd == "disable":
        cfg = call("app_getConfig", {"packageName": PKG})
        print("current enableScript:", cfg.get("enableScript") if isinstance(cfg, dict) else cfg)
        return 0

    print("unknown command")
    return 2


if __name__ == "__main__":
    sys.exit(main())