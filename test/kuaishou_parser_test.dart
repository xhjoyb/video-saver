import 'package:flutter_test/flutter_test.dart';
import 'package:videosaver/parser/kuaishou_parser.dart';

void main() {
  group('快手链接识别', () {
    test('分享短链', () {
      const url = 'https://v.kuaishou.com/AbCdEf';
      expect(KuaishouParser.looksLike(url), isTrue);
      expect(KuaishouParser.extractPhotoId(url), isNull);
    });

    test('网页短链', () {
      const url = 'https://www.kuaishou.com/short-video/3xzjn7ps8i9kgm2';
      expect(KuaishouParser.looksLike(url), isTrue);
      expect(KuaishouParser.extractPhotoId(url), '3xzjn7ps8i9kgm2');
    });

    test('移动分享页链接', () {
      const url = 'https://v.m.chenzhongtech.com/fw/photo/3x9e6zt3sjwd7p9?fid=1';
      expect(KuaishouParser.looksLike(url), isTrue);
      expect(KuaishouParser.extractPhotoId(url), '3x9e6zt3sjwd7p9');
    });

    test('纯 photoId', () {
      expect(KuaishouParser.looksLike('3xzjn7ps8i9kgm2'), isTrue);
      expect(KuaishouParser.extractPhotoId('3xzjn7ps8i9kgm2'), '3xzjn7ps8i9kgm2');
    });

    test('抖音纯数字 ID 不会被当作快手', () {
      expect(KuaishouParser.looksLike('7400000000000000001'), isFalse);
    });

    test('B 站 BV 号不会被当作快手', () {
      expect(KuaishouParser.looksLike('BV1pGnn67EbB'), isFalse);
    });

    test('普通文本不会误判', () {
      expect(KuaishouParser.looksLike('今天天气不错'), isFalse);
    });
  });
}