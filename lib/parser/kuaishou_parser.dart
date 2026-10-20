import 'dart:convert';
import 'dart:io';

import 'parse_result.dart';

/// 快手解析：移动端分享页（`v.m.chenzhongtech.com/fw/photo/{id}`）是 SSR，
/// 页面里直接内嵌 mp4 直链与标题/作者/时长，**不需要签名**。
///
/// 已验证：
/// - 短链 `v.kuaishou.com/xxx` 302 到移动分享页
/// - mp4 落在 `*.kwimgs.com/upic/...mp4`，带 Referer 返回 206 video/mp4
/// - 不传 Referer 也能下载（比 B 站宽松），但仍统一带上 `https://www.kuaishou.com/`
class KuaishouParser {
  KuaishouParser._();

  static const String userAgent =
      'Mozilla/5.0 (Linux; Android 14; PGT-AN20 Build/HONORPGT-AN20) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';
  static const String referer = 'https://www.kuaishou.com/';

  static final RegExp _urlRe = RegExp(r'https?://[^\s\u4e00-\u9fa5]+');
  static final RegExp _kwaiShortRe = RegExp(r'https?://v\.kuaishou\.com/[A-Za-z0-9]+');
  static final RegExp _photoIdInUrlRe =
      RegExp(r'/(?:short-video|fw/photo)/([0-9A-Za-z]{10,20})');
  static final RegExp _pureIdRe = RegExp(r'^[0-9A-Za-z]{14,20}$');

  static bool looksLike(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('kuaishou.com') || lower.contains('chenzhongtech.com')) {
      return true;
    }
    // 纯 photoId：16 位左右、必须含字母（抖音 ID 是纯数字，避免误判）
    final trimmed = text.trim();
    return _pureIdRe.hasMatch(trimmed) &&
        RegExp(r'[A-Za-z]').hasMatch(trimmed) &&
        !trimmed.startsWith('BV');
  }

  static String? extractPhotoId(String text) {
    final inUrl = _photoIdInUrlRe.firstMatch(text);
    if (inUrl != null) return inUrl.group(1);
    final trimmed = text.trim();
    if (_pureIdRe.hasMatch(trimmed)) return trimmed;
    return null;
  }

  /// 短链需要跟 302；完整链接直接取 id
  static Future<String?> resolvePhotoId(String input) async {
    final direct = extractPhotoId(input);
    if (direct != null) return direct;

    final short = _kwaiShortRe.firstMatch(input)?.group(0) ??
        _urlRe.firstMatch(input)?.group(0);
    if (short == null) return null;

    final location = await _followRedirects(short);
    if (location == null) return null;
    return extractPhotoId(location);
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

  static Future<String?> _getText(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set(HttpHeaders.userAgentHeader, userAgent);
      request.headers.set(HttpHeaders.refererHeader, referer);
      request.headers.set(HttpHeaders.acceptHeader, 'text/html,*/*');
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      return response.statusCode == 200 ? body : null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static Future<ParseResult> parse(String input) async {
    final photoId = await resolvePhotoId(input);
    if (photoId == null) {
      throw const FormatException('没有识别到快手视频链接');
    }

    final html = await _getText(
      'https://v.m.chenzhongtech.com/fw/photo/$photoId',
    );
    if (html == null || html.isEmpty) {
      throw const FormatException('快手分享页加载失败');
    }

    final caption = _clean(
      _firstGroup(RegExp(r'"caption"\s*:\s*"((?:[^"\\]|\\.)*)"'), html),
    );
    final author = _clean(
      _firstGroup(RegExp(r'"userName"\s*:\s*"((?:[^"\\]|\\.)*)"'), html),
    );
    final duration = int.tryParse(
          _firstGroup(RegExp(r'"duration"\s*:\s*(\d+)'), html) ?? '',
        ) ??
        0;

    final mp4Matches = RegExp(
      r'https://[a-z0-9.]+\.kwimgs\.com/[^"\\\s<>]+\.mp4[^"\\\s<>]*',
    ).allMatches(html);
    final urls = <String>[];
    for (final m in mp4Matches) {
      final url = _clean(m.group(0)!);
      if (url.isNotEmpty && !urls.contains(url)) urls.add(url);
    }

    if (urls.isEmpty) {
      throw const FormatException('没有拿到视频地址（可能是图文作品或权限受限）');
    }

    return ParseResult(
      platform: 'kuaishou',
      awemeId: photoId,
      title: caption,
      author: author,
      coverUrl: '',
      durationMs: duration,
      videoUrls: urls,
    );
  }

  static String? _firstGroup(RegExp re, String text) {
    final m = re.firstMatch(text);
    return m?.group(1);
  }

  /// 处理 JSON 转义：`\/` → `/`，`\uXXXX` → 字符
  static String _clean(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    var text = raw.replaceAll(r'\/', '/');
    text = text.replaceAllMapped(
      RegExp(r'\\u([0-9a-fA-F]{4})'),
      (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)),
    );
    return text.trim();
  }
}