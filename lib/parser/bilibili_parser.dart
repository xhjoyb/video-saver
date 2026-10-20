import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

import 'douyin_parser.dart';
import 'parse_result.dart';

/// B 站解析：Web wbi 签名路线（不走 App 的 gRPC）
///
/// 已验证：
/// - `x/web-interface/view` 免签名
/// - `x/player/wbi/playurl` 需 wbi 签名，`fnval=1` 返回 durl 单文件 mp4（含音轨）
/// - 未登录最高 720P（qn=80/112 会被服务端降级为 64）
/// - 直链下载必须带 `Referer: https://www.bilibili.com/`
class BilibiliParser {
  BilibiliParser._();

  static const String userAgent = DouyinParser.userAgent;
  static const String referer = 'https://www.bilibili.com/';

  static final RegExp _bvidRe = RegExp(r'BV[0-9A-Za-z]{10}');
  static final RegExp _urlRe = RegExp(r'https?://[^\s]+');

  /// wbi 混淆表（公开常量，用于打乱 img_key + sub_key）
  static const List<int> _mixinTab = [
    46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35,
    27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13,
    37, 48, 7, 16, 24, 55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4,
    22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36, 20, 34, 44, 52,
  ];

  static bool looksLike(String text) {
    if (_bvidRe.hasMatch(text)) return true;
    final lower = text.toLowerCase();
    return lower.contains('bilibili.com') || lower.contains('b23.tv');
  }

  static String? extractBvid(String text) {
    final match = _bvidRe.firstMatch(text);
    if (match != null) return match.group(0);
    final param = RegExp(r'[?&]bvid=(BV[0-9A-Za-z]{10})').firstMatch(text);
    return param?.group(1);
  }

  /// 支持纯 BV 号 / 完整链接 / b23.tv 短链（跟随最多 3 跳）
  static Future<String?> resolveBvid(String input) async {
    final direct = extractBvid(input);
    if (direct != null) return direct;

    final url = _urlRe.firstMatch(input.trim())?.group(0);
    if (url == null) return null;
    final location = await _followRedirects(url);
    if (location == null) return null;
    return extractBvid(location);
  }

  static Future<String?> _followRedirects(String url) async {
    var current = url;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      for (var hop = 0; hop < 3; hop++) {
        final request = await client.getUrl(Uri.parse(current));
        request.followRedirects = false;
        request.headers.set(HttpHeaders.userAgentHeader, userAgent);
        final response = await request.close();
        await response.drain<void>();
        if (response.statusCode >= 300 && response.statusCode < 400) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          if (location == null) return null;
          current = location;
          continue;
        }
        return current;
      }
      return current;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static Future<Map<String, dynamic>> _getJson(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set(HttpHeaders.userAgentHeader, userAgent);
      request.headers.set(HttpHeaders.refererHeader, referer);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}');
      }
      final data = jsonDecode(body);
      if (data is! Map<String, dynamic>) {
        throw const FormatException('接口返回格式异常');
      }
      return data;
    } finally {
      client.close(force: true);
    }
  }

  static String mixinKey(String imgKey, String subKey) {
    final source = imgKey + subKey;
    final buffer = StringBuffer();
    for (final index in _mixinTab) {
      if (index < source.length) buffer.write(source[index]);
      if (buffer.length >= 32) break;
    }
    final result = buffer.toString();
    return result.length > 32 ? result.substring(0, 32) : result;
  }

  /// 生成带 w_rid 的 query；[wts] 由调用方传入，便于单测固定时间
  static String signQuery(Map<String, String> params, String mixin, int wts) {
    final merged = Map<String, String>.from(params)..['wts'] = '$wts';
    final keys = merged.keys.toList()..sort();
    final pairs = <String>[];
    for (final key in keys) {
      final value = merged[key]!.replaceAll(RegExp(r"[!'()*]"), '');
      pairs.add('${Uri.encodeQueryComponent(key)}=${Uri.encodeQueryComponent(value)}');
    }
    final query = pairs.join('&');
    final rid = crypto.md5.convert(utf8.encode(query + mixin)).toString();
    return '$query&w_rid=$rid';
  }

  static Future<String> _wbiMixin() async {
    final nav = await _getJson('https://api.bilibili.com/x/web-interface/nav');
    final data = nav['data'];
    final wbi = data is Map ? data['wbi_img'] : null;
    final imgUrl = '${wbi is Map ? wbi['img_url'] ?? '' : ''}';
    final subUrl = '${wbi is Map ? wbi['sub_url'] ?? '' : ''}';
    if (imgUrl.isEmpty || subUrl.isEmpty) {
      throw const FormatException('没有拿到 wbi 密钥');
    }
    final imgKey = imgUrl.split('/').last.split('.').first;
    final subKey = subUrl.split('/').last.split('.').first;
    return mixinKey(imgKey, subKey);
  }

  static Future<ParseResult> parse(String input) async {
    final bvid = await resolveBvid(input);
    if (bvid == null) {
      throw const FormatException('没有识别到 B 站视频链接');
    }

    final view = await _getJson(
      'https://api.bilibili.com/x/web-interface/view?bvid=$bvid',
    );
    if ('${view['code']}' != '0') {
      throw FormatException('${view['message'] ?? '视频信息获取失败'}');
    }
    final info = view['data'] as Map<String, dynamic>?;
    if (info == null) throw const FormatException('视频信息为空');
    final cid = info['cid'];
    if (cid == null) throw const FormatException('没有拿到 cid');

    final mixin = await _wbiMixin();
    final urls = <String>[];
    final labels = <String>[];

    // 未登录只有 720P / 360P 两档，按 qn=64、16 依次请求
    for (final qn in [64, 16]) {
      try {
        final query = signQuery(
          {
            'bvid': bvid,
            'cid': '$cid',
            'qn': '$qn',
            'fnval': '1',
            'fnver': '0',
            'fourk': '1',
          },
          mixin,
          DateTime.now().millisecondsSinceEpoch ~/ 1000,
        );
        final res = await _getJson(
          'https://api.bilibili.com/x/player/wbi/playurl?$query',
        );
        if ('${res['code']}' != '0') continue;
        final data = res['data'];
        if (data is! Map) continue;
        final durl = (data['durl'] as List?) ?? const [];
        if (durl.isEmpty) continue;
        final first = durl.first;
        final url = first is Map ? '${first['url'] ?? ''}' : '';
        if (url.isEmpty || urls.contains(url)) continue;
        urls.add(url);
        labels.add(_qualityLabel('${data['quality'] ?? qn}'));
      } catch (_) {
        // 单档失败不影响其它档
      }
    }

    if (urls.isEmpty) {
      throw const FormatException('没有拿到播放地址（可能需要登录或视频受限）');
    }

    final owner = info['owner'];
    return ParseResult(
      platform: 'bilibili',
      awemeId: bvid,
      title: '${info['title'] ?? ''}',
      author: '${owner is Map ? owner['name'] ?? '' : ''}',
      coverUrl: '${info['pic'] ?? ''}',
      durationMs: (int.tryParse('${info['duration'] ?? 0}') ?? 0) * 1000,
      videoUrls: urls,
      qualityNames: labels,
    );
  }

  static String _qualityLabel(String quality) {
    switch (quality) {
      case '120':
        return '4K';
      case '116':
        return '1080P60';
      case '112':
        return '1080P+';
      case '80':
        return '1080P';
      case '64':
        return '720P';
      case '32':
        return '480P';
      case '16':
        return '360P';
      default:
        return '原画';
    }
  }
}