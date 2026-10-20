# 视频嗅探 VideoSaver

多平台视频解析下载 App。首个平台：抖音（视频 / 图集，无水印）。

- 包名：`com.xhjoyb.videosaver`
- 技术栈：Flutter 3.24.5 + Material 3，Kotlin 原生壳（MethodChannel）
- Android：minSdk 26 / targetSdk 34，仅 arm64 出包
- 构建：GitHub Actions 云端构建 → Release
- 当前基线：**`flutter-47`**（commit `1ad8904c`，App 内版本 `0.5.0 (build 5)`），语义 tag **`v0.5.0`**（上一档 `v0.4.0-bilibili`）
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
| 剪贴板自动识别（切回前台填入链接，可关闭） | ✅ |
| 保存后「去相册看看」直达文件 | ✅ |
| 液态玻璃底部导航：可拖动切换 + 液态形变 + 玻璃材质 | ✅ |
| 下载队列（并发 1–3、失败自动重试、队列卡片） | ✅ |
| 后台下载（前台服务 + 通知栏进度 + WakeLock） | ✅ |
| 自适应应用图标 + 深色启动页 | ✅ |
| 青绿主题图标 + 自绘开屏动画（光环/粒子/描边/扫光） | ✅ |
| 多平台（快手 / 小红书） | ⏳ 仅 UI 占位 |
| **B 站解析**（BV 号 / b23 短链 / 完整链接；720P + 360P） | ✅ |

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

## 品牌视觉

| 项 | 值 / 位置 |
|---|---|
| 青绿主色 | `#19E8BE`；亮 `#6BFFDD`；深 `#00A98A` |
| 墨绿底 | 启动页 `#05100E`、图标底 `#061412` |
| 自适应图标 | `drawable/ic_launcher_foreground.xml` + `ic_launcher_background.xml`（vector 渐变） |
| 位图兜底 | `tools/gen_icons.py` 生成 48–192px PNG（纯标准库，不依赖 Pillow） |
| Android 12+ 系统启动图 | `values-v31/styles.xml` + `drawable/ic_splash_anim.xml`（旋转弧 AnimatedVector） |
| App 内开屏动画 | `lib/app/splash_overlay.dart`：光晕呼吸 / 46 颗上浮光点 / 三层扩散环 / 描边生长 / 三角弹性 / 字距收拢 / 底部扫光，1.9s，点击可跳过 |
| App 内品牌标识 | `lib/widgets/brand_logo.dart`（解析页 header 复用，与 launcher 图标同源几何：青绿渐变圆 + 墨绿播放三角） |
| App 内强调色 | 深色：`accent` `#19E8BE` / `accent2` `#00C9A6` / `onAccent` `#04120F`；浅色：`accent` `#008F76` / `accent2` `#00B394` / `onAccent` 白 |
| 底部导航 | `lib/widgets/liquid_glass_tab_bar.dart`：悬浮玻璃胶囊（`BackdropFilter` 26px + 饱和度 ×1.5 + 白/黑渐变 + 1px 亮边 + 外投影）+ 液态指示器（点击 380ms 缓动 / **水平拖动跟手** / 松手弹簧吸附 / 速度驱动拉伸 22%、拖尾圆角收窄 50%）+ 四层叠加（白玻璃底 / 极淡青绿 / 底部厚度 / 顶亮底暗受光边）+ 顶部镜面高光；无白点、无彩色光斑 |

> 注：Android 12+ 的系统 SplashScreen 只播约 1s（`windowSplashScreenAnimationDuration`），随后由 Flutter 侧动画接力；两侧背景色一致，不会闪白。
> App 内强调色已与图标/开屏统一为青绿，全部集中在 `lib/theme/app_palette.dart`（`accent` / `accent2` / `onAccent`），页面禁止硬编码颜色。
> `onAccent` 是压在 accent 渐变上的前景色：深色主题 accent 偏亮用墨绿文字，浅色主题 accent 偏深用白字，避免「亮青绿上放白字」看不清。

