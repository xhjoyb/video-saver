#!/usr/bin/env python3
"""从日志文本里抽取第一条 http(s) 链接写入文件。

用法: python3 tools/extract_url.py <log.txt> <out.txt> [keyword]
"""

import re
import sys

text = open(sys.argv[1], "r", encoding="utf-8", errors="replace").read()
keyword = sys.argv[3] if len(sys.argv) > 3 else ""
pat = r'https://[^"\s\\]+'
best = ""
for m in re.finditer(pat, text):
    url = m.group(0)
    if keyword and keyword not in url:
        continue
    if len(url) > len(best):
        best = url
open(sys.argv[2], "w", encoding="utf-8").write(best)
print("url_len =", len(best))
print("host =", best.split("/")[2] if "://" in best else "-")