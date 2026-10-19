#!/bin/sh
# 等待最新一次 CI 完成，并下载对应 Release 的 APK（后台运行，日志写工作区）
cd "$(dirname "$0")/.." || exit 1
export GH_TOKEN=$(gh auth token --user xhjoyb)

: > release/ci.log
for i in $(seq 1 60); do
  python3 tools/ci_status.py --owner xhjoyb --repo video-saver > release/ci.log 2>&1
  if grep -q "completed" release/ci.log 2>/dev/null; then
    break
  fi
  sleep 15
done

TAG=$(gh api "repos/xhjoyb/video-saver/releases?per_page=1" --jq '.[0] | .tag_name' 2>/dev/null)
echo "TAG=$TAG" >> release/ci.log
python3 tools/dl_asset.py --owner xhjoyb --repo video-saver --tag "$TAG" \
  --name app-release.apk --out release/probe4.apk --threads 12 >> release/ci.log 2>&1
echo "DONE=$?" >> release/ci.log