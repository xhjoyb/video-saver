import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'history_item.dart';

/// 解析历史存储：SharedPreferences 存 JSON 字符串列表，最多保留 50 条
class HistoryStore extends ChangeNotifier {
  HistoryStore._();

  static final HistoryStore instance = HistoryStore._();

  static const String _key = 'history_items';
  static const int _limit = 50;

  final List<HistoryItem> _items = <HistoryItem>[];

  List<HistoryItem> get items => List<HistoryItem>.unmodifiable(_items);

  int get total => _items.length;
  int get downloadedCount => _items.where((e) => e.downloaded).length;
  int get platformCount => _items.map((e) => e.platform).toSet().length;

  /// 当前有记录的平台（按出现顺序去重）
  List<String> get platforms {
    final seen = <String>[];
    for (final item in _items) {
      if (!seen.contains(item.platform)) seen.add(item.platform);
    }
    return seen;
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_key) ?? const <String>[];
      _items
        ..clear()
        ..addAll(raw.map(HistoryItem.tryParse).whereType<HistoryItem>());
      notifyListeners();
    } catch (_) {
      // 读取失败保持空列表，不影响启动
    }
  }

  Future<void> add(HistoryItem item) async {
    _items.removeWhere((e) => e.awemeId == item.awemeId);
    _items.insert(0, item);
    if (_items.length > _limit) {
      _items.removeRange(_limit, _items.length);
    }
    notifyListeners();
    await _persist();
  }

  Future<void> markDownloaded(String awemeId, String filePath) async {
    final index = _items.indexWhere((e) => e.awemeId == awemeId);
    if (index < 0) return;
    _items[index] = _items[index].copyWith(filePath: filePath);
    notifyListeners();
    await _persist();
  }

  Future<void> remove(String awemeId) async {
    _items.removeWhere((e) => e.awemeId == awemeId);
    notifyListeners();
    await _persist();
  }

  /// 批量删除（历史页多选）
  Future<void> removeMany(Iterable<String> awemeIds) async {
    final ids = awemeIds.toSet();
    if (ids.isEmpty) return;
    _items.removeWhere((e) => ids.contains(e.awemeId));
    notifyListeners();
    await _persist();
  }

  Future<void> clear() async {
    _items.clear();
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _key,
        _items.map((e) => jsonEncode(e.toJson())).toList(),
      );
    } catch (_) {}
  }
}