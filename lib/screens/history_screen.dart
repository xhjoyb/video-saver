import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../theme/app_theme.dart';
import '../widgets/app_card.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SafeArea(
      bottom: false,
      child: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 120),
        children: [
          Text('解析记录', style: AppText.title(context)),
          const SizedBox(height: 6),
          Text('解析过的视频会保存在这里', style: AppText.label(context)),
          const SizedBox(height: 24),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
            child: Column(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: p.cardAlt,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Icons.history_rounded, size: 22, color: p.faint),
                ),
                const SizedBox(height: 14),
                Text(
                  '暂无记录',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: p.text,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '完成第一次解析后，这里会出现视频封面与下载入口',
                  textAlign: TextAlign.center,
                  style: AppText.label(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: _StatCard(label: '已解析', value: '0')),
              const SizedBox(width: 10),
              Expanded(child: _StatCard(label: '已下载', value: '0')),
              const SizedBox(width: 10),
              Expanded(child: _StatCard(label: '占用空间', value: '0 MB')),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      radius: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: context.palette.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: AppText.label(context)),
        ],
      ),
    );
  }
}