import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _haptic = true;
  bool _autoClipboard = false;
  bool _keepOriginal = true;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('设置', style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
              color: AppColors.text,
            )),
            const SizedBox(height: 6),
            const Text('下载位置、交互与关于信息', style: TextStyle(
              fontSize: 12.5,
              color: AppColors.textFaint,
            )),
            const SizedBox(height: 24),
            _groupTitle('下载'),
            GlassCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _SettingRow(
                    icon: Icons.folder_rounded,
                    title: '保存位置',
                    subtitle: 'Movies/VideoSaver',
                    onTap: () => _toast('目录选择开发中'),
                  ),
                  const _Divider(),
                  _SettingRow(
                    icon: Icons.high_quality_rounded,
                    title: '清晰度',
                    subtitle: '优先最高可用',
                    onTap: () => _toast('清晰度切换开发中'),
                  ),
                  const _Divider(),
                  _SettingRow(
                    icon: Icons.download_rounded,
                    title: '同时下载数',
                    subtitle: '3 个任务',
                    onTap: () => _toast('并发设置开发中'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            _groupTitle('体验'),
            GlassCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _SwitchRow(
                    icon: Icons.vibration_rounded,
                    title: '震动反馈',
                    subtitle: '按钮与解析完成时轻微震动',
                    value: _haptic,
                    onChanged: (v) => setState(() => _haptic = v),
                  ),
                  const _Divider(),
                  _SwitchRow(
                    icon: Icons.content_paste_go_rounded,
                    title: '自动识别剪贴板',
                    subtitle: '打开 App 时自动读取抖音链接',
                    value: _autoClipboard,
                    onChanged: (v) => setState(() => _autoClipboard = v),
                  ),
                  const _Divider(),
                  _SwitchRow(
                    icon: Icons.hd_rounded,
                    title: '保留原始画质',
                    subtitle: '关闭后按屏幕尺寸压缩',
                    value: _keepOriginal,
                    onChanged: (v) => setState(() => _keepOriginal = v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            _groupTitle('关于'),
            GlassCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _SettingRow(
                    icon: Icons.info_outline_rounded,
                    title: '版本',
                    subtitle: '0.2.0 (build 2)',
                  ),
                  const _Divider(),
                  _SettingRow(
                    icon: Icons.code_rounded,
                    title: '开源仓库',
                    subtitle: 'github.com/xhjoyb/video-saver',
                    onTap: () => _toast('当前为私有仓库'),
                  ),
                  const _Divider(),
                  _SettingRow(
                    icon: Icons.article_outlined,
                    title: '开源许可',
                    onTap: () => _toast('MIT License'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 26),
            Center(
              child: Text(
                '视频嗅探 · 仅供个人学习与备份使用',
                style: TextStyle(fontSize: 10.5, color: AppColors.textFaint.withOpacity(0.7)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _groupTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          letterSpacing: 1.6,
          fontWeight: FontWeight.w600,
          color: AppColors.textFaint.withOpacity(0.85),
        ),
      ),
    );
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            _iconBox(icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text,
                  )),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(subtitle!, style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textFaint,
                    )),
                  ],
                ],
              ),
            ),
            if (onTap != null)
              const Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.textFaint),
          ],
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          _iconBox(icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.text,
                )),
                const SizedBox(height: 3),
                Text(subtitle, style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textFaint,
                )),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: Colors.white,
            activeTrackColor: AppColors.accent,
            inactiveThumbColor: AppColors.textFaint,
            inactiveTrackColor: Colors.white.withOpacity(0.08),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 58),
      child: Container(height: 1, color: Colors.white.withOpacity(0.05)),
    );
  }
}

Widget _iconBox(IconData icon) {
  return Container(
    width: 30,
    height: 30,
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.05),
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: Colors.white.withOpacity(0.05)),
    ),
    child: Icon(icon, size: 16, color: AppColors.textDim),
  );
}