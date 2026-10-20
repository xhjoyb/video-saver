import 'package:flutter_test/flutter_test.dart';
import 'package:videosaver/parser/douyin_parser.dart';

void main() {
  test('从分享口令文本里提取链接', () {
    const text = '7.43 xyz:/ 复制打开抖音，看看【作者的作品】'
        'https://v.douyin.com/iAbCdEf/ 复制此链接';
    expect(
      DouyinParser.extractUrl(text),
      'https://v.douyin.com/iAbCdEf/',
    );
  });

  test('没有链接时返回 null', () {
    expect(DouyinParser.extractUrl('今天天气不错'), isNull);
  });

  test('长链可直接取 aweme_id（不发起网络请求）', () async {
    final id = await DouyinParser.resolveAwemeId(
      'https://www.douyin.com/video/7400000000000000001',
    );
    expect(id, '7400000000000000001');
  });

  test('modal_id 形式也支持', () async {
    final id = await DouyinParser.resolveAwemeId(
      'https://www.douyin.com/user/self?modal_id=7400000000000000002',
    );
    expect(id, '7400000000000000002');
  });

  test('纯 ID 原样返回', () async {
    final id = await DouyinParser.resolveAwemeId('7400000000000000003');
    expect(id, '7400000000000000003');
  });
}