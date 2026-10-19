#!/usr/bin/env python3
"""多线程 Range 下载 GitHub Release 资产（单连接慢时提速）。

用法:
    GH_TOKEN=... python3 tools/dl_asset.py \
        --owner xhjoyb --repo video-saver --tag build-4 \
        --name app-release.apk --out release/app-release.apk --threads 8
"""

import argparse
import json
import os
import ssl
import sys
import threading
import urllib.request

CHUNK = 512 * 1024


def resolve_asset_urls(token, owner, repo, tag, name):
    """返回 (api_url, direct_url, size)。"""
    ctx = ssl.create_default_context()
    req = urllib.request.Request(
        f"https://api.github.com/repos/{owner}/{repo}/releases/tags/{tag}",
        headers={
            "Authorization": "Bearer " + token,
            "Accept": "application/vnd.github+json",
            "User-Agent": "dl-asset",
        },
    )
    with urllib.request.urlopen(req, timeout=45, context=ctx) as resp:
        rel = json.loads(resp.read().decode())

    asset = None
    for a in rel.get("assets", []):
        if a["name"] == name:
            asset = a
            break
    if not asset:
        raise RuntimeError(f"release {tag} 中没有资产 {name}")

    # 用 Asset API + Accept: octet-stream 拿 302 Location
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, headers, newurl):
            return None

    opener = urllib.request.build_opener(
        NoRedirect, urllib.request.HTTPSHandler(context=ctx)
    )
    req2 = urllib.request.Request(
        asset["url"],
        headers={
            "Authorization": "Bearer " + token,
            "Accept": "application/octet-stream",
            "User-Agent": "dl-asset",
        },
    )
    direct = None
    try:
        opener.open(req2, timeout=45)
    except urllib.error.HTTPError as e:
        if e.code in (301, 302, 303, 307, 308):
            direct = e.headers.get("Location")
        else:
            raise
    if not direct:
        raise RuntimeError("未能拿到资产直链")
    return asset["url"], direct, asset["size"]


def download_range(url, start, end, path, idx, token_headers=None):
    headers = {"User-Agent": "dl-asset", "Range": f"bytes={start}-{end}"}
    req = urllib.request.Request(url, headers=headers)
    ctx = ssl.create_default_context()
    with urllib.request.urlopen(req, timeout=120, context=ctx) as resp, open(path, "wb") as fh:
        while True:
            buf = resp.read(65536)
            if not buf:
                break
            fh.write(buf)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--owner", required=True)
    ap.add_argument("--repo", required=True)
    ap.add_argument("--tag", required=True)
    ap.add_argument("--name", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--threads", type=int, default=8)
    args = ap.parse_args()

    token = os.environ.get("GH_TOKEN", "")
    if not token:
        print("ERROR: 缺少 GH_TOKEN")
        return 2

    api_url, direct, size = resolve_asset_urls(
        token, args.owner, args.repo, args.tag, args.name
    )
    print(f"asset size = {size} bytes, url host = {direct.split('/')[2]}", flush=True)

    os.makedirs(os.path.dirname(os.path.abspath(args.out)) or ".", exist_ok=True)
    tmpdir = args.out + ".parts"
    os.makedirs(tmpdir, exist_ok=True)

    n = max(1, args.threads)
    part = (size + n - 1) // n
    jobs = []
    for i in range(n):
        start = i * part
        end = min(size - 1, start + part - 1)
        if start > end:
            continue
        jobs.append((i, start, end, os.path.join(tmpdir, f"p{i:02d}")))

    errors = []

    def worker(i, start, end, path):
        exp = end - start + 1
        if os.path.exists(path) and os.path.getsize(path) == exp:
            return  # 分片已完整，跳过（断点续传）
        try:
            download_range(direct, start, end, path, i)
            got = os.path.getsize(path)
            if got != exp:
                raise RuntimeError(f"part {i} 大小不符 {got}/{exp}")
        except Exception as e:  # noqa: BLE001
            errors.append(f"part {i}: {e}")

    threads = [threading.Thread(target=worker, args=j) for j in jobs]
    for t in threads:
        t.start()
    for t in threads:
        t.join()

    if errors:
        print("下载失败: " + "; ".join(errors))
        return 1

    with open(args.out, "wb") as out:
        for i, _, _, path in jobs:
            with open(path, "rb") as fh:
                while True:
                    buf = fh.read(1024 * 1024)
                    if not buf:
                        break
                    out.write(buf)

    final = os.path.getsize(args.out)
    print(f"完成: {args.out} {final} bytes (期望 {size})", flush=True)
    if final != size:
        print("ERROR: 大小不符")
        return 1
    for _, _, _, path in jobs:
        try:
            os.remove(path)
        except OSError:
            pass
    try:
        os.rmdir(tmpdir)
    except OSError:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())