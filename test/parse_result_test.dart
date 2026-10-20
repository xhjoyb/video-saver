import 'package:flutter_test/flutter_test.dart';
import 'package:videosaver/parser/parse_result.dart';

void main() {
  ParseResult build({
    List<String> videoUrls = const [],
    List<String> imageUrls = const [],
    String title = '标题',
  }) {
    return ParseResult(
      platform: 'douyin',
      awemeId: '7400000000000000001',
      title: title,
      author: '作者',
      coverUrl: 'https://example.com/c.jpg',
      durationMs: 65000,
      videoUrls: videoUrls,
      imageUrls: imageUrls,
    );
  }

  group('qualities', () {
    test('按 br 降序、去重并标注清晰度', () {
      final r = build(videoUrls: [
        'https://x/v.mp4?br=900',
        'https://x/v.mp4?br=2500',
        'https://x/v.mp4?br=900',
      ]);
      final q = r.qualities;
      expect(q.length, 2);
      expect(q.first.br, 2500);
      expect(q.first.label, '原画');
      expect(q[1].label, '高清');
    });

    test('单档一律标原画', () {
      final r = build(videoUrls: ['https://x/v.mp4?br=1200']);
      expect(r.qualities.single.label, '原画');
    });

    test('无 br 参数时合并为 br=0 的一档', () {
      final r = build(videoUrls: ['https://x/a.mp4', 'https://x/b.mp4']);
      expect(r.qualities.length, 1);
      expect(r.qualities.single.br, 0);
    });
  });

  group('图集判定', () {
    test('图片优先于视频', () {
      final r = build(
        videoUrls: ['https://x/v.mp4'],
        imageUrls: ['https://x/i1.jpg'],
      );
      expect(r.isImages, isTrue);
      expect(r.isVideo, isFalse);
    });

    test('纯视频', () {
      final r = build(videoUrls: ['https://x/v.mp4']);
      expect(r.isImages, isFalse);
      expect(r.isVideo, isTrue);
    });
  });

  test('durationText 与 fileName 规范化', () {
    final r = build(videoUrls: ['https://x/v.mp4'], title: 'a/b c');
    expect(r.durationText, '1:05');
    expect(r.fileName, 'a_b_c_7400000000000000001.mp4');
  });

  test('空标题回退为无标题与平台前缀文件名', () {
    final r = build(title: '');
    expect(r.displayTitle, '无标题');
    expect(r.fileName, 'douyin_7400000000000000001.mp4');
  });
}