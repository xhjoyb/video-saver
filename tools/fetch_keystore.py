#!/usr/bin/env python3
"""从 Actions artifact 取回 keystore，并导出 base64（用于写入仓库 Secret）。

用法:
    GH_TOKEN=... python3 tools/fetch_keystore.py --owner xhjoyb --repo video-saver --out keystore/release.jks
"""

import argparse
import json
import os
import ssl
import sys
import urllib.error
import urllib.request
import zipfile
import io


def api_get(token, path, accept="application/vnd.github+json"):
    ctx = ssl.create_default_context()
    req = urllib.request.Request(
        "https://api.github.com" + path,
        headers={
            "Authorization": "Bearer " + token,
            "Accept": accept,
            "User-Agent": "fetch-keystore",
        },
    )
    return urllib.request.urlopen(req, timeout=60, context=ctx)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--owner", required=True)
    ap.add_argument("--repo", required=True)
    ap.add_argument("--name", default="keystore-backup")
    ap.add_argument("--ext", default=".jks", help="zip 内要提取的文件扩展名，如 .jks / .apk")
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    token = os.environ.get("GH_TOKEN", "")
    if not token:
        print("ERROR: 缺少 GH_TOKEN")
        return 2

    arts = json.loads(
        api_get(token, f"/repos/{args.owner}/{args.repo}/actions/artifacts?per_page=100").read()
    )["artifacts"]
    cand = [a for a in arts if a["name"] == args.name and not a["expired"]]
    if not cand:
        print(f"没有可用的 artifact: {args.name}")
        return 1
    art = sorted(cand, key=lambda a: a["created_at"])[-1]
    print(f"artifact {art['id']} created={art['created_at']} size={art['size_in_bytes']}")

    ctx = ssl.create_default_context()

    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, headers, newurl):
            return None

    opener = urllib.request.build_opener(NoRedirect, urllib.request.HTTPSHandler(context=ctx))
    req = urllib.request.Request(
        f"https://api.github.com/repos/{args.owner}/{args.repo}/actions/artifacts/{art['id']}/zip",
        headers={
            "Authorization": "Bearer " + token,
            "Accept": "application/vnd.github+json",
            "User-Agent": "fetch-keystore",
        },
    )
    direct = None
    try:
        opener.open(req, timeout=60)
    except urllib.error.HTTPError as e:
        if e.code in (301, 302, 303, 307, 308):
            direct = e.headers.get("Location")
        else:
            raise RuntimeError(f"artifact 下载失败 HTTP {e.code}")
    if not direct:
        raise RuntimeError("未拿到 artifact 直链")

    data = urllib.request.urlopen(direct, timeout=60, context=ctx).read()
    print(f"downloaded zip {len(data)} bytes")

    zf = zipfile.ZipFile(io.BytesIO(data))
    names = zf.namelist()
    print("entries:", names)
    target = None
    for n in names:
        if n.endswith(args.ext):
            target = n
            break
    if not target:
        print(f"zip 中找不到 {args.ext} 文件")
        return 1

    os.makedirs(os.path.dirname(os.path.abspath(args.out)) or ".", exist_ok=True)
    with open(args.out, "wb") as fh:
        fh.write(zf.read(target))
    print(f"OK: {args.out} {os.path.getsize(args.out)} bytes (from {target})")
    return 0


if __name__ == "__main__":
    sys.exit(main())