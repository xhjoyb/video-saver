import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_events.dart';
import '../history/history_item.dart';
import '../history/history_store.dart';
import '../theme/app_palette.dart';
import '../theme/app_theme.dart';
import '../widgets/app_card.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: HistoryStore.instance,
      builder: (context, _) {
        final all = HistoryStore.instance.items;
        final q = _query.trim().toLowerCase();
        final items = q.isEmpty
            ? all
            : all
                .where((e) =>
                    e.title.toLowerCase().contains(q) ||
                    e.author.toLowerCase().contains(q) ||
                    e.awemeId.contains(q))
                .toList();

        return SafeArea(
          bottom: false,
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 120),
            children: [
              Row(
                children: [
                  Text('解析记录', style: AppText.title(context)),
                  const Spacer(),
                  if (all.isNotEmpty)
                    GestureDetector(
                      onTap: () => _confirmClear(context),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        child: Text('清空', style: AppText.label(context)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                all.isEmpty ? '解析过的视频会保存在这里' : '共 ${all.length} 条，点击条目可重新解析',
                style: AppText.label(context),
              ),
              if (all.isNotEmpty) ...[
                const SizedBox(height: 14),
                _buildSearch(context),
              ],
              const SizedBox(height: 18),
              if (all.isEmpty)
                _buildEmpty(context)
              else if (items.isEmpty)
                _buildNoMatch(context)
              else
                ...items.map((item) => _HistoryTile(item: item)),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(child: _StatCard(label: '已解析', value: '${HistoryStore.instance.total}')),
                  const SizedBox(width: 10),
                  Expanded(child: _StatCard(label: '已下载', value: '${HistoryStore.instance.downloadedCount}')),
                  const SizedBox(width: 10),
                  const Expanded(child: _StatCard(label: '平台数', value: '1')),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSearch(BuildContext context) {
    final p = context.palette;
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: p.cardAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.border),
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 16, color: p.faint),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              style: TextStyle(fontSize: 13, color: p.text),
              cursorColor: p.accent,
              decoration: InputDecoration(
                hintText: '搜索标题 / 作者 / ID',
                hintStyle: TextStyle(fontSize: 13, color: p.faint),
                border: InputBorder.none,
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          if (_query.isNotEmpty)
            GestureDetector(
              onTap: () {
                _searchController.clear();
                setState(() => _query = '');
              },
              child: Icon(Icons.close_rounded, size: 15, color: p.faint),
            ),
        ],
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final p = context.palette;
    return AppCard(
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
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.text),
          ),
          const SizedBox(height: 6),
          Text(
            '完成第一次解析后，这里会出现视频封面与下载状态',
            textAlign: TextAlign.center,
            style: AppText.label(context),
          ),
        ],
      ),
    );
  }

  Widget _buildNoMatch(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      child: Center(
        child: Text('没有找到匹配的记录', style: AppText.label(context)),
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空解析记录？'),
        content: const Text('只会删除记录，不会删除已保存到相册的视频。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('清空')),
        ],
      ),
    );
    if (ok == true) {
      await HistoryStore.instance.clear();
    }
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.item});

  final HistoryItem item;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(10),
        radius: 16,
        onTap: () => _showActions(context),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 64,
                height: 64,
                child: item.coverUrl.isEmpty
                    ? Container(color: p.cardAlt)
                    : Image.network(
                        item.coverUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: p.cardAlt,
                          child: Icon(Icons.movie_outlined, size: 22, color: p.faint),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.displayTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13.5, height: 1.35, fontWeight: FontWeight.w600, color: p.text),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (item.author.isNotEmpty) '@${item.author}',
                      if (item.durationText.isNotEmpty) item.durationText,
                      item.timeText,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.label(context),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: item.downloaded ? p.success.withOpacity(0.14) : p.cardAlt,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    item.downloaded ? '已下载' : '已解析',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                      color: item.downloaded ? p.success : p.faint,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => HistoryStore.instance.remove(item.awemeId),
                  child: Icon(Icons.delete_outline_rounded, size: 17, color: p.faint),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showActions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.palette.cardAlt,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.refresh_rounded),
              title: const Text('重新解析'),
              subtitle: const Text('回到解析页并自动开始（直链有时效，需要重新获取）'),
              onTap: () {
                Navigator.pop(ctx);
                AppEvents.tabIndex.value = 0;
                AppEvents.pendingParse.value = item.awemeId;
              },
            ),
            ListTile(
              leading: const Icon(Icons.link_rounded),
              title: const Text('复制视频直链'),
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: item.videoUrl));
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('直链已复制（有时效，尽快使用）')),
                  );
                }
              },
            ),
            if (item.downloaded)
              ListTile(
                leading: const Icon(Icons.folder_rounded),
                title: const Text('保存位置'),
                subtitle: Text(item.filePath ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.pop(ctx),
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('删除这条记录'),
              onTap: () {
                Navigator.pop(ctx);
                HistoryStore.instance.remove(item.awemeId);
              },
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