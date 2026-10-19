# 视频嗅探 VideoSaver

多平台视频解析下载 App。首个平台：**抖音短视频无水印**。

- 包名：`com.xhjoyb.videosaver`
- 技术栈：Kotlin + Jetpack Compose (Material3)，minSdk 26 / targetSdk 34
- 构建：GitHub Actions 云端出包（本机无 JDK / Android SDK）
- 产物：每次 push 到 `main` 自动构建，生成 Release（Tag `build-<run_number>`）附 APK

## 当前进度

| 阶段 | 状态 |
|---|---|
| 云端构建链路 + 固定签名 + Release 交付 | ✅ 已验证（build-4 装机冒烟通过） |
| 解析器抽象层 | 待开始 |
| 抖音无水印解析 | 待开始 |
| 下载与保存 | 待开始 |
| 分享接收 / 剪贴板识别 | 待开始 |
| 多平台扩展 | 待开始 |

## 构建产物与安装

每次 push 到 `main` → Actions 构建 → 生成 Release（Tag `build-<run_number>`）附 `app-release.apk`。

本机 `github.com:443` 不通，Release 资产单连接很慢，用多线程 Range 下载：

```sh
GH_TOKEN=$(gh auth token --user xhjoyb) python3 tools/dl_asset.py \
  --owner xhjoyb --repo video-saver --tag build-4 \
  --name app-release.apk --out release/videosaver.apk --threads 8
```

安装（Android 13+ 需先落到 /data/local/tmp）：

```sh
su -c 'cp /sdcard/Download/videosaver.apk /data/local/tmp/v.apk && pm install -r /data/local/tmp/v.apk'
su -c 'am start --user 0 -n com.xhjoyb.videosaver/com.xhjoyb.videosaver.MainActivity'
```

> 注意：本机 `am start` 不带 `--user 0` 会报 `Failed transaction`；带 `--user 0` 正常。

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
目前已把该 keystore 固化为仓库 Secret `ANDROID_KEYSTORE_B64`（alias `videosaver`），
CI 优先从 Secret 还原，其次用 Actions Cache（key `videosaver-keystore-v1`），
两者都没有时才现场生成。已实测跨构建签名一致：build-4 → build-6 覆盖安装成功，
证书指纹均为 `763a3827`。

## 已知问题与排查记录（踩过的坑）

| 现象 | 原因 | 处理 |
|---|---|---|
| `Keystore file '.../app/keystore/release.jks' not found` | module 内 `file()` 按 `app/` 解析 | 改用 `rootProject.file(ksPath)` |
| 推送成功但分支没变化 | 更新 ref 用了单数 `/git/ref/`，404 被静默容忍 | 改 `/git/refs/`，并校验返回的 sha |
| `pm install` 报 Android 13 SELinux 拒绝 | 直接装 `/sdcard` 路径 | 先 `cp` 到 `/data/local/tmp/` 再装 |
| `am start` 报 `Failed transaction` | 未指定 user | 使用 `am start --user 0 -n ...` |
| Release 没生成但步骤显示 success | runner 到 `api.github.com` 偶发 i/o timeout，且命令后面跟了 `\|\| true` | Publish 步骤加 5 次退避重试，并输出 warning |
| Release 资产下载很慢/中断 | `release-assets.githubusercontent.com` 单连接限速 | 用 `tools/dl_asset.py` 8 线程 Range 下载 |

构建耗时：首次约 5 分钟（含依赖下载），之后约 4 分钟（Gradle 缓存命中）。

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