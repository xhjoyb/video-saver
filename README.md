# 视频嗅探 VideoSaver

多平台视频解析下载 App。首个平台：抖音（视频 / 图集，无水印）。

- 包名：`com.xhjoyb.videosaver`
- 技术栈：Flutter 3.24.5 + Material 3，Kotlin 原生壳（MethodChannel）
- Android：minSdk 26 / targetSdk 34，仅 arm64 出包
- 构建：GitHub Actions 云端构建 → Release
- 当前基线：**`flutter-31`**（commit `8ed10b4`，App 内版本 `0.3.0 (build 3)`），语义 tag `v0.3.0`
- 仓库：**public** — https://github.com/xhjoyb/video-saver

## 当前能力

| 能力 | 状态 |
|---|---|
| 抖音分享文本 / 短链 / 纯 ID 解析 | ✅ |
| 无水印视频直链（封面 / 标题 / 作者 / 时长） | ✅ |
| 下载（带 Referer、进度、Range 支持） | ✅ |
| 视频落盘 `Movies/VideoSaver`（MediaStore） | ✅ |
| 图集解析 + 多选保存（逐张勾选，落 `Pictures/VideoSaver`） | ✅ |
| 图片按真实格式（jpg/png/webp）入库 | ✅ |
| 解析历史（本地持久化、已下载标记、复制直链、清空） | ✅ |
| 日间 / 夜间主题（跟随系统 / 手动） | ✅ |
| 自定义背景（相册图片 / ≤30s 视频静音循环） | ✅ |
| 首次解析被 Argus 拦截时自动重试（最多 3 次） | ✅ |
| 清晰度选择（按 `br` 分 原画 / 高清 / 标清） | ✅ |
| 解析预热（启动后预加载，缩短首次等待） | ✅ |
| 历史搜索 / 点击条目「重新解析」 | ✅ |
| 自适应应用图标 + 深色启动页 | ✅ |
| 多平台（快手 / 小红书 / B 站） | ⏳ 仅 UI 占位 |

## 抖音解析链路（核心）

```
分享文本 / 短链
  → 正则取 URL；v.douyin.com 跟随一次 302 拿到 aweme_id
  → 隐藏 WebView 加载 https://www.iesdouyin.com/share/video/{id}/
       （PC Chrome UA，302 到 www.douyin.com/video/{id}）
  → 页面 JS 自动完成：__ac_nonce/__ac_signature 挑战、生成 UIFID、加载 bdms.js
  → 页面内 fetch /aweme/v1/web/aweme/detail/?aweme_id=…
       （同源请求，bdms.js 自动加 a_bogus，cookie 自动携带）
  → 200 JSON（约 100KB）→ aweme_detail.video.play_addr.url_list / images
  → 下载：带 Referer: https://www.douyin.com/ → 206 video/mp4
  → MediaStore 写入 Movies/VideoSaver（视频）或 Pictures/VideoSaver（图片）
```

对应实现：

| 文件 | 职责 |
|---|---|
| `lib/parser/douyin_parser.dart` | URL/短链 → aweme_id；页面内 detail 请求 JS（含非 JSON 容错） |
| `lib/parser/parse_controller.dart` | 隐藏 WebView 生命周期、页面就绪防抖、JS 结果轮询、**失败重试 3 次**、35s 超时 |
| `lib/parser/parse_result.dart` | 统一结果模型；`isImages` 优先于 `isVideo`（图集作品的 video 字段也可能有值） |
| `lib/download/download_service.dart` | 流式下载 + 进度 + Referer + 图片真实格式探测 |
| `lib/platform/media_store.dart` | MethodChannel → 原生 MediaStore 入库（视频 / 图片分流） |
| `android/.../MainActivity.kt` | `saveVideo` / `saveImage`：插入 MediaStore(IS_PENDING) → 拷贝 → 清除 pending |
| `lib/history/*` | 解析历史（SharedPreferences JSON，最多 50 条，按 awemeId 去重） |

### 为什么是 WebView 而不是纯 HTTP

这一轮做了完整验证（都实测过）：

