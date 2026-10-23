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

  /// 在 web 页面上下文里发一次 detail 请求（带页面自带的 X-Bogus 签名）
  ///
  /// 关键事实（2026-10-23 真机验证）：
  /// - 页面暴露 `window.byted_acrawler.frontierSign({url, method})`，返回 `{"X-Bogus": "…"}`
  /// - 带上 `X-Bogus` 后请求 detail：200 / 66KB / `aweme_detail` 完整；裸请求必 403
  ///
  /// 注意：**不要在这里用 setTimeout 调度**。隐藏 WebView 会被浏览器判定不可见，
  /// 定时器被节流，回调可能几十秒都不触发（真机实测：`__dyResult` 一直为空）。
  /// 因此本函数只做「同步一次尝试」：
  /// - 返回 `have` 已有结果 / `no_signer` 签名器未就绪（由 Dart 侧稍后重试）/
  ///   `inflight` 上一次请求还在飞 / `started` 已发出
  /// - 成功写 `window.__dyResult`，失败写 `window.__dyErr`（都只写一次）
  static String detailJs(String awemeId) => '''
(function () {
  if (window.__dyResult) return 'have';
  var c = window.byted_acrawler;
  if (!c || typeof c.frontierSign !== 'function') return 'no_signer';
  if (window.__dyInflight) return 'inflight';
  window.__dyInflight = true;

  function env() {
    return {
      ua: String(navigator.userAgent).slice(0, 80),
      adt: (navigator.userAgentData && navigator.userAgentData.platform) || 'none'
    };
  }
  function done(o) { try { window.__dyResult = JSON.stringify(o); } catch (e) {} }
  function err(tag, extra) {
    try {
      var o = env();
      o.error = tag;
      o.body = String(extra || '').slice(0, 160);
      window.__dyErr = JSON.stringify(o);
    } catch (e) {}
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
        err('non_json', r.status + ' ' + String(t).slice(0, 120));
      });
    })
    .catch(function (e) { err('fetch', String(e)); })
    .then(function () { window.__dyInflight = false; });

  return 'started';
})()
''';

  /// 读页面里的结果 / 错误（返回原始字符串，由 Dart 侧 JSON 解码）
  static const String readResultJs = 'window.__dyResult || ""';
  static const String readErrorJs = 'window.__dyErr || ""';
}