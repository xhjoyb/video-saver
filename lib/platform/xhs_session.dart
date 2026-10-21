import 'package:webview_flutter/webview_flutter.dart';

/// 小红书登录态（WebView cookie）。
///
/// WebView 的 CookieManager 是全局单例，登录页写入的 cookie 会被
/// ParseController 的隐藏 WebView 直接复用，因此只需登录一次。
class XhsSession {
  XhsSession._();

  static final Uri _origin = Uri.parse('https://www.xiaohongshu.com');
  static const String _cookieName = 'web_session';

  /// 是否已登录：只看 `web_session` 是否存在且非空
  static Future<bool> hasSession() async {
    try {
      final cookies = await WebViewCookieManager().getCookies(_origin);
      return cookies.any(
        (c) => c.name == _cookieName && c.value.trim().isNotEmpty,
      );
    } catch (_) {
      return false;
    }
  }

  /// 清除 WebView 的全部 cookie（会连带清掉抖音的匿名 cookie，不影响功能）
  static Future<void> clear() async {
    try {
      await WebViewCookieManager().clearCookies();
    } catch (_) {}
  }
}