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
    final path = signedUrl(awemeId, const {}); // 先用裸 URL 让页面签名
    final signatureText = await sign(path);
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

    final uri = Uri.parse(signedUrl(awemeId, signature));
    final cookie = (await cookieProvider()) ?? '';

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
        return (null, 'http_${response.statusCode} ${head.replaceAll('\n', ' ')}');
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) return (null, 'non_json');
      final parsed = parseDetail(decoded);
      if (parsed == null) {
        final status = decoded['status_code'];
        return (null, 'no_detail status=$status');
      }
      return (parsed, 'ok');
    } catch (e) {
      final text = e.toString();
      return (null, 'http_err ${text.length > 80 ? text.substring(0, 80) : text}');
    } finally {
      client.close(force: true);
    }
  }
}