## 构建与交付

push 到 `main` → Actions 构建 → Release `flutter-<run_number>`（只保留最新一版）。
仅改文档（`**.md` / `docs/**`）或 CI 配置（`.github/**`）不会触发构建（workflow 有 `paths-ignore`）；需要出包时用 `workflow_dispatch` 手动触发。

每次 Release 的说明由 workflow 自动生成：取**上一版 Release tag 到本次 commit** 之间的提交标题（`git log --no-merges`），再附构建信息表（commit / run / APK 字节数 / SHA-256），使用 `--notes-file` 发布。首次发布（无上一版）回退为最近 15 条提交。

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
| `gen_icons.py` | 纯标准库生成青绿 launcher PNG（`--preview` 打字符画预览） |
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

### 支线待优化（已知限制）

以下问题已知、不影响主线使用，作为**支线按需排期**，不默认执行：

| 项 | 现状 | 优化方向 |
|---|---|---|
| 下载队列不持久化 | App 进程被系统强杀后队列丢失，需重新入队 | 任务表落盘（SharedPreferences / SQLite）+ 冷启动恢复，未完成任务标记「已中断」 |
| 无断点续传 | 中断后从头重下 | 记录已下载字节 + `Range` 续传；B 站直链有时效，过期需重新解析 |
| 通知无操作按钮 | 通知栏只能看进度，不能暂停/取消 | 给通知加 `PendingIntent` action，广播回传队列控制 |
| B 站仅 720P / 360P | 未登录上限（`qn=80/112` 被服务端降级为 64） | 可选支持粘贴 `SESSDATA` 取 1080P，凭据只存本地、不上传、可一键清除 |
| 番剧 / PGC 受限 | 版权内容拿不到 `durl`，提示「可能需要登录或视频受限」 | 需大会员登录态；或改 dash + 音视频合流（工程量大） |
| 图集仍走同步保存 | 图集不入队，无并发与自动重试 | 把图集拆成多任务入队，任务模型支持图片类型 |

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
| `flutter-32` | （空）文档提交触发的一次重复构建，已取消，无产物 |
| `flutter-33` | 青绿主题图标（adaptive vector + PNG 兜底）、自绘开屏动画、Android 12+ SplashScreen AVD |
| `flutter-34` | 解析页 header 换青绿品牌 Logo（`BrandLogo`） |
| `flutter-35` | 主题色珊瑚红 → 青绿，新增 `onAccent` 前景色 |
| `flutter-36` | 底部导航换液态形变指示器（拖尾/光点/触觉） |
| `flutter-37` | （已否）传统贴底 Tab Bar 试验 |
| `flutter-38` | 液态玻璃底栏首版（白点/大面积青绿，已否） |
| `flutter-39` | 底栏去白点 + 支持拖动切换 + 玻璃质感重调 |
| `flutter-40` | （失败）新增 Test 步骤发现「空标题文件名重复拼接 aweme_id」，未出包 |
| `flutter-41` | 剪贴板自动识别、保存后「去相册看看」、设置项落地、版本 0.4.0、单测 + CI Test |
| `flutter-42` | 移除震动反馈（设置项、`AppSettings.haptic`、底栏触觉调用全部清掉） |
| `flutter-43` | B 站接入：wbi 签名 / BV 与 b23 短链 / 720P + 360P 双档 |
| `flutter-44` | 修复 B 站短链解析：分享文本提取 URL 时吞掉中文/全角标点 |
| `flutter-45` | 修复 B 站下载 403：CDN 只认 PC 浏览器 UA，下载按平台切换 User-Agent |
| `flutter-46` | 下载队列（并发 1–3 / 失败自动重试 / 队列卡片），版本升至 `0.5.0` |
| `flutter-47` | 后台下载：前台服务（dataSync）+ 通知栏进度 + WakeLock |

## 基线（回退点）

