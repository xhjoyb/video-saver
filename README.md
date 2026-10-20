# 视频嗅探 VideoSaver

多平台视频解析下载 App。首个平台：**抖音短视频无水印解析**（已跑通真实链路）。

- 包名：`com.xhjoyb.videosaver`
- 技术栈：Flutter 3.24.5 + Material 3，Kotlin 原生壳
- Android：minSdk 26 / targetSdk 34，仅 arm64 出包
- 构建：GitHub Actions 云端构建，Release 附 APK
- 当前基线：**run `flutter-22`**（解析 + 下载 + 相册 + 解析历史全部验证通过），tag `v0.3.0`

## 当前能力

| 能力 | 状态 |
|---|---|
| 抖音分享链接 / 短链 / 纯 ID 解析 | ✅ |
| 无水印视频直链提取（封面/标题/作者/时长） | ✅ |
| 下载（带 Referer，支持进度） | ✅ |
| 保存到相册 `Movies/VideoSaver`（MediaStore） | ✅ |
| 日间 / 夜间主题（跟随系统 / 手动） | ✅ |
| 自定义背景（相册图片 / ≤30s 视频静音循环） | ✅ |
| 解析历史（本地持久化 + 记录页） | ✅ |
| 分享接收（ACTION_SEND 已声明，Dart 侧未接） | ⏳ 待做 |
| 图集（images）解析下载 | ⏳ 返回数据已带，暂未落地下载 |
| 其它平台（快手 / 小红书 / B 站） | ⏳ 仅 UI 占位 |

## 抖音解析链路（核心）

```
分享文本 / 短链
  → 正则取 URL；v.douyin.com 跟随一次 302 拿到 aweme_id
  → 隐藏 WebView 加载 https://www.iesdouyin.com/share/video/{id}/
       （PC Chrome UA，302 到 www.douyin.com/video/{id}）
  → 页面 JS 自动完成：__ac_nonce/__ac_signature 挑战、生成 UIFID、加载 bdms.js
  → 页面内 fetch /aweme/v1/web/aweme/detail/?aweme_id=…
       （同源请求，bdms.js 自动加 a_bogus，cookie 自动携带）
  → 200 JSON（约 100KB）→ 取 aweme_detail.video.play_addr.url_list
  → 下载：带 Referer: https://www.douyin.com/ → 206 video/mp4
  → MediaStore 写入 Movies/VideoSaver
```

对应实现：

| 文件 | 职责 |
|---|---|
| `lib/parser/douyin_parser.dart` | URL/短链 → aweme_id；页面内 detail 请求的 JS |
| `lib/parser/parse_controller.dart` | 隐藏 WebView 生命周期、页面就绪防抖、JS 结果轮询、22s 超时 |
| `lib/parser/parse_result.dart` | 统一结果模型（封面/标题/作者/时长/直链/图集） |
| `lib/download/download_service.dart` | 流式下载 + 进度 + Referer |
| `lib/platform/media_store.dart` | MethodChannel → 原生 MediaStore 入库 |
| `android/.../MainActivity.kt` | `saveVideo`：插入 MediaStore(IS_PENDING) → 拷贝 → 清除 pending |

### 为什么是 WebView 而不是纯 HTTP

这一轮做了完整验证，结论如下（都实测过）：

| 尝试 | 结果 |
|---|---|
| 直接请求 `share/video/{id}` 拿 SSR `_ROUTER_DATA` | ❌ 只返回页面骨架，`videoInfoRes` 不存在（4 种 UA/请求头组合均如此） |
| `aweme/v1/web/aweme/detail/`（自带签名） | ❌ `403 Blocked by ArgusSecurityPlugin Uifid Not Found` |
| 自研 `a_bogus` | ✅ 算法复刻成功（`tools/abogus.py`），但接口仍因缺 `uifid` 403 |
| 抓包看抖音 App 明文 | ❌ 仅 TCP 层（Cronet + native 信任库，TLS 解不开） |
| Frida Hook（算法助手Pro） | ✅ 能拿到 `play_addr` 并验证无水印，但只能在抖音进程内用，不能用于独立 App |
| **WebView 渲染 + 页面内 fetch** | ✅ **可行**：挑战、UIFID、a_bogus 全部由页面 JS 代劳 |

