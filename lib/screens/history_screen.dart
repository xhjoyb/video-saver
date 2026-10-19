import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

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
            const Text('解析记录', style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
              color: AppColors.text,
            )),
            const SizedBox(height: 6),
            const Text('解析过的视频会保存在这里，方便重新下载', style: TextStyle(
              fontSize: 12.5,
              color: AppColors.textFaint,
            )),
            const SizedBox(height: 24),
            GlassCard(
              padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 24),
              child: Column(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: AppGradients.ice,
                      border: Border.all(color: Colors.white.withOpacity(0.06)),
                    ),
                    child: const Icon(Icons.history_rounded, size: 30, color: AppColors.textDim),
                  ),
                  const SizedBox(height: 18),
                  const Text('暂无记录', style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  )),
                  const SizedBox(height: 8),
                  const Text('完成第一次解析后，这里会出现视频封面、标题与下载按钮',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, height: 1.6, color: AppColors.textFaint),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                _StatCard(label: '已解析', value: '0'),
                const SizedBox(width: 12),
                _StatCard(label: '已下载', value: '0'),
                const SizedBox(width: 12),
                _StatCard(label: '节省空间', value: '0 MB'),
              ],
            ),
          ],
        ),
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
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            )),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 10.5, color: AppColors.textFaint)),
          ],
        ),
      ),
    );
  }
}