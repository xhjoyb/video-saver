import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../history/history_store.dart';
import '../platform/download_notification.dart';
import '../platform/media_store.dart';
import 'download_service.dart';

enum DownloadStatus { queued, running, success, failed, cancelled, interrupted }

/// 一个下载任务（当前只针对单文件视频；图集仍走同步保存）
class DownloadTask {
  DownloadTask({
    required this.id,
    required this.title,
    required this.fileName,
    required this.url,
    required this.platform,
    required this.referer,
    required this.userAgent,
    required this.awemeId,
  });

  final String id;
  final String title;
  final String fileName;
  final String url;
  final String platform;
  final String referer;
  final String? userAgent;
  final String awemeId;

  DownloadStatus status = DownloadStatus.queued;
  double progress = 0;
  String? error;
  String? savedUri;
  int attempts = 0;

  /// 结束态（可被「清除已完成」清理）
  bool get finished => status == DownloadStatus.success ||
      status == DownloadStatus.failed ||
      status == DownloadStatus.cancelled ||
      status == DownloadStatus.interrupted;

  String get statusText {
    switch (status) {
      case DownloadStatus.queued:
        return '等待中';
      case DownloadStatus.running:
        return '下载中 ${(progress * 100).toStringAsFixed(0)}%';
      case DownloadStatus.success:
        return '已保存到相册';
      case DownloadStatus.failed:
        return '失败：${error ?? '未知错误'}';
      case DownloadStatus.cancelled:
        return '已取消';
      case DownloadStatus.interrupted:
        return '已中断（可重试）';
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'fileName': fileName,
        'url': url,
        'platform': platform,
        'referer': referer,
        'userAgent': userAgent,
        'awemeId': awemeId,
        'status': status.name,
        'attempts': attempts,
      };

  static DownloadTask? fromJson(Map<String, dynamic> m) {
    final url = '${m['url'] ?? ''}';
    if (url.isEmpty) return null;
    final ua = (m['userAgent'] as String?)?.trim() ?? '';
    final task = DownloadTask(
      id: '${m['id'] ?? DateTime.now().microsecondsSinceEpoch}',
      title: '${m['title'] ?? ''}',
      fileName: '${m['fileName'] ?? 'video.mp4'}',
      url: url,
      platform: '${m['platform'] ?? 'douyin'}',
      referer: '${m['referer'] ?? 'https://www.douyin.com/'}',
      userAgent: ua.isEmpty ? null : ua,
      awemeId: '${m['awemeId'] ?? ''}',
    );
    final status = DownloadStatus.values.firstWhere(
      (e) => e.name == '${m['status']}',
      orElse: () => DownloadStatus.interrupted,
    );
    // 上次运行到一半的任务：进程已死，标记中断等待重试
    task.status =
        status == DownloadStatus.running ? DownloadStatus.interrupted : status;
    task.attempts = int.tryParse('${m['attempts'] ?? 0}') ?? 0;
    return task;
  }
}

/// 全局下载队列：并发上限内自动调度，失败自动重试一次。
///
/// 持久化：
/// - 任务表落盘到 SharedPreferences，冷启动 `restore()` 恢复；
/// - 上次处于「下载中」的任务会被标成 `interrupted`（可重试）；
/// - 排队中的任务恢复后会自动继续。
class DownloadQueue extends ChangeNotifier {
  DownloadQueue._();

  static final DownloadQueue instance = DownloadQueue._();

  static const String _prefsKey = 'download_tasks';
  static const int _maxAttempts = 2;
  static const int _maxTasks = 30;

  final List<DownloadTask> _tasks = [];

  int _concurrency = 2;
  bool _notificationOn = false;
  int _lastNotifyAt = 0;

  List<DownloadTask> get tasks => List.unmodifiable(_tasks);

  int get concurrency => _concurrency;

  set concurrency(int value) {
    final next = value.clamp(1, 3).toInt();
    if (next == _concurrency) return;
    _concurrency = next;
    notifyListeners();
    _pump();
  }

  int get runningCount =>
      _tasks.where((t) => t.status == DownloadStatus.running).length;

  int get queuedCount =>
      _tasks.where((t) => t.status == DownloadStatus.queued).length;

  bool get hasActive => runningCount > 0 || queuedCount > 0;

