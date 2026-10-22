import 'package:flutter/services.dart';

/// WebView 环境信息（从原生侧读取）
///
/// 抖音对「UA 声明 Windows、Client Hints 却是 Android」这种自相矛盾的环境
/// 会挂起接口请求，因此需要拿到与引擎一致的真实 UA 做对照尝试。
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
}
