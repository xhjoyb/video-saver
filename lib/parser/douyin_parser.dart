import 'dart:io';

/// 抖音解析：短链/长链 → aweme_id，以及在页面内触发 detail 请求的 JS
class DouyinParser {
  DouyinParser._();

  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  static final RegExp _urlRe = RegExp(r'https?://[^\s\u4e00-\u9fa5]+');
  static final RegExp _idRe = RegExp(r'/(?:video|note)/(\d{15,20})');
  static final RegExp _modalRe = RegExp(r'[?&]modal_id=(\d{15,20})');
  static final RegExp _pureIdRe = RegExp(r'^\d{15,20}$');

  static String? extractUrl(String text) {
    final m = _urlRe.firstMatch(text);
    return m?.group(0);
  }

  /// 从分享文本 / 短链 / 长链 / 纯 ID 中解析出 aweme_id
  static Future<String?> resolveAwemeId(String input) async {
    final text = input.trim();
    if (_pureIdRe.hasMatch(text)) return text;

    final url = extractUrl(text);
    if (url == null) return null;

    final direct = _idRe.firstMatch(url) ?? _modalRe.firstMatch(url);
    if (direct != null) return direct.group(1);

    final isShort = url.contains('v.douyin.com') || url.contains('v.iesdouyin.com');
    if (!isShort) return null;

    final location = await _followOnce(url);
    if (location == null) return null;
    final m = _idRe.firstMatch(location) ?? _modalRe.firstMatch(location);
    return m?.group(1);
  }

  static Future<String?> _followOnce(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.userAgentHeader, userAgent);
      final response = await request.close();
      final location = response.headers.value(HttpHeaders.locationHeader);
      await response.drain<void>();
      return location;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// 在 web 页面上下文里请求 detail（同源，页面会自行加 a_bogus 并带 cookie）
  static String detailJs(String awemeId) => '''
(function () {
  try {
    window.__dyResult = '';
    var u = '/aweme/v1/web/aweme/detail/?device_platform=webapp&aid=6383'
      + '&channel=channel_pc_web&aweme_id=$awemeId'
      + '&pc_client_type=1&version_code=170400&version_name=17.4.0'
      + '&cookie_enabled=true&screen_width=1920&screen_height=1080'
      + '&browser_language=zh-CN&browser_platform=Win32&browser_name=Chrome'
      + '&browser_version=120.0.0.0&browser_online=true&engine_name=Blink'
      + '&engine_version=120.0.0.0&os_name=Windows&os_version=10&platform=PC';
    fetch(u, { credentials: 'include' })
      .then(function (r) { return r.json(); })
      .then(function (j) {
        var a = j.aweme_detail || {};
        var v = a.video || {};
        var play = (v.play_addr && v.play_addr.url_list) || [];
        var cover = ((v.cover && v.cover.url_list) || [''])[0] || '';
        var imgs = (a.images || []).map(function (it) { return ((it.url_list || [''])[0]); });
        window.__dyResult = JSON.stringify({
          id: a.aweme_id || '',
          desc: a.desc || '',
          author: (a.author && a.author.nickname) || '',
          cover: cover,
          duration: v.duration || 0,
          play: play,
          images: imgs
        });
      })
      .catch(function (e) { window.__dyResult = JSON.stringify({ error: String(e) }); });
    return 'kicked';
  } catch (e) { return 'ERR ' + e; }
})()
''';
}