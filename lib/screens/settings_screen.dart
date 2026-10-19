import 'package:flutter/material.dart';

import '../dev/parse_probe_screen.dart';
import '../state/app_settings.dart';
import '../theme/app_palette.dart';
import '../theme/app_theme.dart';
import '../widgets/app_card.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _haptic = true;
  bool _autoClipboard = false;

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _pickImage() async {
    final settings = AppSettingsScope.of(context);
    final ok = await settings.pickBackgroundImage();
    if (!mounted) return;
    if (ok) {
      _toast('已应用图片背景');
    } else if (settings.lastError != null) {
      _toast('选择失败：${settings.lastError}');
    }
  }

  Future<void> _pickVideo() async {
    final settings = AppSettingsScope.of(context);
    final ok = await settings.pickBackgroundVideo();
    if (!mounted) return;
    if (ok) {
      _toast('已应用动态背景');
    } else if (settings.lastError != null) {
      _toast('选择失败：${settings.lastError}');
    }
  }

  Future<void> _clearBackground() async {
    await AppSettingsScope.of(context).clearBackground();
    if (!mounted) return;
    _toast('已恢复默认背景');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final settings = AppSettingsScope.of(context);
    return SafeArea(
      bottom: false,
      child: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 120),
        children: [
          Text('设置', style: AppText.title(context)),
          const SizedBox(height: 6),
          Text('外观、下载位置与交互偏好', style: AppText.label(context)),
          const SizedBox(height: 24),
          _groupTitle(context, '外观'),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const _IconBox(Icons.brightness_6_rounded),
                          const SizedBox(width: 12),
                          Text('主题', style: AppText.body(context)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _ThemeOption(
                            label: '跟随系统',
                            selected: settings.themeMode == ThemeMode.system,
                            onTap: () => settings.setThemeMode(ThemeMode.system),
                          ),
                          const SizedBox(width: 8),
                          _ThemeOption(
                            label: '日间',
                            selected: settings.themeMode == ThemeMode.light,
                            onTap: () => settings.setThemeMode(ThemeMode.light),
                          ),
                          const SizedBox(width: 8),
                          _ThemeOption(
                            label: '夜间',
                            selected: settings.themeMode == ThemeMode.dark,
                            onTap: () => settings.setThemeMode(ThemeMode.dark),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                _Divider(color: p.border),
                _RowTile(
                  icon: Icons.image_outlined,
                  title: '图片背景',
                  subtitle: settings.bgType == BackgroundType.image
                      ? '已启用（静态图片）'
                      : '从相册选择一张图片',
                  onTap: settings.busy ? null : _pickImage,
                  trailing: settings.busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                ),
                _Divider(color: p.border),
                _RowTile(
                  icon: Icons.videocam_outlined,
                  title: '动态背景',
                  subtitle: settings.bgType == BackgroundType.video
                      ? '已启用（静音循环播放）'
                      : '从相册选择 30 秒以内的视频',
                  onTap: settings.busy ? null : _pickVideo,
                ),
                if (settings.bgType != BackgroundType.none) ...[
                  _Divider(color: p.border),
                  _RowTile(
                    icon: Icons.restart_alt_rounded,
                    title: '恢复默认背景',
                    subtitle: '移除当前图片或视频',
                    onTap: _clearBackground,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          _groupTitle(context, '下载'),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _RowTile(
                  icon: Icons.folder_rounded,
                  title: '保存位置',
                  subtitle: 'Movies/VideoSaver',
                  onTap: () => _toast('目录选择开发中'),
                ),
                _Divider(color: p.border),
                _RowTile(
                  icon: Icons.download_rounded,
                  title: '同时下载数',
                  subtitle: '3 个任务',
                  onTap: () => _toast('并发设置开发中'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _groupTitle(context, '体验'),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _SwitchTile(
                  icon: Icons.vibration_rounded,
                  title: '震动反馈',
                  value: _haptic,
                  onChanged: (v) => setState(() => _haptic = v),
                ),
                _Divider(color: p.border),
                _SwitchTile(
                  icon: Icons.content_paste_go_rounded,
                  title: '自动识别剪贴板',
                  value: _autoClipboard,
                  onChanged: (v) => setState(() => _autoClipboard = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _groupTitle(context, '关于'),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _RowTile(
                  icon: Icons.info_outline_rounded,
                  title: '版本',
                  subtitle: '0.2.0 (build 2)',
                ),
                _Divider(color: p.border),
                _RowTile(
                  icon: Icons.code_rounded,
                  title: '开源仓库',
                  subtitle: 'github.com/xhjoyb/video-saver',
                  onTap: () => _toast('当前为私有仓库'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _groupTitle(context, '开发者'),
          AppCard(
            padding: EdgeInsets.zero,
            child: _RowTile(
              icon: Icons.bug_report_outlined,
              title: '解析探针',
              subtitle: '用 WebView 打开分享页，抓取视频地址与接口线索',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ParseProbeScreen()),
                );
              },
            ),
          ),
          const SizedBox(height: 28),
          Center(
            child: Text('视频嗅探 · 个人学习与备份使用', style: AppText.label(context)),
          ),
        ],
      ),
    );
  }

  Widget _groupTitle(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 10),
      child: Text(text, style: AppText.label(context)),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? p.accent : p.cardAlt,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? p.accent : p.border),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? Colors.white : p.dim,
            ),
          ),
        ),
      ),
    );
  }
}

class _RowTile extends StatelessWidget {
  const _RowTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            _IconBox(icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppText.body(context)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: AppText.label(context)),
                  ],
                ],
              ),
            ),
            if (trailing != null)
              trailing!
            else if (onTap != null)
              Icon(Icons.chevron_right_rounded, size: 18, color: p.faint),
          ],
        ),
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(
        children: [
          _IconBox(icon),
          const SizedBox(width: 12),
          Expanded(child: Text(title, style: AppText.body(context))),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: Colors.white,
            activeTrackColor: p.accent,
            inactiveThumbColor: p.faint,
            inactiveTrackColor: p.cardAlt,
          ),
        ],
      ),
    );
  }
}

class _IconBox extends StatelessWidget {
  const _IconBox(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: p.cardAlt,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 15, color: p.dim),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 54),
      child: Divider(height: 1, thickness: 1, color: color),
    );
  }
}