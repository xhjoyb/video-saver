# 视频嗅探 VideoSaver

多平台视频解析下载 App。首个平台：**抖音短视频无水印**。

- 包名：`com.xhjoyb.videosaver`
- 技术栈：**Flutter 3.24.5** + Material 3（深色科技感）
- Android：minSdk 26 / targetSdk 34，Kotlin 原生壳 `MainActivity`（FlutterActivity）
- 构建：GitHub Actions 云端出包（本机无 JDK / Flutter SDK）
- 产物：push 到 `main` 自动构建，生成 Release（Tag `flutter-<run_number>`）附 arm64 APK

## 当前进度

| 阶段 | 状态 |
|---|---|
| 云端构建链路 + 固定签名 + Release 交付 | ✅ 已验证（build-6 与 Flutter 版均覆盖安装成功） |
| Flutter 迁移 + 深色主题四屏 UI | ✅ 已完成（解析 / 记录 / 设置三页 + 玻璃卡片组件） |
| 解析器抽象层（Dart） | 待开始 |
| 抖音无水印解析 | 待开始 |
| 下载与相册落盘 | 待开始 |
| 分享接收 / 剪贴板识别 | 剪贴板已接；ACTION_SEND 已在 Manifest 声明，待 Dart 侧处理 |

## 目录结构

```
lib/
  main.dart                 # App 入口 + 底部导航壳（IndexedStack）
  theme/app_theme.dart      # 深色配色 / 渐变 / 文字层级
  screens/
    parse_screen.dart       # 解析页：光晕背景 + 玻璃输入卡 + 平台入口 + 空态
    history_screen.dart     # 记录页：空态 + 统计卡
    settings_screen.dart    # 设置页：下载 / 体验 / 关于 三组卡片
  widgets/
    glass_card.dart         # 玻璃拟态卡片（BackdropFilter）
    gradient_button.dart    # 主渐变按钮（按压缩放 / loading）
    platform_chip.dart      # 平台入口（激活 / 敬请期待）
android/                    # flutter create 官方骨架 + 签名与 Manifest 定制
.github/workflows/
  flutter.yml               # 主构建流水线（签名 / APK / Release）
  flutter-bootstrap.yml     # 手动触发：生成官方 Android 骨架并回传 artifact
tools/                      # 本机辅助脚本（推送 / 下载 / CI 状态 / keystore）
keystore/                   # 本地签名密钥（已 gitignore，CI 用 Secret）
release/                    # 本地下载的安装包与截图
```

## 设计说明（方案 A · 深色科技感 · v4）

- **双主题**：`AppPalette` 以 `ThemeExtension` 挂到 `ThemeData`，日间/夜间两套色值；页面内禁止硬编码颜色，统一 `context.palette`
- **主题模式**：跟随系统 / 日间 / 夜间（设置页可切换，持久化到 SharedPreferences）
- **自定义背景**：默认渐变底 → 相册图片 / 30 秒内视频（静音循环）→ 可读性遮罩 → 页面内容
- **卡片半透明**（夜间 `#12121A` 79% / 日间 `#FFFFFF` 90%），让背景能透出但文字仍清晰
- **字号收敛到 6 级**：hero 27 / title 20 / section 15 / body 13.5 / sub 12.5 / label 11.5
- **间距固定 20 / 24 / 28**，圆角统一 18（控件 12）
- 主色珊瑚红只出现在 Logo、主按钮、激活平台、选中 Tab 四处
- 首页结构：品牌行 → 双行大标题 → 说明 → 输入卡（粘贴 + 开始解析）→ 平台四宫格 → 最近解析空态
- 底部导航固定高度，切换不产生布局跳动

## 背景与主题实现

| 能力 | 实现 |
|---|---|
| 主题切换 | `AppSettings.themeMode`（system/light/dark）→ `MaterialApp.themeMode` |
| 图片背景 | `image_picker` 选图（≤2400px）→ 复制到 `support/backgrounds/` → `Image.file(cover)` |
| 视频背景 | `image_picker.pickVideo`（≤30s）→ `video_player` 静音循环 + `FittedBox(cover)` |
| 持久化 | `shared_preferences`（theme_mode / bg_type / bg_path），启动时校验文件存在 |
| 可读性 | 背景上有 palette.scrim 遮罩（夜间黑 55%、日间白 30%），卡片自身半透明 |
| 清除 | 设置页「恢复默认背景」删除文件并重置状态 |

## 构建产物与安装

push 到 `main` → Flutter CI → Release `flutter-<run_number>` 附 `app-release.apk`（仅 arm64，约 13–16MB）。

本机 `github.com:443` 不通、Release 资产单连接很慢，用多线程 Range 下载：

```sh
GH_TOKEN=$(gh auth token --user xhjoyb) python3 tools/dl_asset.py \
  --owner xhjoyb --repo video-saver --tag flutter-2 \
  --name app-release.apk --out release/videosaver.apk --threads 16
```

安装与启动（Android 13+ 需先落 `/data/local/tmp`）：

```sh
su -c 'cp /sdcard/Download/videosaver.apk /data/local/tmp/v.apk && pm install -r /data/local/tmp/v.apk'
su -c 'am start --user 0 -n com.xhjoyb.videosaver/com.xhjoyb.videosaver.MainActivity'
```

> `am start` 不带 `--user 0` 会报 `Failed transaction`；带 `--user 0` 正常。

## 签名

keystore 已固化为仓库 Secret `ANDROID_KEYSTORE_B64`（PKCS12，alias `videosaver`），
CI 优先从 Secret 还原，其次用 Actions Cache（key `videosaver-keystore-v1`），
都没有时才现场生成。实测跨版本签名一致：Kotlin 版 build-4 → build-6 → Flutter 版
覆盖安装均成功，证书指纹 `763a3827`。

## 已知问题与排查记录

| 现象 | 原因 | 处理 |
|---|---|---|
| `Keystore file '.../app/keystore/release.jks' not found`（历史） | module 内 `file()` 按 `app/` 解析 | 改为绝对路径 `KS_FILE` |
| 推送成功但分支没变化 | 更新 ref 用了单数 `/git/ref/`，404 被静默容忍 | 改 `/git/refs/` 并校验返回 sha |
| `pm install` 报 Android 13 SELinux 拒绝 | 直接装 `/sdcard` 路径 | 先 `cp` 到 `/data/local/tmp/` |
| `am start` 报 `Failed transaction` | 未指定 user | `am start --user 0 -n ...` |
| Release 没生成但步骤 success | runner 到 `api.github.com` 偶发 timeout，且跟了 `\|\| true` | Publish 加 5 次退避重试 + warning |
| Release 下载慢/中断 | `release-assets.githubusercontent.com` 单连接限速 | `tools/dl_asset.py` 多线程 Range |
| 两个 workflow 的 `run_number` 各自独立，tag 会撞车 | GitHub 语义 | Flutter 用 `flutter-<n>`、旧 Kotlin 用 `build-<n>` |
| Flutter universal APK 45MB | 含 3 个 ABI 的引擎 | 改 `--target-platform android-arm64` |
| 偶发 `Concurrent modification ... handleClearSelection` | Flutter 文本选择框架的已知竞态，非本工程逻辑 | 不崩溃、可忽略，等引擎版本升级 |

构建耗时：Flutter 首次约 8 分钟（含 SDK + 引擎下载），缓存命中后约 4–5 分钟。

## 平台扩展路线

`lib` 侧按 `VideoParser` 抽象预留：`matches(url)` / `parse(url) → ParseResult`，
新增平台只加实现类，UI 与下载层不动。首批计划：抖音 → 快手 → 小红书 → B 站。