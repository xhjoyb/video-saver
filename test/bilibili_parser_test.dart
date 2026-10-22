import 'package:flutter_test/flutter_test.dart';
import 'package:videosaver/parser/bilibili_parser.dart';

void main() {
  group('B 站链接识别', () {
    test('纯 BV 号', () {
      expect(BilibiliParser.looksLike('BV1pGnn67EbB'), isTrue);
      expect(BilibiliParser.extractBvid('BV1pGnn67EbB'), 'BV1pGnn67EbB');
    });

    test('完整链接', () {
      const url = 'https://www.bilibili.com/video/BV1pGnn67EbB?spm_id_from=333';
      expect(BilibiliParser.looksLike(url), isTrue);
      expect(BilibiliParser.extractBvid(url), 'BV1pGnn67EbB');
    });

    test('带 bvid 参数的链接', () {
      const url = 'https://www.bilibili.com/list/watchlater?bvid=BV1MHJB63Emv';
      expect(BilibiliParser.extractBvid(url), 'BV1MHJB63Emv');
    });

    test('b23 短链可识别，但不含 BV（需联网跳转）', () {
      const url = 'https://b23.tv/abc123';
      expect(BilibiliParser.looksLike(url), isTrue);
      expect(BilibiliParser.extractBvid(url), isNull);
    });

    test('抖音链接不会被判成 B 站', () {
      expect(
        BilibiliParser.looksLike('https://v.douyin.com/iAbCdEf/'),
        isFalse,
      );
    });

    test('分享文本里的 b23 短链能精确切出', () {
      const text = '【初音未来4.0-QQ动态主题（芙兰）"谢谢你，找到了我。"-哔哩哔哩】 '
          'https://b23.tv/pRhnnRk';
      expect(BilibiliParser.extractShareUrl(text), 'https://b23.tv/pRhnnRk');
    });

    test('短链后紧跟中文也不会被吞进 URL', () {
      expect(
        BilibiliParser.extractShareUrl('看这个 https://b23.tv/pRhnnRk复制此链接'),
        'https://b23.tv/pRhnnRk',
      );
    });

    test('长链尾部的全角标点会被裁掉', () {
      expect(
        BilibiliParser.extractShareUrl(
          '视频 https://www.bilibili.com/video/BV18Tby67ErD?p=1，好看',
        ),
        'https://www.bilibili.com/video/BV18Tby67ErD?p=1',
      );
    });
  });

  group('wbi 签名', () {
    test('mixinKey 取 32 位且结果稳定', () {
      const img = '7cd084941338484aae1ad9425b84077c';
      const sub = '4932caff0ff7c2f8f8b1f0f7a3c3a1c2';
      final first = BilibiliParser.mixinKey(img, sub);
      final second = BilibiliParser.mixinKey(img, sub);
      expect(first.length, 32);
      expect(first, second);
    });

    test('signQuery 按参数名排序并附带 32 位 w_rid', () {
      final query = BilibiliParser.signQuery(
        {
          'bvid': 'BV1pGnn67EbB',
          'cid': '42868346042',
          'qn': '64',
          'fnval': '1',
        },
        'ea1db124af3c7062474693fa704f4ff8',
        1700000000,
      );
      expect(
        query.startsWith(
          'bvid=BV1pGnn67EbB&cid=42868346042&fnval=1&qn=64&wts=1700000000',
        ),
        isTrue,
      );
      final rid = query.split('w_rid=').last;
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(rid), isTrue);
    });

    test('相同输入签名结果一致', () {
      String once() => BilibiliParser.signQuery(
            {'a': '1', 'b': '2'},
            'abcdefghijklmnopqrstuvwxyz012345',
            1700000000,
          );
      expect(once(), once());
    });

    test('特殊字符会被过滤后参与签名', () {
      final dirty = BilibiliParser.signQuery(
        {'q': "a!b'c(d)e*f"},
        'abcdefghijklmnopqrstuvwxyz012345',
        1700000000,
      );
      expect(dirty.contains('q=abcdef'), isTrue);
    });
  });

  group('DASH 档位挑选', () {
    List<dynamic> videos() => [
          {
            'id': 64,
            'baseUrl': 'https://cdn/720-hevc.m4s',
            'bandwidth': 606319,
            'codecs': 'hvc1.1.6.L120.90',
          },
          {
            'id': 80,
            'baseUrl': 'https://cdn/1080-avc.m4s',
            'bandwidth': 1937193,
            'codecs': 'avc1.640032',
          },
          {
            'id': 80,
            'baseUrl': 'https://cdn/1080-hevc.m4s',
            'bandwidth': 1135443,
            'codecs': 'hvc1.1.6.L150.90',
          },
          {
            'id': 64,
            'baseUrl': 'https://cdn/720-avc.m4s',
            'bandwidth': 1002428,
            'codecs': 'avc1.640028',
          },
          {
            'id': 16,
            'baseUrl': 'https://cdn/360-avc.m4s',
            'bandwidth': 403579,
            'codecs': 'avc1.64001E',
          },
        ];

    List<dynamic> audios() => [
          {'baseUrl': 'https://cdn/a-30216.m4s', 'bandwidth': 65723},
          {'baseUrl': 'https://cdn/a-30280.m4s', 'bandwidth': 102659},
        ];

    test('按清晰度降序排列，同档位优先 avc1 而不是更高码率的 hevc', () {
      final picks = BilibiliParser.pickDashQualities(videos(), audios());
      expect(picks.map((e) => e.id).toList(), [80, 64, 16]);
      expect(picks.first.videoUrl, 'https://cdn/1080-avc.m4s');
      expect(picks[1].videoUrl, 'https://cdn/720-avc.m4s');
    });

    test('每档都挂最高码率音轨（DASH 音轨与清晰度无关）', () {
      final picks = BilibiliParser.pickDashQualities(videos(), audios());
      expect(
        picks.every((e) => e.audioUrl == 'https://cdn/a-30280.m4s'),
        isTrue,
      );
    });

    test('没有音轨时 audioUrl 为空，调用方会回落到 durl 单文件', () {
      final picks = BilibiliParser.pickDashQualities(videos(), const []);
      expect(picks.first.audioUrl, isEmpty);
    });

    test('空输入返回空列表', () {
      expect(BilibiliParser.pickDashQualities(const [], const []), isEmpty);
    });

    test('缺 id / 缺 url / 非 Map 的脏数据都被跳过', () {
      final picks = BilibiliParser.pickDashQualities(
        [
          {'id': 0, 'baseUrl': 'https://cdn/zero.m4s'},
          {'id': 80},
          'not-a-map',
        ],
        const [],
      );
      expect(picks, isEmpty);
    });
  });
}