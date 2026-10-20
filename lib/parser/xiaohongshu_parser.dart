import 'dart:convert';
import 'dart:io';

import 'parse_result.dart';

/// 小红书解析：网页端 SSR 已下线，必须用 WebView 渲染后从
/// `window.__INITIAL_STATE__.note.noteDetailMap` 里取数据。
///
/// 已验证：
/// - 分享短链 `xhslink.cn` / `xhslink.com` 302 到 `www.xiaohongshu.com/...?xsec_token=...`
/// - 直接 GET 只能拿到 36KB 的 SPA 空壳（无 noteDetailMap）
/// - WebView 渲染后可读到标题/作者/图片/视频 `masterUrl`
class XiaohongshuParser {
  XiaohongshuParser._();

  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  static const String referer = 'https://www.xiaohongshu.com/';

  static final RegExp _linkRe =
      RegExp(r'https?://xhslink\.(?:cn|com)/[A-Za-z0-9]+(?:/[A-Za-z0-9]+)*');
  static final RegExp _urlRe = RegExp(r'https?://[^\s\u4e00-\u9fa5]+');
  static final RegExp _noteIdRe =
      RegExp(r'/(?:explore|discovery/item)/([0-9a-f]{24})');

  static bool looksLike(String text) {
    final lower = text.toLowerCase();
    return lower.contains('xiaohongshu.com') || lower.contains('xhslink.');
  }

  static String? extractShareUrl(String text) {
    final short = _linkRe.firstMatch(text)?.group(0);
    if (short != null) return short;
    var url = _urlRe.firstMatch(text)?.group(0);
    if (url == null) return null;
    url = url.replaceAll(
      RegExp(r'''[)\]}>.,;:!?"'，。；：！？、）】」』]+$'''),
      '',
    );
    return url;
  }

  static String? extractNoteId(String text) {
    final m = _noteIdRe.firstMatch(text);
    return m?.group(1);
  }

  /// 返回可直接加载的笔记页 URL（短链会跟 302，保留 xsec_token）
  static Future<String?> resolvePageUrl(String input) async {
    final url = extractShareUrl(input);
    if (url == null) return null;
    if (url.contains('xiaohongshu.com')) return url;
    return _followRedirects(url);
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

  /// 注入到 WebView 的提取脚本，返回 JSON 字符串
  static const String extractJs = r'''
(function () {
  try {
    var s = window.__INITIAL_STATE__;
    var map = s && s.note && s.note.noteDetailMap;
    if (!map) return "";
    var keys = Object.keys(map);
    if (!keys.length) return "";
    var item = map[keys[0]];
    var n = item && item.note;
    if (!n) return "";
    var stream = n.video && n.video.media && n.video.media.stream;
    var videos = [];
    if (stream) {
      ["h264", "h265", "h266"].forEach(function (codec) {
        (stream[codec] || []).forEach(function (v) {
          if (v && v.masterUrl) videos.push(v.masterUrl);
        });
      });
    }
    var images = (n.imageList || []).map(function (i) {
      return (i && (i.urlDefault || i.urlPre || i.url)) || "";
    }).filter(function (u) { return !!u; });
    var duration = (n.video && n.video.capa && n.video.capa.duration) || 0;
    return JSON.stringify({
      title: n.title || n.desc || "",
      author: (n.user && n.user.nickname) || "",
      images: images,
      videos: videos,
      duration: duration
    });
  } catch (e) { return ""; }
})()
''';

  static ParseResult buildResult(Map<String, dynamic> data, String noteId) {
    final videos = _list(data['videos']);
    final images = _list(data['images']);
    final hasVideo = videos.isNotEmpty;
    return ParseResult(
      platform: 'xiaohongshu',
      awemeId: noteId,
      title: '${data['title'] ?? ''}',
      author: '${data['author'] ?? ''}',
      coverUrl: images.isNotEmpty ? images.first : '',
      durationMs: (int.tryParse('${data['duration'] ?? 0}') ?? 0) * 1000,
      videoUrls: videos,
      // 视频笔记的 imageList 只是封面，不能当图集
      imageUrls: hasVideo ? const [] : images,
    );
  }

  static List<String> _list(Object? raw) {
    if (raw is! List) return const [];
    final out = <String>[];
    for (final item in raw) {
      var url = '$item'.trim();
      if (url.isEmpty) continue;
      // 小红书 CDN 会返回 http，统一升到 https
      if (url.startsWith('http://')) {
        url = 'https://${url.substring(7)}';
      }
      if (!out.contains(url)) out.add(url);
    }
    return out;
  }

  /// 解析不了时的兜底：把页面里的 og:video / video 标签 URL 当候选
  static const String fallbackJs = r'''
(function () {
  try {
    var meta = document.querySelector('meta[property="og:video"]');
    if (meta && meta.content) return meta.content;
    var v = document.querySelector('video');
    if (v) {
      if (v.src && v.src.indexOf('http') === 0) return v.src;
      var src = v.querySelector('source');
      if (src && src.src) return src.src;
    }
    return "";
  } catch (e) { return ""; }
})()
''';

  static Future<Map<String, dynamic>?> decodePayload(String raw) async {
    var text = raw.trim();
    if (text.isEmpty || text == '""') return null;
    if (text.startsWith('"') && text.endsWith('"')) {
      text = jsonDecode(text) as String;
    }
    if (text.isEmpty) return null;
    final data = jsonDecode(text);
    return data is Map<String, dynamic> ? data : null;
  }
}