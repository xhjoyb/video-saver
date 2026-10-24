import 'dart:convert';
import 'dart:io';

/// 抖音解析
///
/// 结论（2026-10-23 真机多轮验证）：
/// - WebView 页面里暴露同步签名器 `window.byted_acrawler.frontierSign({url, method})`
///   → 返回 `{"X-Bogus": "…"}`；带该签名请求 detail 可 200（浏览器实测 66KB）
/// - 但**隐藏 WebView 里发起的 fetch 会一直 pending**（既不成功也不报错，
///   `state=inflight` 卡死），所以网络请求不能放在页面里做
/// - 因此：页面只负责「同步算签名」，HTTP 请求交给 Dart（HttpClient 已被 B 站/快手验证可用），
///   cookie 从原生 CookieManager 读取（含 UIFID / __ac_signature / ttwid）
class DouyinParser {
  DouyinParser._();

  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  static const String referer = 'https://www.douyin.com/';

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

  /// detail 接口路径 + 固定参数
  static String detailPath(String awemeId) =>
      '/aweme/v1/web/aweme/detail/?device_platform=webapp&aid=6383'
      '&channel=channel_pc_web&aweme_id=$awemeId'
      '&pc_client_type=1&version_code=170400&version_name=17.4.0'
      '&cookie_enabled=true&screen_width=1920&screen_height=1080'
      '&browser_language=zh-CN&browser_platform=Win32&browser_name=Chrome'
      '&browser_version=120.0.0.0&browser_online=true&engine_name=Blink'
      '&engine_version=120.0.0.0&os_name=Windows&os_version=10&platform=PC';


  /// 页面环境诊断（失败时写进 note，用来判断到底加载到了什么）
  static const String envJs =
      "(function(){try{var ck=document.cookie.split('; ').map(function(x){return x.split('=')[0]});"
      "return JSON.stringify({rs:document.readyState,url:String(location.href).slice(0,90),"
      "acr:typeof window.byted_acrawler,ck:ck.slice(0,20),ckLen:document.cookie.length,"
      "title:String(document.title).slice(0,40)});}catch(e){return ''}})()";

  /// 在页面里同步取签名（不联网、不用定时器）
  ///
  /// 返回 JSON 字符串（如 `{"X-Bogus":"…"}`）；签名器未就绪时返回空串。
  static String signJs(String absoluteUrl) =>
      "(function(){try{var c=window.byted_acrawler;"
      "if(!c||typeof c.frontierSign!=='function')return '';"
      "var s=c.frontierSign({url:'$absoluteUrl',method:'GET'})||{};"
      "return JSON.stringify(s);}catch(e){return ''}})()";

