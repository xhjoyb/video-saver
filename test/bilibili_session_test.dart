import 'package:flutter_test/flutter_test.dart';
import 'package:videosaver/platform/bilibili_session.dart';

void main() {
  group('B 站登录态判定', () {
    test('含 SESSDATA 即视为已登录', () {
      expect(
        BilibiliSession.hasSessdata('buvid3=1; SESSDATA=abc123; bili_jct=x'),
        isTrue,
      );
    });

    test('没有 SESSDATA 视为未登录', () {
      expect(
        BilibiliSession.hasSessdata('buvid3=1; b_nut=2; buvid4=3'),
        isFalse,
      );
    });

    test('空值与 null 视为未登录', () {
      expect(BilibiliSession.hasSessdata(''), isFalse);
      expect(BilibiliSession.hasSessdata(null), isFalse);
    });
  });
}