import 'package:flutter/services.dart';

/// WebView 环境信息（从原生侧读取）
///
/// 两个用途：
/// - 拿 WebView 引擎真实 UA（与 Client Hints 一致），用于抖音兜底尝试
/// - 读 CookieManager 里的 cookie（含 HttpOnly 的 UIFID / __ac_signature / ttwid），
///   供 Dart 侧 HTTP 请求使用（抖音页面里 fetch 会挂死，请求必须搬到 Dart）
class WebViewEnv {
  WebViewEnv._();

  static const MethodChannel _channel = MethodChannel('videosaver/media');

  static String? _defaultUa;

  /// WebView 默认 UA（真实平台，与 `navigator.userAgentData` 一致）
  static Future<String?> defaultUserAgent() async {
    if (_defaultUa != null) return _defaultUa;
    try {
      final ua = await _channel.invokeMethod<String>('defaultUserAgent');
      if (ua != null && ua.isNotEmpty) _defaultUa = ua;
      return _defaultUa;
    } catch (_) {
      return null;
    }
  }

  /// 读指定 URL 的 cookie（原生 CookieManager，含 HttpOnly）
  static Future<String?> cookies(String url) async {
    try {
      final raw = await _channel.invokeMethod<String>('getWebViewCookies', {
        'url': url,
      });
      final text = (raw ?? '').trim();
      return text.isEmpty ? null : text;
    } catch (_) {
      return null;
    }
  }
}