  /// 用签名结果补全 URL
  static String signedUrl(String awemeId, Map<String, dynamic> signature) {
    final base = 'https://www.douyin.com${detailPath(awemeId)}';
    final query = signature.entries
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent('${e.value}')}')
        .join('&');
    return query.isEmpty ? base : '$base&$query';
  }

  /// 把 `aweme_detail` 转成 App 内部结果结构
  static Map<String, dynamic>? parseDetail(Map<String, dynamic> json) {
    final detail = json['aweme_detail'];
    if (detail is! Map) return null;
    final video = detail['video'];
    final v = video is Map ? video : const {};
    final playUrl = v['play_addr'];
    final play = playUrl is Map ? (playUrl['url_list'] as List?) ?? const [] : const [];

    String firstUrl(Object? node) {
      if (node is! Map) return '';
      final list = (node['url_list'] as List?) ?? const [];
      return list.isEmpty ? '' : '${list.first}';
    }

    final cover = firstUrl(v['cover']);
    var images = <String>[];
    final imgs = detail['images'];
    final postInfo = detail['image_post_info'];
    if (imgs is List && imgs.isNotEmpty) {
      images = imgs.map((e) => firstUrl(e)).where((e) => e.isNotEmpty).toList();
    } else if (postInfo is Map && postInfo['images'] is List) {
      images = (postInfo['images'] as List)
          .map((e) => firstUrl(e))
          .where((e) => e.isNotEmpty)
          .toList();
    }

    return {
      'id': '${detail['aweme_id'] ?? ''}',
      'desc': '${detail['desc'] ?? ''}',
      'author': detail['author'] is Map ? '${(detail['author'] as Map)['nickname'] ?? ''}' : '',
      'cover': cover,
      'duration': int.tryParse('${v['duration'] ?? 0}') ?? 0,
      'play': play.map((e) => '$e').where((e) => e.startsWith('http')).toList(),
      'images': images,
    };
  }

  /// 页面签名 + Dart 侧 HTTP 拉取 detail
  ///
  /// [sign] 负责在 WebView 里同步算签名；[cookieProvider] 读原生 CookieManager。
  /// 返回 `(数据结构, 说明)`：数据结构为空时，说明用于诊断（sign_empty / http_403 / non_json …）。
  static Future<(Map<String, dynamic>?, String)> fetchDetail({
    required String awemeId,
    required String ua,
    required Future<String> Function(String absoluteUrl) sign,
    required Future<String?> Function() cookieProvider,
  }) async {
    final cookie = (await cookieProvider()) ?? '';
    final rawUifid = extractCookieRaw(cookie, 'UIFID');
    if (rawUifid.isEmpty) return (null, 'sign_empty no_uifid');

    // CookieManager 里的 UIFID 可能已 URL 编码，服务端登记的是「原样」值；
    // 两种形态都试一遍，命中哪个由 note 里的 uifid=dec/raw 说明。
    final candidates = <String>[];
    final decoded = _tryDecode(rawUifid);
    if (decoded.isNotEmpty && decoded != rawUifid) candidates.add(decoded);
    candidates.add(rawUifid);

    var lastNote = '';
    for (final uifid in candidates) {
      final result = await _requestOnce(
        awemeId: awemeId,
        ua: ua,
        uifid: uifid,
        cookie: cookie,
        sign: sign,
      );
      if (result.$1 != null) {
        final tag = identical(uifid, decoded) || uifid == decoded
            ? 'ok uifid=dec len=${uifid.length}'
            : 'ok uifid=raw len=${uifid.length} pct=${rawUifid.contains('%')}';
        return (result.$1, tag);
      }
      lastNote = result.$2;
    }
    return (null, '$lastNote uifid_len=${rawUifid.length} pct=${rawUifid.contains('%')}');
  }

  /// 单次请求：签名 + Dart HTTP
  static Future<(Map<String, dynamic>?, String)> _requestOnce({
    required String awemeId,
    required String ua,
    required String uifid,
    required String cookie,
    required Future<String> Function(String absoluteUrl) sign,
  }) async {
    var base = signedUrl(awemeId, const {});
    base = '$base&uifid=${Uri.encodeQueryComponent(uifid)}';

    final signatureText = await sign(base);
    if (signatureText.isEmpty) return (null, 'sign_empty');

    Map<String, dynamic> signature;
    try {
      final decoded = jsonDecode(signatureText);
      if (decoded is! Map) return (null, 'sign_bad');
      signature = decoded.map((k, v) => MapEntry('$k', '$v'));
    } catch (_) {
      return (null, 'sign_bad');
    }
    if (signature.isEmpty) return (null, 'sign_empty');

    final query = signature.entries
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent('${e.value}')}')
        .join('&');
    final uri = Uri.parse(query.isEmpty ? base : '$base&$query');

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader, ua);
      request.headers.set(HttpHeaders.refererHeader, referer);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (cookie.isNotEmpty) {
        request.headers.set(HttpHeaders.cookieHeader, cookie);
      }
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        final head = body.length > 80 ? body.substring(0, 80) : body;
        return (null, 'http_${response.statusCode} ${head.replaceAll(RegExp(r'\s+'), ' ')}');
      }
      final decodedBody = jsonDecode(body);
      if (decodedBody is! Map<String, dynamic>) return (null, 'non_json');
      final parsed = parseDetail(decodedBody);
      if (parsed == null) {
        return (null, 'no_detail status=${decodedBody['status_code']}');
      }
      return (parsed, 'ok');
    } catch (e) {
      final text = e.toString();
      return (null, 'http_err ${text.length > 80 ? text.substring(0, 80) : text}');
    } finally {
      client.close(force: true);
    }
  }

  static String _tryDecode(String value) {
    try {
      return Uri.decodeComponent(value);
    } catch (_) {
      return value;
    }
  }

  /// 从 cookie 串里取指定项（原样，不做解码）
  static String extractCookieRaw(String cookie, String name) {
    final m = RegExp('(?:^|;\s*)' + name + '=([^;]+)').firstMatch(cookie);
    var v = m == null ? '' : (m.group(1) ?? '');
    if (v.length >= 2 && v.startsWith('"') && v.endsWith('"')) {
      v = v.substring(1, v.length - 1);
    }
    return v;
  }
}
