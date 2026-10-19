#!/usr/bin/env python3
"""多线程下载 Actions artifact 并提取指定扩展名文件。

用法:
    GH_TOKEN=... python3 tools/dl_artifact.py --owner xhjoyb --repo video-saver \
        --name videosaver-apk --ext .apk --out release/videosaver_build5.apk
"""

import argparse
import io
import json
import os
import ssl
import sys
import urllib.error
import urllib.request
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dl_asset import download_range  # noqa: E402


def api_get(token, path):
    ctx = ssl.create_default_context()
    req = urllib.request.Request(
        "https://api.github.com" + path,
        headers={
            "Authorization": "Bearer " + token,
            "Accept": "application/vnd.github+json",
            "User-Agent": "dl-artifact",
        },
    )
    return urllib.request.urlopen(req, timeout=60, context=ctx)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--owner", required=True)
    ap.add_argument("--repo", required=True)
    ap.add_argument("--name", required=True)
    ap.add_argument("--ext", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--threads", type=int, default=8)
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
        print(f"没有可用 artifact: {args.name}")
        return 1
    art = sorted(cand, key=lambda a: a["created_at"])[-1]
    size = art["size_in_bytes"]
    print(f"artifact {art['id']} size={size} created={art['created_at']}")

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
            "User-Agent": "dl-artifact",
        },
    )
    direct = None
    try:
        opener.open(req, timeout=60)
    except urllib.error.HTTPError as e:
        if e.code in (301, 302, 303, 307, 308):
            direct = e.headers.get("Location")
        else:
            raise RuntimeError(f"HTTP {e.code}")
    if not direct:
        raise RuntimeError("未拿到直链")
    print("host:", direct.split("/")[2])

    tmp = f"/tmp/artifact_{art['id']}.zip"
    if not (os.path.exists(tmp) and os.path.getsize(tmp) == size):
        n = max(1, args.threads)
        part = (size + n - 1) // n
        parts = []
        for i in range(n):
            s = i * part
            e = min(size - 1, s + part - 1)
            if s > e:
                continue
            parts.append((i, s, e, f"/tmp/art_{art['id']}_p{i:02d}"))
        from concurrent.futures import ThreadPoolExecutor

        with ThreadPoolExecutor(max_workers=n) as ex:
            list(ex.map(lambda j: download_range(direct, j[1], j[2], j[3], j[0]), parts))
        with open(tmp, "wb") as out:
            for _, _, _, p in parts:
                with open(p, "rb") as fh:
                    out.write(fh.read())
                os.remove(p)
    print(f"zip {os.path.getsize(tmp)} bytes")

    zf = zipfile.ZipFile(tmp)
    names = zf.namelist()
    print("entries:", names)
    target = next((n for n in names if n.endswith(args.ext)), None)
    if not target:
        print(f"zip 中找不到 {args.ext}")
        return 1

    os.makedirs(os.path.dirname(os.path.abspath(args.out)) or ".", exist_ok=True)
    with open(args.out, "wb") as fh:
        fh.write(zf.read(target))
    print(f"OK: {args.out} {os.path.getsize(args.out)} bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())