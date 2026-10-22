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

  /// 在 web 页面上下文里请求 detail（同源，页面会自行加 a_bogus 并带 cookie）
  ///
  /// 2026-10 真机实测：页面加载正常、`byted_acrawler` 已就绪、cookie 有
  /// `UIFID`/`__ac_signature`，但 `fetch` 既不 resolve 也不 reject（一直 pending），
  /// 导致 `__dyResult` 永远为空、解析超时。因此这里：
  /// - `fetch` 加 6s 超时（AbortController）；
  /// - 失败/超时后用 `XMLHttpRequest` 兜底再打一次；
  /// - 结果里附带 UA / Client Hints / visibilityState / 耗时，便于区分环境问题。
  static String detailJs(String awemeId) => '''
(function () {
  if (window.__dyResult) return 'have';
  var t0 = Date.now();
  function env() {
    return {
      ua: String(navigator.userAgent).slice(0, 90),
      adt: (navigator.userAgentData && navigator.userAgentData.platform) || 'none',
      vis: document.visibilityState,
      ms: Date.now() - t0
    };
  }
  function done(obj) {
    try { window.__dyResult = JSON.stringify(obj); } catch (e) {}
  }
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
    return o;
  }

  var u = '/aweme/v1/web/aweme/detail/?device_platform=webapp&aid=6383'
    + '&channel=channel_pc_web&aweme_id=$awemeId'
    + '&pc_client_type=1&version_code=170400&version_name=17.4.0'
    + '&cookie_enabled=true&screen_width=1920&screen_height=1080'
    + '&browser_language=zh-CN&browser_platform=Win32&browser_name=Chrome'
    + '&browser_version=120.0.0.0&browser_online=true&engine_name=Blink'
    + '&engine_version=120.0.0.0&os_name=Windows&os_version=10&platform=PC';

  window.__dyResult = '';

  var settled = false;
  function settle(fn) { if (settled) return; settled = true; fn(); }

  function viaXhr() {
    try {
      var x = new XMLHttpRequest();
      x.open('GET', u, true);
      x.withCredentials = true;
      x.timeout = 6000;
      x.onload = function () {
        var d = parse(x.responseText || '');
        if (d) { settle(function () { done(d); }); return; }
        settle(function () {
          fail('xhr_non_json', x.status + ' ' + String(x.responseText || '').slice(0, 120));
        });
      };
      x.onerror = function () { settle(function () { fail('xhr_error', 'status=' + x.status); }); };
      x.ontimeout = function () { settle(function () { fail('xhr_timeout', ''); }); };
      x.send();
    } catch (e) {
      settle(function () { fail('xhr_throw', String(e)); });
    }
  }

  var ctl = window.AbortController ? new AbortController() : null;
  var timer = setTimeout(function () { try { if (ctl) ctl.abort(); } catch (e) {} }, 6000);

  try {
    fetch(u, {
      credentials: 'include',
      cache: 'no-store',
      signal: ctl ? ctl.signal : undefined
    }).then(function (r) {
      return r.text().then(function (t) {
        clearTimeout(timer);
        var d = parse(t);
        if (d) { settle(function () { done(d); }); return; }
        fail('non_json', r.status + ' ' + String(t).slice(0, 120));
        viaXhr();
      });
    }).catch(function (e) {
      clearTimeout(timer);
      fail('fetch', String(e));
      viaXhr();
    });
  } catch (e) {
    clearTimeout(timer);
    fail('fetch_throw', String(e));
    viaXhr();
  }
  return 'kicked';
})()
''';

  /// 页面内「旁路采集」：拦截页面自己的 detail 请求，把响应存进 `__dyResult`
  ///
  /// 为什么不自己发请求：`/aweme/v1/web/aweme/detail/` 需要页面 SDK 生成
  /// `a_bogus` 并带 `msToken` 等指纹，裸 `fetch` 必然 403。页面自己渲染视频时
  /// 一定会发一次请求，这里只挂代理取响应，不参与签名，成功率等于正常浏览。
  static String get captureJs => r'''
(function () {
  if (window.__dyHooked) return 'ok';
  window.__dyHooked = true;
  if (!window.__dyResult) window.__dyResult = '';

  function pick(text) {
    try {
      var j = JSON.parse(text);
      var a = j && j.aweme_detail;
      if (!a) return;
      var v = a.video || {};
      var play = (v.play_addr && v.play_addr.url_list) || [];
      var cover = ((v.cover && v.cover.url_list) || [''])[0] || '';
      var imgs = [];
      if (a.images && a.images.length) {
        imgs = a.images.map(function (it) { return ((it.url_list || [''])[0]); });
      } else if (a.image_post_info && a.image_post_info.images && a.image_post_info.images.length) {
        imgs = a.image_post_info.images.map(function (it) { return ((it.url_list || [''])[0]); });
      }
      window.__dyResult = JSON.stringify({
        id: a.aweme_id || '',
        desc: a.desc || '',
        author: (a.author && a.author.nickname) || '',
        cover: cover,
        duration: v.duration || 0,
        play: play,
        images: imgs,
        via: 'page'
      });
    } catch (e) {}
  }

  var of = window.fetch;
  if (of) {
    window.fetch = function () {
      var url = String((arguments[0] && arguments[0].url) || arguments[0] || '');
      var p = of.apply(this, arguments);
      try {
        if (url.indexOf('aweme/detail') >= 0) {
          p.then(function (r) {
            try { r.clone().text().then(pick).catch(function () {}); } catch (e) {}
          }).catch(function () {});
        }
      } catch (e) {}
      return p;
    };
  }

  try {
    var open = XMLHttpRequest.prototype.open;
    var send = XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.open = function (m, u) {
      try { this.__dyUrl = String(u || ''); } catch (e) {}
      return open.apply(this, arguments);
    };
    XMLHttpRequest.prototype.send = function () {
      var self = this;
      try {
        if (String(self.__dyUrl || '').indexOf('aweme/detail') >= 0) {
          self.addEventListener('load', function () {
            try { pick(self.responseText || ''); } catch (e) {}
          });
        }
      } catch (e) {}
      return send.apply(this, arguments);
    };
  } catch (e) {}

  return 'ok';
})()
''';
}