# 视频嗅探 VideoSaver

多平台视频解析下载 App。首个平台：**抖音短视频无水印**。

- 包名：`com.xhjoyb.videosaver`
- 技术栈：Kotlin + Jetpack Compose (Material3)，minSdk 26 / targetSdk 34
- 构建：GitHub Actions 云端出包（本机无 JDK / Android SDK）
- 产物：每次 push 到 `main` 自动构建，生成 Release（Tag `build-<run_number>`）附 APK

## 当前进度

| 阶段 | 状态 |
|---|---|
| 云端构建链路 + 固定签名 + Release 交付 | 进行中（本次提交验证） |
| 解析器抽象层 | 待开始 |
| 抖音无水印解析 | 待开始 |
| 下载与保存 | 待开始 |
| 分享接收 / 剪贴板识别 | 待开始 |
| 多平台扩展 | 待开始 |

## 目录结构

```
app/src/main/java/com/xhjoyb/videosaver/    # 应用代码（后续拆 parser / download / ui）
app/src/main/res/                           # 资源
.github/workflows/android.yml               # 云端构建流水线
gradle/wrapper/                             # Gradle 8.7 wrapper
tools/push_repo.py                          # 通过 Git Data API 推送（本机 github.com:443 不通）
```

## 本地推送说明

本机 `git push` 到 github.com 会挂起（443 不通，`api.github.com` 正常），
所有提交统一走 Git Data API 脚本：

```sh
GH_TOKEN=$(gh auth token --user xhjoyb) python3 tools/push_repo.py \
  --owner xhjoyb --repo video-saver --branch main --dir . --message "feat: xxx"
```

## 签名

CI 首次运行用 `keytool` 生成 PKCS12 keystore（`keystore/release.jks`），
通过 Actions Cache（key `videosaver-keystore-v1`）复用，并上传 `keystore-backup` artifact。
待首次构建完成后，会将该 keystore 固化为仓库 Secret，避免 cache 失效导致签名变化。

## 解析链路（设计）

```
分享文本 → 提取 v.douyin.com 短链
        → 跟随 302 得到 aweme_id
        → 请求 iesdouyin share 页拿 _ROUTER_DATA
        → 解析 video.play_addr.uri_list / images / music
        → playwm → play 得无水印直链
        → OkHttp 下载 → MediaStore 写 Movies/
```

三级降级：直接 HTTP → 带 Cookie 重试 → WebView 预热 Cookie。具体以实测结果为准。
