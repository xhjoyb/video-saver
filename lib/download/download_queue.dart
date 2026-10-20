import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../history/history_store.dart';
import '../platform/download_notification.dart';
import '../platform/media_store.dart';
import 'download_service.dart';

enum DownloadStatus { queued, running, success, failed, cancelled }

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

  bool get finished =>
      status == DownloadStatus.success ||
      status == DownloadStatus.failed ||
      status == DownloadStatus.cancelled;

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
    }
  }
}

/// 全局下载队列：并发上限内自动调度，失败自动重试一次。
///
/// 说明：真正的后台常驻（前台服务 + 通知栏进度）在下一批做；
/// 当前实现保证 App 在前台时多任务排队、并发可控、失败可诊断。
class DownloadQueue extends ChangeNotifier {
  DownloadQueue._();

  static final DownloadQueue instance = DownloadQueue._();

  static const int _maxAttempts = 2;

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

  DownloadTask enqueue({
    required String title,
    required String fileName,
    required String url,
    required String platform,
    required String referer,
    String? userAgent,
    required String awemeId,
  }) {
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
    notifyListeners();
    _pump();
    unawaited(_syncNotification(force: true));
    return task;
  }

  void _pump() {
    for (final task in _tasks) {
      if (runningCount >= _concurrency) break;
      if (task.status == DownloadStatus.queued) {
        unawaited(_run(task));
      }
    }
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

  Future<void> _run(DownloadTask task) async {
    if (task.status != DownloadStatus.queued) return;
    task.status = DownloadStatus.running;
    task.progress = 0;
    task.error = null;
    notifyListeners();
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
      _pump();
      return;
    }
  }

  void removeFinished() {
    _tasks.removeWhere((t) => t.finished);
    notifyListeners();
  }
}