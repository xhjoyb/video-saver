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

    final isShort =
        url.contains('v.douyin.com') || url.contains('v.iesdouyin.com');
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

  /// 在 web 页面上下文里请求 detail
  ///
  /// 关键（2026-10-23 真机验证）：抖音 web 端页面暴露了签名器
  /// `window.byted_acrawler.frontierSign({url, method})`，返回 `{"X-Bogus": "..."}`。
  /// 把该签名追加到 URL 后请求 detail，实测 **200 / 66KB / aweme_detail 完整**。
  /// 裸请求（不带签名）会被判游客直接 403。
  ///
  /// 因此这里：等 `byted_acrawler` 就绪（最多 5s）→ 取 X-Bogus → fetch → 解析；
  /// 失败重试最多 3 次；结果里附带 UA / Client Hints / 耗时便于排查。
  static String detailJs(String awemeId) => '''
(function () {
  if (window.__dyResult) return 'have';
  var t0 = Date.now();
  function env() {
    return {
      ua: String(navigator.userAgent).slice(0, 80),
      adt: (navigator.userAgentData && navigator.userAgentData.platform) || 'none',
      ms: Date.now() - t0
    };
  }
  function done(obj) { try { window.__dyResult = JSON.stringify(obj); } catch (e) {} }
  function fail(tag, extra) {
    var o = env();
    o.error = tag;
    o.body = String(extra || '').slice(0, 160);
    done(o);
  }
  function parse(t) {
    var j = null;
    try { j = JSON.parse(t); } catch (e) {}
    if (!j) return null;
    var a = j.aweme_detail || {};
    var v = a.video || {};
    var play = (v.play_addr && v.play_addr.url_list) || [];
    var cover = ((v.cover && v.cover.url_list) || [''])[0] || '';
    var imgs = [];
    if (a.images && a.images.length) {
      imgs = a.images.map(function (it) { return ((it.url_list || [''])[0]); });
    } else if (a.image_post_info && a.image_post_info.images && a.image_post_info.images.length) {
      imgs = a.image_post_info.images.map(function (it) { return ((it.url_list || [''])[0]); });
    }
    var o = env();
    o.id = a.aweme_id || '';
    o.desc = a.desc || '';
    o.author = (a.author && a.author.nickname) || '';
    o.cover = cover;
    o.duration = v.duration || 0;
    o.play = play;
    o.images = imgs;
    o.via = 'x-bogus';
    return o;
  }

  var base = '/aweme/v1/web/aweme/detail/?device_platform=webapp&aid=6383'
    + '&channel=channel_pc_web&aweme_id=$awemeId'
    + '&pc_client_type=1&version_code=170400&version_name=17.4.0'
    + '&cookie_enabled=true&screen_width=1920&screen_height=1080'
    + '&browser_language=zh-CN&browser_platform=Win32&browser_name=Chrome'
    + '&browser_version=120.0.0.0&browser_online=true&engine_name=Blink'
    + '&engine_version=120.0.0.0&os_name=Windows&os_version=10&platform=PC';

  function signer() {
    var c = window.byted_acrawler;
    return (c && typeof c.frontierSign === 'function') ? c : null;
  }

  var tries = 0;
  function attempt() {
    tries++;
    var c = signer();
    if (!c) {
      if (Date.now() - t0 < 5000) { setTimeout(attempt, 300); return; }
      fail('no_signer', 'byted_acrawler 未就绪');
      return;
    }
    var url = base;
    try {
      var sig = c.frontierSign({ url: location.origin + base, method: 'GET' }) || {};
      var q = Object.keys(sig).map(function (k) {
        return k + '=' + encodeURIComponent(sig[k]);
      }).join('&');
      if (q) url = base + '&' + q;
    } catch (e) {}
    fetch(url, { credentials: 'include', cache: 'no-store' })
      .then(function (r) {
        return r.text().then(function (t) {
          var d = parse(t);
          if (d) { done(d); return; }
          if (tries < 3) { setTimeout(attempt, 700); return; }
          fail('non_json', r.status + ' ' + String(t).slice(0, 120));
        });
      })
      .catch(function (e) {
        if (tries < 3) { setTimeout(attempt, 700); return; }
        fail('fetch', String(e));
      });
  }
  setTimeout(attempt, 0);
  return 'kicked';
})()
''';
}
