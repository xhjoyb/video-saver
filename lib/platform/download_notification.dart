import 'package:flutter/services.dart';

/// 下载前台服务桥接：让进程在后台存活，并在通知栏显示队列进度。
///
/// 真正的下载仍在 Dart 侧执行；原生侧只负责 startForeground + 通知 + WakeLock。
class DownloadNotification {
  DownloadNotification._();

  static const MethodChannel _channel = MethodChannel('videosaver/media');

  static Future<void> start({required int running, required int queued}) async {
    try {
      await _channel.invokeMethod('startDownloadService', {
        'running': running,
        'queued': queued,
      });
    } catch (_) {
      // 原生不可用时静默降级为前台下载
    }
  }

  static Future<void> update({
    required int running,
    required int queued,
    required int progress,
  }) async {
    try {
      await _channel.invokeMethod('updateDownloadService', {
        'running': running,
        'queued': queued,
        'progress': progress,
      });
    } catch (_) {}
  }

  static Future<void> stop() async {
    try {
      await _channel.invokeMethod('stopDownloadService');
    } catch (_) {}
  }
}