| 尝试 | 结果 |
|---|---|
| 直接请求 `share/video/{id}` 拿 SSR `_ROUTER_DATA` | ❌ 只返回页面骨架，`videoInfoRes` 不存在 |
| `aweme/v1/web/aweme/detail/`（自带签名） | ❌ `403 Blocked by ArgusSecurityPlugin Uifid Not Found` |
| 自研 `a_bogus`（`tools/abogus.py`） | ✅ 算法复刻成功，但缺 `uifid` 仍 403 |
| 抓包看抖音 App 明文 | ❌ 仅 TCP 层（Cronet + native 信任库） |
| Frida Hook（算法助手Pro） | ✅ 能拿 `play_addr` 并验证无水印，但只能用于抖音进程，不能进自己的 App |
| **WebView 渲染 + 页面内 fetch** | ✅ **可行**：挑战、UIFID、a_bogus 全部由页面 JS 代劳 |

关键结论：

1. **不需要自研 a_bogus**——页面里的 `bdms.js` 会给同源请求自动签名；
2. `uifid` 由 Argus 在浏览器环境生成，纯 HTTP 伪造不了，WebView 里天然就有；
3. 新版 `play_addr` **本身就是无水印地址**（无 `watermark`、无 `playwm`），`playwm → play` 的老规则已过时；
4. 下载必须带 **`Referer: https://www.douyin.com/`**，否则 CDN 403；
5. 移动端 UA 会触发 `snssdk://` 唤起 App，WebView 会整页 `ERR_UNKNOWN_URL_SCHEME`——必须 PC UA + 拦截非 http(s) 导航；
6. **冷启动首次解析可能被 Argus 拦**（cookie 未就绪，返回 "Blocked by …" 纯文本），已改为自动重试 3 次。

## 构建与交付

push 到 `main` → Actions 构建 → Release `flutter-<run_number>`（只保留最新一版）。
仅改文档（`**.md` / `docs/**`）不会触发构建（workflow 有 `paths-ignore`）；需要出包时用 `workflow_dispatch` 手动触发。

```sh
# 查看最新 tag（gh api 默认顺序不是时间序）
gh api 'repos/xhjoyb/video-saver/releases?per_page=100' --jq 'sort_by(.created_at) | last | .tag_name'
```

安装（Android 13+ 需先落 `/data/local/tmp`）：

```sh
su -c 'cp /sdcard/Download/app.apk /data/local/tmp/v.apk && pm install -r /data/local/tmp/v.apk'
```

签名：keystore 固化在 Secret `ANDROID_KEYSTORE_B64`，密码在 `ANDROID_KS_PASS`，
workflow 内无明文；跨版本覆盖安装指纹稳定 `763a3827`。

> 下载判据用**字节数**或 SHA-256，不要看界面上的 MB（v2 签名块在文件末尾，截断即报「安装包没有签名文件」）。

## 调试工具（`tools/`）

| 脚本 | 用途 |
|---|---|
| `push_repo.py` | 本机 `github.com:443` 不通，用 Git Data API 推送（增量 blob + 重试 + prune） |
| `dl_asset.py` / `dl_artifact.py` | 多线程 Range 下载 Release / artifact（单连接会被限速） |
| `fetch_keystore.py` / `ci_status.py` | keystore 取回、CI 状态 |
| `img_ascii.py` | 截图转字符画，无图形环境判断布局 |
| `abogus.py` / `sm3.py` | a_bogus 参考实现（主路径不用，留作纯 HTTP 备选） |
| `dy_*.py` / `mcp_capture.py` / `dy_hook.js` | 抓包 MCP 客户端、Frida Hook 探针、接口探测（逆向期工具） |
| `verify_url.py` | 校验直链（206 / video/mp4 / ftyp / 是否带 watermark） |

App 内开发者页面：**设置 → 开发者 → 解析探针**，把 WebView 加载、错误码、cookie 名、detail 响应写到
`/sdcard/Android/data/com.xhjoyb.videosaver/files/probe_result.json`。

## 已知问题

