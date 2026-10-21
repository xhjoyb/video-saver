import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// B 站登录态（SESSDATA 等 cookie）。
///
/// 与小红书不同：这里通过**原生 CookieManager** 读取 WebView 的 cookie，
/// 因此 HttpOnly 的 `SESSDATA` 也能拿到，再作为 `Cookie` 头随 playurl 请求发出。
class BilibiliSession {
  BilibiliSession._();

  static const MethodChannel _channel = MethodChannel('videosaver/media');
  static const String _prefsKey = 'bilibili_cookie';

  static bool hasSessdata(String? cookie) =>
      (cookie ?? '').contains('SESSDATA=');

  static Future<String?> cookie() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey)?.trim() ?? '';
      return raw.isEmpty ? null : raw;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> isLoggedIn() async => hasSessdata(await cookie());

  /// 登录页点「完成」后调用：从 WebView 读取 cookie，含 SESSDATA 才保存
  static Future<bool> captureFromWebView() async {
    try {
      final raw = await _channel.invokeMethod<String>('getWebViewCookies', {
        'url': 'https://www.bilibili.com',
      });
      final cookie = (raw ?? '').trim();
      if (!hasSessdata(cookie)) return false;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, cookie);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (_) {}
  }
}