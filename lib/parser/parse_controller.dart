import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../platform/webview_env.dart';
import 'bilibili_parser.dart';
import 'diag_log.dart';
import 'douyin_parser.dart';
import 'kuaishou_parser.dart';
import 'parse_result.dart';
import 'xiaohongshu_parser.dart';

enum ParseStage { idle, resolving, loading, parsing, done, error }

/// 解析控制器：用隐藏 WebView 打开抖音视频页，页面内请求 detail 并回传结果
class ParseController extends ChangeNotifier {
  ParseController() {
    web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(DouyinParser.userAgent)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            // 阻止 snssdk:// 等自定义 scheme 唤起，避免整页 ERR_UNKNOWN_URL_SCHEME
            final url = request.url;
            if (!url.startsWith('http://') && !url.startsWith('https://')) {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageFinished: (url) {
            // 只有抖音走「页面内 fetch + 轮询」；小红书由自身流程轮询
            if (_stage != ParseStage.loading || _mode != 'douyin') return;
            _scheduleProbe();
          },
          onPageStarted: (url) {
            // 小红书风控会检测自动化特征，页面一开始就注入伪装脚本
            if (_mode != 'xhs') return;
            web
                .runJavaScript(XiaohongshuParser.browserMaskJs)
                .catchError((Object _) {});
          },
          onWebResourceError: (e) {
            if (_stage == ParseStage.loading && e.isForMainFrame == true) {
              _fail('页面加载失败：${e.description}');
            }
          },
        ),
      );
  }

  late final WebViewController web;

  ParseStage _stage = ParseStage.idle;
  ParseResult? _result;
  String? _error;
  String? _awemeId;
  Timer? _debounce;
  Timer? _timeout;
  bool _probeStarted = false;
  bool _warmed = false;
  String _mode = 'douyin';

  /// 请求代次：新解析开始时自增，旧请求的异步回写会因代次不匹配而作废
  int _seq = 0;

  /// 预热：提前打开 douyin.com 让 cookie / 签名就绪，降低首次解析被拦与耗时
  Future<void> warmUp() async {
    if (_warmed) return;
    _warmed = true;
    try {
      if (_stage == ParseStage.idle) {
        await web.loadRequest(Uri.parse('https://www.douyin.com/'));
      }
    } catch (_) {}
  }

  ParseStage get stage => _stage;
  ParseResult? get result => _result;
  String? get error => _error;

  bool get busy =>
      _stage == ParseStage.resolving ||
      _stage == ParseStage.loading ||
      _stage == ParseStage.parsing;

  Future<void> parse(String input) async {
    final seq = ++_seq;
    _debounce?.cancel();
    _timeout?.cancel();
    _probeStarted = false;
    _mode = 'douyin';
    _result = null;
    _error = null;
    _stage = ParseStage.resolving;
    notifyListeners();

    // 小红书：网页 SSR 已下线，用隐藏 WebView 渲染后取 __INITIAL_STATE__
    if (XiaohongshuParser.looksLike(input)) {
      await _parseXiaohongshu(input);
      return;
    }

    // B 站走纯 HTTP（wbi 签名），不需要 WebView
    if (BilibiliParser.looksLike(input)) {
      await _parseBilibili(input, seq);
      return;
    }

    // 快手：移动分享页 SSR 直出 mp4，同样走纯 HTTP
    if (KuaishouParser.looksLike(input)) {
      await _parseKuaishou(input, seq);
      return;
    }

    final id = await DouyinParser.resolveAwemeId(input);
    if (id == null) {
      _fail('没有识别到支持的视频链接');
      return;
    }
    _awemeId = id;
    _stage = ParseStage.loading;
    notifyListeners();

    _timeout = Timer(const Duration(seconds: 75), () {
      if (busy) _fail('解析超时，请检查网络后重试');
    });

    try {
      // 直接打开视频页：少一跳 302，也避免分享页跳转带入的 previous_page 参数
      await web.loadRequest(Uri.parse('https://www.douyin.com/video/$id'));
    } catch (e) {
      _fail('页面加载失败：$e');
    }
  }

  void _scheduleProbe() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 1500), () {
      if (_stage == ParseStage.loading) {
        _runProbe();
      }
    });
  }

  Future<void> _runProbe() async {
    if (_probeStarted) return;
    final seq = _seq;
    _probeStarted = true;
    _stage = ParseStage.parsing;
    notifyListeners();

    final id = _awemeId;
    if (id == null) {
      _fail('缺少视频 ID');
      return;
    }

    // 逐层尝试：用页面自带的签名器（byted_acrawler.frontierSign）给请求加 X-Bogus。
    // 裸请求不带签名必然 403，所以每层都是「注入 JS → 取签名 → fetch」。
    final desktopUa = DouyinParser.userAgent;
    final nativeUa = await WebViewEnv.defaultUserAgent();
    final attempts = <({String url, String ua})>[
      (url: 'https://www.douyin.com/video/$id', ua: desktopUa),
      (url: 'https://www.douyin.com/video/$id', ua: nativeUa ?? desktopUa),
      (url: 'https://www.iesdouyin.com/share/video/$id/', ua: desktopUa),
    ];

    for (var i = 0; i < attempts.length; i++) {
      final attempt = attempts[i];
      final no = i + 1;
      try {
        await web.setUserAgent(attempt.ua);
      } catch (_) {}
      if (i > 0) {
        // 换 URL / 换 UA 后必须重新加载页面才会生效
        try {
          await web.loadRequest(Uri.parse(attempt.url));
          await Future.delayed(const Duration(milliseconds: 1800));
        } catch (_) {}
      }
      final startedAt = DateTime.now();
      try {
        Map<String, dynamic>? data;
        var note = '';
        // 页面加载后 UIFID / 签名器都要几秒才就绪，先给页面一点时间
        await Future.delayed(const Duration(milliseconds: 1500));
        // 页面只负责同步算签名；HTTP 走 Dart，避开「隐藏 WebView 里 fetch 永久挂起」
        for (var round = 0; round < 12 && data == null; round++) {
          final result = await DouyinParser.fetchDetail(
            awemeId: id,
            ua: attempt.ua,
            sign: (url) => _readJs(DouyinParser.signJs(url)),
            cookieProvider: () async {
              final native =
                  (await WebViewEnv.cookies(DouyinParser.referer)) ?? '';
              if (DouyinParser.extractCookieRaw(native, 'UIFID').isNotEmpty) {
                return native;
              }
              // 原生 CookieManager 没读到 UIFID 时，从页面 document.cookie 补
              final doc = await _readJs('document.cookie');
              final uifid = DouyinParser.extractCookieRaw(doc, 'UIFID');
              if (uifid.isEmpty) return native;
              return native.isEmpty ? 'UIFID=$uifid' : '$native; UIFID=$uifid';
            },
          );
          data = result.$1;
          note = result.$2;
          if (data == null) {
            final wait = note.contains('no_uifid') ? 800 : 600;
            await Future.delayed(Duration(milliseconds: wait));
          }
        }
        final elapsed = DateTime.now().difference(startedAt).inMilliseconds;
        await DiagLog.write('douyin_diag.log', [
          'attempt=$no note=$note ua=${_short(attempt.ua, 48)} url=${attempt.url}',
          'elapsed=${elapsed}ms result=${_short(data == null ? '' : jsonEncode(data), 260)}',
        ]);
        if (data == null) {
          if (no < attempts.length) continue;
          final url = await web.currentUrl() ?? '';
          _fail('解析超时：页面未返回数据（当前页面：${_short(url, 70)}）');
          return;
        }
        final error = data['error'];
        if (error != null) {
          if (no < attempts.length) continue;
          final body = '${data['body'] ?? ''}'.trim();
          _fail(body.isEmpty ? '接口返回异常：$error' : '接口返回异常：$body');
          return;
        }
        if (seq != _seq) return;
        final parsed = ParseResult.fromDouyin(data);
        if (parsed.videoUrls.isEmpty && parsed.imageUrls.isEmpty) {
          _fail('没有拿到视频或图片地址');
          return;
        }
        _result = parsed;
        _stage = ParseStage.done;
        _timeout?.cancel();
        notifyListeners();
        return;
      } catch (e) {
        await DiagLog.write('douyin_diag.log', ['attempt=$no throw $e']);
        if (no < attempts.length) continue;
        _fail('解析失败：$e');
        return;
      }
    }
  }

  static String _short(String text, int max) =>
      text.length > max ? text.substring(0, max) : text;

  /// 读一段页面 JS 的字符串结果（失败或空返回空串）
  Future<String> _readJs(String script) async {
    try {
      final raw = await web.runJavaScriptReturningResult(script);
      var text = raw.toString();
      if (text.isEmpty || text == '""' || text == 'null') return '';
      if (text.startsWith('"') && text.endsWith('"')) {
        final decoded = jsonDecode(text);
        return decoded is String ? decoded : '';
      }
      return text;
    } catch (_) {
      return '';
    }
  }

  Future<void> _parseBilibili(String input, int seq) async {
    _timeout = Timer(const Duration(seconds: 30), () {
      if (busy) _fail('B 站解析超时，请检查网络后重试');
    });
    try {
      final parsed = await BilibiliParser.parse(input);
      if (seq != _seq) return;
      if (parsed.videoUrls.isEmpty) {
        _fail('没有拿到 B 站播放地址');
        return;
      }
      _result = parsed;
      _stage = ParseStage.done;
      _timeout?.cancel();
      notifyListeners();
    } catch (e) {
      if (seq != _seq) return;
      final text = e.toString();
      final message =
          text.startsWith('Exception: ') ? text.substring(11) : text;
      _fail(message.startsWith('B 站') ? message : 'B 站解析失败：$message');
    }
  }

  Future<void> _parseKuaishou(String input, int seq) async {
    _timeout = Timer(const Duration(seconds: 30), () {
      if (busy) _fail('快手解析超时，请检查网络后重试');
    });
    try {
      final parsed = await KuaishouParser.parse(input);
      if (seq != _seq) return;
      if (parsed.videoUrls.isEmpty) {
        _fail('没有拿到快手视频地址');
        return;
      }
      _result = parsed;
      _stage = ParseStage.done;
      _timeout?.cancel();
      notifyListeners();
    } catch (e) {
      if (seq != _seq) return;
      final text = e.toString();
      final message =
          text.startsWith('Exception: ') ? text.substring(11) : text;
      _fail(message.startsWith('快手') ? message : '快手解析失败：$message');
    }
  }

  /// 小红书：WebView 被平台安全拦截（404/sec_），暂不支持
  Future<void> _parseXiaohongshu(String input) async {
    _fail('小红书暂不支持：WebView 被平台安全拦截，可在小红书 App 内直接观看');
  }

  void cancel() {
    _seq++;
    _debounce?.cancel();
    _timeout?.cancel();
    _stage = ParseStage.idle;
    _result = null;
    _error = null;
    notifyListeners();
  }

  void _fail(String message) {
    _timeout?.cancel();
    _stage = ParseStage.error;
    _error = message;
    notifyListeners();
  }

  @override
  void dispose() {
    _seq++;
    _debounce?.cancel();
    _timeout?.cancel();
    super.dispose();
  }
}