| tag | commit | 对应构建 | 内容 |
|---|---|---|---|
| `v0.1.0-compose` | `3010f6d7` | — | 最初 Kotlin/Compose 版 |
| `v0.3.0-parse` | `2252f1ed` | `flutter-21` | 首个解析可用 |
| `v0.3.0` | `40118796` | `flutter-22` | 解析历史（记录页接真实数据） |
| `v0.3.0-visual` | `76f848f1` | `flutter-33` | 青绿图标 + 开屏动画 |
| `v0.4.0` | `aacfc1fb` | `flutter-41` | 剪贴板识别 / 去相册 / 设置项落地 / 单测 + CI Test |
| `v0.4.0-bilibili` | `166de112` | `flutter-45` | B 站接入：wbi 签名 / BV 与短链 / 720P+360P / PC UA 下载 |
| `v0.5.0` | `1ad8904c` | `flutter-47` | 下载队列 + 后台下载（前台服务 / 通知进度 / WakeLock）（**当前基线**） |

回退方式：用 `workflow_dispatch` 指定目标 commit 触发 `flutter.yml`，约 15–25 分钟重新出包。
Release 与构建物只增不删，清理必须由需求方明确指定（范围 + 数量）。

---

## 接下来可选目标（按性价比排序）

### 🟢 低成本 / 明显收益（建议先做）

| 目标 | 说明 | 成本 |
|---|---|---|
| **1. 应用图标 + 启动页** | ✅ 已完成（`flutter-31`）：自适应图标 + 深色 `launch_background` | — |
| **2. 清晰度选择** | ✅ 已完成（`flutter-31`）：按 `br` 排序分 原画/高清/标清 | — |
| **3. 解析预热** | ✅ 已完成（`flutter-31`）：首页 init 后 900ms 调 `warmUp()` 预加载 | — |
| **4. 历史增强** | 🟡 部分完成（`flutter-31`）：搜索 + 重新解析已做；按平台筛选、批量删除未做 | 2h |
| **5. 保存后引导** | ✅ 已完成（`flutter-41`）：保存成功 SnackBar 带「去相册看看」，用系统查看器打开刚写入的文件 | — |

### 🟡 中等成本 / 战略价值

| 目标 | 说明 | 成本 |
|---|---|---|
| **6. B 站接入** | ✅ 已完成（`flutter-45`）：wbi 签名 + BV/b23 短链 + 720P/360P 双档，纯 HTTP 1–2 秒出结果，下载需 PC UA | — |
| **7. 下载队列 + 后台下载** | ✅ 已完成（`flutter-47`）：并发 1–3 / 失败自动重试 / 队列卡片 / 前台服务 + 通知进度 + WakeLock；断点续传与队列持久化列入支线 | — |
| **8. 小红书接入** | 笔记链接 → 图文/视频，需要逆向 SSR 或接口签名 | 1–2 天 |
| **9. 快手接入** | 短链 → 页面解析，风控比抖音轻，但接口/字段要重新摸 | 1–2 天 |

### 🔴 高成本 / 按需再评估（非主线）

- **分享接收（ACTION_SEND）**：需要 intent 冷启动、多入口状态恢复、与粘贴解析去重，已从 Manifest 移除。
- **多账号 / 服务端同步**：需要后端，且涉及隐私合规。
- **a_bogus 纯 HTTP 客户端**：算法已有，但缺 `uifid`（浏览器指纹），除非接第三方打码/指纹服务。
- **iOS / 桌面端**：Flutter 可复用 UI，但下载落盘、分享接收要各写一套原生。

### 我的建议顺序

**1–3、5、6、7 已完成**（`flutter-31` / `flutter-41` / `flutter-45` / `flutter-47`），4 完成一半（搜索 + 重新解析）。主线下一步是 **8（批量解析）**，之后补 4 的剩余项（按平台筛选、批量删除）；队列持久化 / 断点续传 / 通知操作按钮等已列入「支线待优化」，按需再排。