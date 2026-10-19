import 'package:flutter/material.dart';

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

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 120),
        children: [
          const Text('设置', style: AppText.title),
          const SizedBox(height: 6),
          const Text('下载位置与交互偏好', style: AppText.label),
          const SizedBox(height: 24),
          _groupTitle('下载'),
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
                const _Divider(),
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
          _groupTitle('体验'),
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
                const _Divider(),
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
          _groupTitle('关于'),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                const _RowTile(
                  icon: Icons.info_outline_rounded,
                  title: '版本',
                  subtitle: '0.2.0 (build 2)',
                ),
                const _Divider(),
                _RowTile(
                  icon: Icons.code_rounded,
                  title: '开源仓库',
                  subtitle: 'github.com/xhjoyb/video-saver',
                  onTap: () => _toast('当前为私有仓库'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          const Center(
            child: Text('视频嗅探 · 个人学习与备份使用', style: AppText.label),
          ),
        ],
      ),
    );
  }

  Widget _groupTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 10),
      child: Text(text, style: AppText.label),
    );
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }
}

class _RowTile extends StatelessWidget {
  const _RowTile({
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            _IconBox(icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppText.body),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: AppText.label),
                  ],
                ],
              ),
            ),
            if (onTap != null)
              const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.faint),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(
        children: [
          _IconBox(icon),
          const SizedBox(width: 12),
          Expanded(child: Text(title, style: AppText.body)),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: Colors.white,
            activeTrackColor: AppColors.accent,
            inactiveThumbColor: AppColors.faint,
            inactiveTrackColor: AppColors.cardAlt,
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
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: AppColors.cardAlt,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 15, color: AppColors.dim),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(left: 54),
      child: Divider(height: 1, thickness: 1, color: AppColors.border),
    );
  }
}