  /// 冷启动恢复：已结束的任务不再恢复，运行中的转为「已中断」
  Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_prefsKey) ?? const <String>[];
      for (final line in raw) {
        try {
          final map = jsonDecode(line) as Map<String, dynamic>;
          final task = DownloadTask.fromJson(map);
          if (task == null) continue;
          if (task.status == DownloadStatus.success ||
              task.status == DownloadStatus.cancelled) {
            continue;
          }
          _tasks.add(task);
        } catch (_) {
          // 单条损坏跳过
        }
      }
      _trim();
      notifyListeners();
      _pump();
      unawaited(_syncNotification(force: true));
    } catch (_) {
      // 读取失败保持空队列
    }
  }

  DownloadTask? enqueue({
    required String title,
    required String fileName,
    required String url,
    required String platform,
    required String referer,
    String? userAgent,
    required String awemeId,
  }) {
    // 同一视频已在队列（排队/下载中）时不重复入队
    for (final task in _tasks) {
      if (task.url == url &&
          (task.status == DownloadStatus.queued ||
              task.status == DownloadStatus.running)) {
        return null;
      }
    }
    final task = DownloadTask(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      title: title,
      fileName: fileName,
      url: url,
      platform: platform,
      referer: referer,
      userAgent: userAgent,
      awemeId: awemeId,
    );
    _tasks.add(task);
    _trim();
    notifyListeners();
    _persist();
    _pump();
    unawaited(_syncNotification(force: true));
    return task;
  }

  /// 重试失败/中断的任务
  void retry(String id) {
    for (final task in _tasks) {
      if (task.id != id) continue;
      if (task.status != DownloadStatus.failed &&
          task.status != DownloadStatus.interrupted) {
        return;
      }
      task
        ..status = DownloadStatus.queued
        ..attempts = 0
        ..error = null
        ..progress = 0;
      notifyListeners();
      _persist();
      _pump();
      return;
    }
  }

  void _pump() {
    for (final task in _tasks) {
      if (runningCount >= _concurrency) break;
      if (task.status == DownloadStatus.queued) {
        unawaited(_run(task));
      }
    }
  }

  Future<void> _run(DownloadTask task) async {
    if (task.status != DownloadStatus.queued) return;
    task.status = DownloadStatus.running;
    task.progress = 0;
    task.error = null;
    notifyListeners();
    _persist();
    unawaited(_syncNotification(force: true));

    File? file;
    try {
      file = await DownloadService.download(
        task.url,
        task.fileName,
        referer: task.referer,
        userAgent: task.userAgent,
        onProgress: (received, total) {
          if (total <= 0) return;
          final progress = received / total;
          if ((progress - task.progress).abs() >= 0.01) {
            task.progress = progress;
            notifyListeners();
            unawaited(_syncNotification(progress: (progress * 100).round()));
          }
        },
      );

      final uri = await MediaStore.saveVideo(file, task.fileName);
      if (uri == null) {
        throw StateError('写入相册失败');
      }
      task.savedUri = uri;
      task.progress = 1;
      task.status = DownloadStatus.success;
      await HistoryStore.instance.markDownloaded(
        task.awemeId,
        'Movies/VideoSaver/${task.fileName}',
      );
      notifyListeners();
    } catch (e) {
      task.attempts += 1;
      if (task.attempts < _maxAttempts) {
        task.status = DownloadStatus.queued;
        task.error = '第 ${task.attempts} 次失败，准备重试';
      } else {
        task.status = DownloadStatus.failed;
        task.error = '$e';
      }
      notifyListeners();
    } finally {
      if (file != null) {
        try {
          await file.delete();
        } catch (_) {}
      }
      _persist();
      _pump();
      unawaited(_syncNotification(force: true));
    }
  }

  /// 仅允许取消尚未开始的任务（正在传输的连接暂不支持中断）
  void cancel(String id) {
    for (final task in _tasks) {
      if (task.id != id) continue;
      if (task.status != DownloadStatus.queued) return;
      task.status = DownloadStatus.cancelled;
      notifyListeners();
      _persist();
      _pump();
      return;
    }
  }

  void removeFinished() {
    _tasks.removeWhere((t) => t.finished);
    notifyListeners();
    _persist();
  }

  /// 同步前台服务通知：有任务时启动，全部结束才停止；进度更新节流 800ms
  Future<void> _syncNotification({int progress = -1, bool force = false}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force && now - _lastNotifyAt < 800) return;
    _lastNotifyAt = now;

    final running = runningCount;
    final queued = queuedCount;
    if (running == 0 && queued == 0) {
      if (_notificationOn) {
        _notificationOn = false;
        await DownloadNotification.stop();
      }
      return;
    }
    if (!_notificationOn) {
      _notificationOn = true;
      await DownloadNotification.start(running: running, queued: queued);
    } else {
      await DownloadNotification.update(
        running: running,
        queued: queued,
        progress: progress,
      );
    }
  }

  /// 只保留最近 [_maxTasks] 条，优先清掉已结束的任务
  void _trim() {
    if (_tasks.length <= _maxTasks) return;
    for (final task in _tasks.where((t) => t.finished).toList()) {
      if (_tasks.length <= _maxTasks) break;
      _tasks.remove(task);
    }
    if (_tasks.length > _maxTasks) {
      _tasks.removeRange(0, _tasks.length - _maxTasks);
    }
  }

  Future<void> _persistChain = Future<void>.value();

  /// 写盘串行化：避免多次异步写乱序完成导致状态回退
  void _persist() {
    _persistChain = _persistChain
        .then((_) => _writePrefs())
        .catchError((Object _) {});
  }

  Future<void> _writePrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _prefsKey,
        _tasks.map((t) => jsonEncode(t.toJson())).toList(),
      );
    } catch (_) {}
  }
}