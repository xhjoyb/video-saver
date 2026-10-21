import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 小红书登录态。
///
/// webview_flutter 4.x 的 `WebViewCookieManager` 只能写/清 cookie、**不能读取**，
/// 所以这里用本地标记表示「已登录」，真正的凭据仍保存在 WebView 的 cookie 里。
/// 解析撞到登录墙时会提示重新登录，避免标记过期造成误判。
class XhsSession {
  XhsSession._();

  static const String _key = 'xhs_logged_in';

  static Future<bool> hasSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_key) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> markLoggedIn(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value) {
        await prefs.setBool(_key, true);
      } else {
        await prefs.remove(_key);
      }
    } catch (_) {}
  }

  /// 退出登录：清本地标记 + 清 WebView cookie（会连带清掉抖音匿名 cookie，不影响功能）
  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
      await WebViewCookieManager().clearCookies();
    } catch (_) {}
  }
}