| 现象 | 原因 | 处理 |
|---|---|---|
| 解析耗时 5–8s | 隐藏 WebView 需加载完整页面 + 等 bdms.js | 已做就绪防抖 + 启动后 900ms 预热（`warmUp()`），预热命中后首次明显更快 |
| 冷启动首次解析偶发被拦 | cookie/签名未就绪，返回 "Blocked by …" | 已改自动重试 3 次 + 超时 35s |
| 图集缩略图偶尔空白 | 图床签名 URL 有时效 / 加载慢 | 不影响保存，失败会明确报「第 N 张写入相册失败」 |
| 图集作品也可能带 `video.play_addr` | 抖音数据特性 | 已改 `isImages` 优先判定 |
| CI 偶发 Release 发布失败 | runner 到 `api.github.com` 超时 | Publish 已加 5 次退避重试 |

## 变更记录（里程碑）

| 版本 | 内容 |
|---|---|
| `flutter-20` | 真实解析链路打通 + 视频下载 + 相册落盘 |
| `flutter-22` | 解析历史（记录页接真实数据），版本升 0.3.0 |
| `flutter-24` | 移除未实现的分享接收入口 |
| `flutter-26` | 图集识别修复 + 图片按真实格式入库 |
| `flutter-27` | 图集逐张多选保存 |
| `flutter-28` | 首次被 Argus 拦截自动重试；首页移除「最近解析」 |
| `flutter-29` | 首页文案去平台化（多平台表述） |
| `flutter-30` | 文档更新（记录 flutter-29 状态与可选目标清单） |
| `flutter-31` | 应用图标 + 深色启动页、解析预热、清晰度选择、历史搜索与重新解析 |

---

## 接下来可选目标（按性价比排序）

### 🟢 低成本 / 明显收益（建议先做）

| 目标 | 说明 | 成本 |
|---|---|---|
| **1. 应用图标 + 启动页** | ✅ 已完成（`flutter-31`）：自适应图标 + 深色 `launch_background` | — |
| **2. 清晰度选择** | ✅ 已完成（`flutter-31`）：按 `br` 排序分 原画/高清/标清 | — |
| **3. 解析预热** | ✅ 已完成（`flutter-31`）：首页 init 后 900ms 调 `warmUp()` 预加载 | — |
| **4. 历史增强** | 🟡 部分完成（`flutter-31`）：搜索 + 重新解析已做；按平台筛选、批量删除未做 | 2h |
| **5. 保存后引导** | 保存完成 SnackBar 加「去相册看看」，直接跳到系统相册对应目录 | 0.5h |

### 🟡 中等成本 / 战略价值

| 目标 | 说明 | 成本 |
|---|---|---|
| **6. B 站接入** | B 站有公开 API（`x/web-interface/view` + `playurl`），最省事的「第二个平台」，能验证多平台抽象是否成立 | 0.5–1 天 |
| **7. 下载队列** | 多任务并发、断点续传、失败重试、通知栏进度（Foreground Service） | 1–2 天 |
| **8. 小红书接入** | 笔记链接 → 图文/视频，需要逆向 SSR 或接口签名 | 1–2 天 |
| **9. 快手接入** | 短链 → 页面解析，风控比抖音轻，但接口/字段要重新摸 | 1–2 天 |

### 🔴 高成本 / 按需再评估（非主线）

- **分享接收（ACTION_SEND）**：需要 intent 冷启动、多入口状态恢复、与粘贴解析去重，已从 Manifest 移除。
- **多账号 / 服务端同步**：需要后端，且涉及隐私合规。
- **a_bogus 纯 HTTP 客户端**：算法已有，但缺 `uifid`（浏览器指纹），除非接第三方打码/指纹服务。
- **iOS / 桌面端**：Flutter 可复用 UI，但下载落盘、分享接收要各写一套原生。

### 我的建议顺序

**1–3 已在 `flutter-31` 落地，4 完成了搜索与重新解析**；下一步建议 **5（保存后引导）→ 6（B 站）** 验证多平台抽象，最后视需要补 7（下载队列）与 4 的剩余项（按平台筛选、批量删除）。