关键结论：

1. **不需要自研 a_bogus**——页面里的 `bdms.js` 会给同源请求自动签名；
2. `uifid` 是 Argus 在浏览器环境生成的设备指纹，纯 HTTP 伪造不了，WebView 里天然就有；
3. 新版 `play_addr` **本身就是无水印地址**（URL 里没有 `watermark`，也没有 `playwm`），网上流传的 `playwm → play` 替换规则已过时；
4. 下载必须带 **`Referer: https://www.douyin.com/`**，否则 CDN 直接 403；
5. 移动端 UA 会让抖音甩 `snssdk://` 唤起 App，WebView 会整页 `ERR_UNKNOWN_URL_SCHEME`——必须用 PC UA，并拦截非 http(s) 导航。

## 构建与交付

push 到 `main` → GitHub Actions → 构建 → Release `flutter-<run_number>`。

```sh
# 查看最新 release tag（注意 gh api 默认顺序不是时间序）
gh api 'repos/xhjoyb/video-saver/releases?per_page=100' --jq 'sort_by(.created_at) | last | .tag_name'
```

安装（Android 13+ 需先落 `/data/local/tmp`）：

```sh
su -c 'cp /sdcard/Download/app.apk /data/local/tmp/v.apk && pm install -r /data/local/tmp/v.apk'
```

> 仓库已设为 **public**，可直接下载 Release 资产：
> `https://github.com/xhjoyb/video-saver/releases/download/flutter-22/app-release.apk`

签名 keystore 固化为仓库 Secret `ANDROID_KEYSTORE_B64`，密码在 `ANDROID_KS_PASS`，
workflow 内不出现明文；跨版本覆盖安装指纹稳定 `763a3827`。

## 调试工具（`tools/`）

| 脚本 | 用途 |
|---|---|
| `push_repo.py` | 本机 `github.com:443` 不通，用 Git Data API 推送（增量 blob + 重试 + prune） |
| `dl_asset.py` / `dl_artifact.py` | 多线程 Range 下载 Release 资产 / Actions artifact（单连接会被限速） |
| `fetch_keystore.py` / `ci_status.py` | keystore 取回、CI 状态查看 |
| `img_ascii.py` | 把截图压成字符画，无图形环境判断布局 |
| `abogus.py` / `sm3.py` | 自研 a_bogus 参考实现（当前主路径不用，留作纯 HTTP 备选） |
| `dy_*.py` / `mcp_capture.py` / `dy_hook.js` | 抓包 MCP 直连客户端、Frida Hook 探针、接口探测（逆向期工具） |
| `verify_url.py` | 校验直链可用性（206 / video/mp4 / ftyp / 是否带 watermark） |

App 内还保留一个开发者页面：**设置 → 开发者 → 解析探针**，会把 WebView 加载、错误码、cookie 名、detail 响应写到
`/sdcard/Android/data/com.xhjoyb.videosaver/files/probe_result.json`，用于线上排障。

## 已知问题

| 现象 | 原因 | 处理 |
|---|---|---|
| 解析偶尔慢（5–8s） | 隐藏 WebView 需加载完整页面并等 bdms.js 就绪 | 页面就绪后 1.5s 防抖再 fetch，后续可做预热 |
| `ERR_UNKNOWN_URL_SCHEME` | 移动 UA 触发抖音唤起 App | 已改 PC UA + 拦截非 http 导航 |
| 首版只支持视频，图集未落下载 | 图集字段已解析但下载逻辑只处理 mp4 | 后续补 images 下载 |
| CI 偶发 Release 发布失败 | runner 到 api.github.com 偶发超时 | Publish 步骤已加 5 次退避重试 |

## 路线图

1. 分享接收（抖音「分享 → 更多」直接带链接进 App）
2. 图集下载
3. 多平台（快手 / 小红书 / B 站，`VideoParser` 抽象已预留）
4. 解析结果页支持清晰度选择（`play_addr.url_list` 已含多档码率）
5. 解析预热（提前加载 WebView，降低首次解析等待）

## 备注

- 仓库内 `release/` 为本地构建产物目录（已 gitignore），不参与版本管理
- 当前工作区保留一份基线包 `release/app_v3.apk`（= flutter-20）