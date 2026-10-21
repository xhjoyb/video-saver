import 'package:flutter_test/flutter_test.dart';
import 'package:videosaver/download/download_queue.dart';

void main() {
  DownloadTask build() => DownloadTask(
        id: '1',
        title: '标题',
        fileName: 'f.mp4',
        url: 'https://x/v.mp4',
        platform: 'douyin',
        referer: 'https://www.douyin.com/',
        userAgent: null,
        awemeId: 'a1',
      );

  group('DownloadTask 序列化', () {
    test('往返保持关键字段', () {
      final back = DownloadTask.fromJson(build().toJson());
      expect(back, isNotNull);
      expect(back!.url, 'https://x/v.mp4');
      expect(back.fileName, 'f.mp4');
      expect(back.platform, 'douyin');
      expect(back.referer, 'https://www.douyin.com/');
      expect(back.userAgent, isNull);
      expect(back.awemeId, 'a1');
    });

    test('空 url 视为无效任务', () {
      expect(DownloadTask.fromJson({'url': ''}), isNull);
    });

    test('未知状态回落为 interrupted', () {
      final map = build().toJson()..['status'] = 'unknown_state';
      expect(DownloadTask.fromJson(map)!.status, DownloadStatus.interrupted);
    });
  });

  group('冷启动状态迁移', () {
    test('running 恢复为 interrupted', () {
      final task = build()..status = DownloadStatus.running;
      expect(
        DownloadTask.fromJson(task.toJson())!.status,
        DownloadStatus.interrupted,
      );
    });

    test('queued 保持 queued（恢复后自动继续）', () {
      final task = build()..status = DownloadStatus.queued;
      expect(DownloadTask.fromJson(task.toJson())!.status, DownloadStatus.queued);
    });

    test('success 保持 success', () {
      final task = build()..status = DownloadStatus.success;
      expect(DownloadTask.fromJson(task.toJson())!.status, DownloadStatus.success);
    });
  });

  group('finished 判定', () {
    test('结束态包含 interrupted', () {
      expect((build()..status = DownloadStatus.success).finished, isTrue);
      expect((build()..status = DownloadStatus.failed).finished, isTrue);
      expect((build()..status = DownloadStatus.cancelled).finished, isTrue);
      expect((build()..status = DownloadStatus.interrupted).finished, isTrue);
    });

    test('排队/下载中不算结束', () {
      expect((build()..status = DownloadStatus.queued).finished, isFalse);
      expect((build()..status = DownloadStatus.running).finished, isFalse);
    });
  });
}