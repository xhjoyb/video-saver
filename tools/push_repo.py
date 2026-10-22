#!/usr/bin/env python3
"""通过 GitHub Git Data API 推送本地目录到仓库。

本机到 github.com:443 不通、git push 会挂起，但 api.github.com 可达，
因此统一用 REST API 提交（blob → tree → commit → ref）。

用法:
    GH_TOKEN=$(gh auth token --user xhjoyb) python3 tools/push_repo.py \
        --owner xhjoyb --repo video-saver --branch main \
        --dir . --message "feat: xxx"

特性:
- 按 blob sha 增量上传，内容未变的文件不重复上传
- 每个请求带重试（网络抖动 / 5xx / 429）
- 首次建库（无 commit）自动创建 ref
- gradlew 以 100755 模式写入，保证 CI 中可执行
"""

import argparse
import base64
import hashlib
import json
import os
import ssl
import sys
import time
import urllib.error
import urllib.request

API = "https://api.github.com"

EXCLUDED_DIRS = {
    ".git", ".gradle", "build", ".idea", ".operit", ".backup",
    "keystore", "__pycache__", "output", ".cxx", ".externalNativeBuild",
    ".dart_tool", ".pub-cache", "release",
}

EXCLUDED_SUFFIXES = (
    ".apk", ".aab", ".jks", ".keystore", ".p12", ".ap_", ".dex", ".iml",
    ".log", ".txt",
)

EXCLUDED_FILES = {
    "local.properties", "keystore.properties", ".DS_Store", "Thumbs.db",
}

EXECUTABLE_NAMES = {"gradlew"}


def log(msg):
    print(msg, flush=True)


class GhApi:
    def __init__(self, token):
        self.token = token
        self.ctx = ssl.create_default_context()

    def call(self, method, path, body=None, retries=4, allow=(404,)):
        url = path if path.startswith("http") else API + path
        data = None
        if body is not None:
            data = json.dumps(body).encode("utf-8")
        headers = {
            "Authorization": "Bearer " + self.token,
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "videosaver-push",
        }
        if data is not None:
            headers["Content-Type"] = "application/json"

        last_err = None
        for attempt in range(1, retries + 1):
            req = urllib.request.Request(url, data=data, headers=headers, method=method)
            try:
                with urllib.request.urlopen(req, timeout=60, context=self.ctx) as resp:
                    raw = resp.read()
                    if not raw:
                        return None
                    return json.loads(raw.decode("utf-8"))
            except urllib.error.HTTPError as e:
                payload = e.read().decode("utf-8", "replace")[:400]
                # 404: 资源不存在；409: 仓库为空（由调用方决定是否容忍）
                if e.code in allow:
                    return {"__status__": e.code, "__body__": payload}
                if e.code in (403, 429, 500, 502, 503, 504) and attempt < retries:
                    wait = 2 ** attempt
                    log(f"  ! HTTP {e.code} on {method} {path}, retry in {wait}s")
                    time.sleep(wait)
                    last_err = f"HTTP {e.code}: {payload}"
                    continue
                raise RuntimeError(f"HTTP {e.code} {method} {url}\n{payload}")
            except Exception as e:  # 网络层错误
                if attempt < retries:
                    wait = 2 ** attempt
                    log(f"  ! {type(e).__name__} on {method} {path}, retry in {wait}s")
                    time.sleep(wait)
                    last_err = str(e)
                    continue
                raise RuntimeError(f"{type(e).__name__} {method} {url}: {e}")
        raise RuntimeError(f"request failed: {last_err}")


def blob_sha(data):
    header = b"blob %d\0" % len(data)
    return hashlib.sha1(header + data).hexdigest()


