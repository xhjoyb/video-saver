#!/usr/bin/env python3
"""查询 GitHub Actions 运行状态与各步骤结果。

用法:
    GH_TOKEN=... python3 tools/ci_status.py --owner xhjoyb --repo video-saver [--run 12345]
"""

import argparse
import json
import os
import ssl
import sys
import urllib.request


def api(token, path):
    req = urllib.request.Request(
        "https://api.github.com" + path,
        headers={
            "Authorization": "Bearer " + token,
            "Accept": "application/vnd.github+json",
            "User-Agent": "ci-status",
        },
    )
    ctx = ssl.create_default_context()
    with urllib.request.urlopen(req, timeout=45, context=ctx) as resp:
        return json.loads(resp.read().decode("utf-8"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--owner", required=True)
    ap.add_argument("--repo", required=True)
    ap.add_argument("--run", type=int, default=0)
    ap.add_argument("--jobs", action="store_true", help="打印每个步骤状态")
    args = ap.parse_args()

    token = os.environ.get("GH_TOKEN", "")
    if not token:
        print("ERROR: 缺少 GH_TOKEN")
        return 2

    base = f"/repos/{args.owner}/{args.repo}"
    run_id = args.run
    if not run_id:
        runs = api(token, base + "/actions/runs?per_page=1")["workflow_runs"]
        if not runs:
            print("没有运行记录")
            return 1
        run_id = runs[0]["id"]

    r = api(token, f"{base}/actions/runs/{run_id}")
    print(f"run {run_id}: {r['status']} / {r.get('conclusion')}")
    print(f"  branch={r['head_branch']} sha={r['head_sha'][:8]} event={r['event']}")
    print(f"  url={r['html_url']}")
    print(f"  created={r['created_at']} updated={r['updated_at']}")

    if args.jobs:
        jobs = api(token, f"{base}/actions/runs/{run_id}/jobs")["jobs"]
        for j in jobs:
            print(f"job [{j['name']}] {j['status']} / {j.get('conclusion')}")
            for s in j.get("steps", []):
                print(f"   {s['number']:>2}. {s['name']:<42} {s['status']:<10} {s.get('conclusion')}")
    return 0


if __name__ == "__main__":
    sys.exit(main())