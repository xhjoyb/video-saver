import 'package:flutter_test/flutter_test.dart';
import 'package:videosaver/parser/xiaohongshu_parser.dart';

void main() {
  group('小红书链接识别', () {
    test('分享短链（xhslink.cn）', () {
      const url = 'https://xhslink.cn/o/5PgfPPkqGMP';
      expect(XiaohongshuParser.looksLike(url), isTrue);
      expect(XiaohongshuParser.extractShareUrl(url), url);
    });

    test('分享短链（xhslink.com）', () {
      const url = 'http://xhslink.com/a/AbCdEf';
      expect(XiaohongshuParser.looksLike(url), isTrue);
    });

    test('带 xsec_token 的笔记页', () {
      const url = 'https://www.xiaohongshu.com/discovery/item/'
          '6acaa831000000000202820b?xsec_token=ABC%3D&xsec_source=app_share';
      expect(XiaohongshuParser.looksLike(url), isTrue);
      expect(
        XiaohongshuParser.extractNoteId(url),
        '6acaa831000000000202820b',
      );
    });

    test('explore 形式', () {
      const url = 'https://www.xiaohongshu.com/explore/6acaa831000000000202820b';
      expect(
        XiaohongshuParser.extractNoteId(url),
        '6acaa831000000000202820b',
      );
    });

    test('分享文本里的短链能精确切出', () {
      const text = '世界不能没有小肥鱼 https://xhslink.cn/o/5PgfPPkqGMP 直达【小红书】';
      expect(
        XiaohongshuParser.extractShareUrl(text),
        'https://xhslink.cn/o/5PgfPPkqGMP',
      );
    });

    test('抖音链接不会误判', () {
      expect(
        XiaohongshuParser.looksLike('https://v.douyin.com/iAbCdEf/'),
        isFalse,
      );
    });

    test('快手链接不会误判', () {
      expect(
        XiaohongshuParser.looksLike('https://v.kuaishou.com/AbCdEf'),
        isFalse,
      );
    });
  });
}