def collect_files(root):
    result = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(d for d in dirnames if d not in EXCLUDED_DIRS)
        for name in sorted(filenames):
            if name in EXCLUDED_FILES or name.endswith(EXCLUDED_SUFFIXES):
                continue
            full = os.path.join(dirpath, name)
            if os.path.islink(full):
                continue
            rel = os.path.relpath(full, root).replace(os.sep, "/")
            with open(full, "rb") as fh:
                data = fh.read()
            mode = "100755" if name in EXECUTABLE_NAMES else "100644"
            result.append((rel, data, mode))
    return result


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--owner", required=True)
    ap.add_argument("--repo", required=True)
    ap.add_argument("--branch", default="main")
    ap.add_argument("--dir", default=".")
    ap.add_argument("--message", required=True)
    ap.add_argument("--token", default=os.environ.get("GH_TOKEN", ""))
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--prune", action="store_true", help="删除远端存在但本地已不存在的文件")
    args = ap.parse_args()

    if not args.token:
        log("ERROR: 缺少 token（--token 或 GH_TOKEN）")
        return 2

    gh = GhApi(args.token)
    root = os.path.abspath(args.dir)
    files = collect_files(root)
    log(f"本地文件 {len(files)} 个，根目录 {root}")
    if not files:
        log("ERROR: 没有可推送文件")
        return 2

    ref_get_path = f"/repos/{args.owner}/{args.repo}/git/ref/heads/{args.branch}"
    ref_patch_path = f"/repos/{args.owner}/{args.repo}/git/refs/heads/{args.branch}"
    ref = gh.call("GET", ref_get_path, allow=(404, 409))
    base_tree = None
    parents = []
    if isinstance(ref, dict) and ref.get("object", {}).get("sha"):
        base_commit = ref["object"]["sha"]
        parents = [base_commit]
        commit = gh.call("GET", f"/repos/{args.owner}/{args.repo}/git/commits/{base_commit}")
        base_tree = commit["tree"]["sha"]
        log(f"已有分支 {args.branch} @ {base_commit[:8]}, base_tree={base_tree[:8]}")
    else:
        log(f"分支 {args.branch} 不存在，将创建首个提交")

    remote_blobs = {}
    if base_tree:
        tree = gh.call(
            "GET",
            f"/repos/{args.owner}/{args.repo}/git/trees/{base_tree}?recursive=1",
        )
        for item in tree.get("tree", []):
            if item.get("type") == "blob":
                remote_blobs[item["path"]] = item["sha"]
        log(f"远端已有 blob {len(remote_blobs)} 个")

    tree_entries = []
    uploaded = 0
    unchanged = 0
    for rel, data, mode in files:
        sha = blob_sha(data)
        if remote_blobs.get(rel) != sha:
            if args.dry_run:
                log(f"  [dry] would upload {rel} ({len(data)} B)")
            else:
                resp = gh.call(
                    "POST",
                    f"/repos/{args.owner}/{args.repo}/git/blobs",
                    {"content": base64.b64encode(data).decode("ascii"), "encoding": "base64"},
                )
                sha = resp["sha"]
                uploaded += 1
                log(f"  + {rel} ({len(data)} B)")
        else:
            unchanged += 1
        tree_entries.append({"path": rel, "mode": mode, "type": "blob", "sha": sha})

    log(f"上传 {uploaded} 个，复用 {unchanged} 个")

    if args.prune and remote_blobs:
        local_paths = {rel for rel, _, _ in files}
        removed = 0
        for path in sorted(remote_blobs):
            if path not in local_paths:
                tree_entries.append(
                    {"path": path, "mode": "100644", "type": "blob", "sha": None}
                )
                removed += 1
                log(f"  - {path}")
        log(f"删除远端多余文件 {removed} 个")

    if args.dry_run:
        return 0

    tree_body = {"tree": tree_entries}
    if base_tree:
        tree_body["base_tree"] = base_tree
    new_tree = gh.call("POST", f"/repos/{args.owner}/{args.repo}/git/trees", tree_body)
    log(f"tree={new_tree['sha'][:8]}")

    commit_body = {"message": args.message, "tree": new_tree["sha"], "parents": parents}
    new_commit = gh.call("POST", f"/repos/{args.owner}/{args.repo}/git/commits", commit_body)
    log(f"commit={new_commit['sha'][:8]}")

    if parents:
        res = gh.call("PATCH", ref_patch_path, {"sha": new_commit["sha"], "force": False})
        if not isinstance(res, dict) or res.get("object", {}).get("sha") != new_commit["sha"]:
            raise RuntimeError(f"更新 ref 失败，服务端返回: {res}")
    else:
        gh.call(
            "POST",
            f"/repos/{args.owner}/{args.repo}/git/refs",
            {"ref": f"refs/heads/{args.branch}", "sha": new_commit["sha"]},
        )
    log(f"OK: 已推送到 {args.owner}/{args.repo}:{args.branch} -> {new_commit['sha']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())