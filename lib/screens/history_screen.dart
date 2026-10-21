import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_events.dart';
import '../history/history_item.dart';
import '../history/history_store.dart';
import '../theme/app_palette.dart';
import '../theme/app_theme.dart';
import '../widgets/app_card.dart';

String _platformLabel(String platform) {
  switch (platform) {
    case 'bilibili':
      return 'B 站';
    case 'kuaishou':
      return '快手';
    case 'douyin':
      return '抖音';
    default:
      return platform;
  }
}

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String _platform = 'all';
  bool _managing = false;
  final Set<String> _selected = <String>{};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<HistoryItem> _visibleItems() {
    final all = HistoryStore.instance.items;
    final q = _query.trim().toLowerCase();
    return all.where((e) {
      if (_platform != 'all' && e.platform != _platform) return false;
      if (q.isEmpty) return true;
      return e.title.toLowerCase().contains(q) ||
          e.author.toLowerCase().contains(q) ||
          e.awemeId.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: HistoryStore.instance,
      builder: (context, _) {
        final store = HistoryStore.instance;
        final all = store.items;
        final items = _visibleItems();

        return SafeArea(
          bottom: false,
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 120),
            children: [
              _buildHeader(context, all.length, items.length),
              const SizedBox(height: 6),
              Text(
                all.isEmpty
                    ? '解析过的视频会保存在这里'
                    : '共 ${all.length} 条，点击条目可重新解析',
                style: AppText.label(context),
              ),
              if (all.isNotEmpty) ...[
                const SizedBox(height: 14),
                _buildSearch(context),
                const SizedBox(height: 10),
                _buildPlatformFilter(context, store.platforms),
              ],
              const SizedBox(height: 18),
              if (all.isEmpty)
                _buildEmpty(context)
              else if (items.isEmpty)
                _buildNoMatch(context)
              else
                ..._buildGrouped(context, items),
              if (_managing) _buildManageBar(context, items),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(child: _StatCard(label: '已解析', value: '${store.total}')),
                  const SizedBox(width: 10),
                  Expanded(child: _StatCard(label: '已下载', value: '${store.downloadedCount}')),
                  const SizedBox(width: 10),
                  Expanded(child: _StatCard(label: '平台数', value: '${store.platformCount}')),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, int total, int visible) {
    final p = context.palette;
    return Row(
      children: [
        Text('解析记录', style: AppText.title(context)),
        const Spacer(),
        if (total > 0)
          GestureDetector(
            onTap: () {
              setState(() {
                _managing = !_managing;
                _selected.clear();
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text(
                _managing ? '完成' : '管理',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _managing ? p.accent : p.dim,
                ),
              ),
            ),
          ),
        if (total > 0 && !_managing)
          GestureDetector(
            onTap: () => _confirmClear(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text('清空', style: AppText.label(context)),
            ),
          ),
        if (_managing && visible > 0)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Text('${_selected.length}/$visible', style: AppText.label(context)),
          ),
      ],
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
              onChanged: (v) => setState(() {
                _query = v;
                // 过滤条件变化后旧的勾选可能已不可见，一并清掉
                _selected.clear();
              }),
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

  Widget _buildPlatformFilter(BuildContext context, List<String> platforms) {
    final p = context.palette;
    final options = <MapEntry<String, String>>[
      const MapEntry('all', '全部'),
      for (final platform in platforms)
        MapEntry(platform, _platformLabel(platform)),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in options)
          GestureDetector(
            onTap: () => setState(() {
              _platform = option.key;
              // 切换平台后清空勾选，避免误删不可见条目
              _selected.clear();
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _platform == option.key
                    ? p.accent.withOpacity(0.16)
                    : p.cardAlt,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _platform == option.key ? p.accent : p.border,
                ),
              ),
              child: Text(
                option.value,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: _platform == option.key
                      ? FontWeight.w600
                      : FontWeight.w400,
                  color: _platform == option.key ? p.accent : p.dim,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// 按时间分组：今天 / 昨天 / 最近 7 天 / 更早
  List<Widget> _buildGrouped(BuildContext context, List<HistoryItem> items) {
    final widgets = <Widget>[];
    String? lastGroup;
    for (final item in items) {
      final group = _groupLabel(item.savedAt);
      if (group != lastGroup) {
        lastGroup = group;
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: Text(group, style: AppText.label(context)),
          ),
        );
      }
      widgets.add(
        _HistoryTile(
          item: item,
          managing: _managing,
          selected: _selected.contains(item.awemeId),
          onToggle: () => _toggle(item.awemeId),
        ),
      );
    }
    return widgets;
  }

  String _groupLabel(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(time.year, time.month, time.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return '今天';
    if (diff == 1) return '昨天';
    if (diff < 7) return '最近 7 天';
    return '更早';
  }

  void _toggle(String id) {
    setState(() {
      if (!_selected.add(id)) _selected.remove(id);
    });
  }

  void _toggleSelectAll(List<HistoryItem> items) {
    setState(() {
      if (_selected.length == items.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(items.map((e) => e.awemeId));
      }
    });
  }

  Widget _buildManageBar(BuildContext context, List<HistoryItem> items) {
    final p = context.palette;
    final allSelected = items.isNotEmpty && _selected.length == items.length;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _toggleSelectAll(items),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: p.cardAlt,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: p.border),
              ),
              child: Text(
                allSelected ? '取消全选' : '全选',
                style: TextStyle(fontSize: 12, color: p.dim),
              ),
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: _selected.isEmpty ? null : () => _confirmDeleteSelected(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _selected.isEmpty
                    ? p.cardAlt
                    : p.accent.withOpacity(0.16),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _selected.isEmpty ? p.border : p.accent,
                ),
              ),
              child: Text(
                '删除选中（${_selected.length}）',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _selected.isEmpty ? p.faint : p.accent,
                ),
              ),
            ),
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
      if (!mounted) return;
      setState(() {
        _managing = false;
        _selected.clear();
      });
    }
  }

  Future<void> _confirmDeleteSelected(BuildContext context) async {
    final count = _selected.length;
    if (count == 0) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除 $count 条记录？'),
        content: const Text('只删除记录，已保存到相册的视频不受影响。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    await HistoryStore.instance.removeMany(_selected);
    if (!mounted) return;
    setState(() {
      _selected.clear();
      _managing = false;
    });
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.item,
    required this.managing,
    required this.selected,
    required this.onToggle,
  });

  final HistoryItem item;
  final bool managing;
  final bool selected;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(10),
        radius: 16,
        onTap: managing ? onToggle : () => _showActions(context),
        child: Row(
          children: [
            if (managing)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 20,
                  color: selected ? p.accent : p.faint,
                ),
              ),
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
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                      color: p.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      _platformLabel(item.platform),
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
            if (!managing) ...[
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