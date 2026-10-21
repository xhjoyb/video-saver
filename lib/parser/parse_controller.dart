import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'bilibili_parser.dart';
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
      await _parseBilibili(input);
      return;
    }

    // 快手：移动分享页 SSR 直出 mp4，同样走纯 HTTP
    if (KuaishouParser.looksLike(input)) {
      await _parseKuaishou(input);
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

    _timeout = Timer(const Duration(seconds: 35), () {
      if (busy) _fail('解析超时，请检查网络后重试');
    });

    try {
      // 与探针一致：走分享页（会自动跳到 www.douyin.com/video/{id}）
      await web.loadRequest(
        Uri.parse('https://www.iesdouyin.com/share/video/$id/'),
      );
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
    _probeStarted = true;
    _stage = ParseStage.parsing;
    notifyListeners();

    final id = _awemeId;
    if (id == null) {
      _fail('缺少视频 ID');
      return;
    }
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        await web.runJavaScriptReturningResult(DouyinParser.detailJs(id));
        final data = await _waitResult();
        if (data == null) {
          if (attempt < 3) {
            await Future.delayed(const Duration(milliseconds: 900));
            continue;
          }
          _fail('解析超时：页面未返回数据');
          return;
        }
        if (data['error'] != null) {
          final body = '${data['body'] ?? ''}'.trim();
          if (attempt < 3) {
            // 首次常因页面 cookie / 签名未就绪被 Argus 拦截，稍候重试
            await Future.delayed(const Duration(milliseconds: 1200));
            continue;
          }
          _fail(body.isEmpty ? '接口返回异常：${data['error']}' : '接口返回异常：$body');
          return;
        }
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
        if (attempt < 3) {
          await Future.delayed(const Duration(milliseconds: 900));
          continue;
        }
        _fail('解析失败：$e');
        return;
      }
    }
  }

  Future<Map<String, dynamic>?> _waitResult() async {
    for (var i = 0; i < 18; i++) {
      await Future.delayed(const Duration(milliseconds: 400));
      try {
        final raw = await web.runJavaScriptReturningResult('window.__dyResult || ""');
        var text = raw.toString();
        if (text.isEmpty || text == '""') continue;
        if (text.startsWith('"') && text.endsWith('"')) {
          text = jsonDecode(text) as String;
        }
        if (text.isEmpty) continue;
        return jsonDecode(text) as Map<String, dynamic>;
      } catch (_) {
        // 单次读取失败继续轮询
      }
    }
    return null;
  }

  Future<void> _parseBilibili(String input) async {
    try {
      final parsed = await BilibiliParser.parse(input);
      if (parsed.videoUrls.isEmpty) {
        _fail('没有拿到 B 站播放地址');
        return;
      }
      _result = parsed;
      _stage = ParseStage.done;
      notifyListeners();
    } catch (e) {
      final text = e.toString();
      final message =
          text.startsWith('Exception: ') ? text.substring(11) : text;
      _fail(message.startsWith('B 站') ? message : 'B 站解析失败：$message');
    }
  }

  Future<void> _parseKuaishou(String input) async {
    try {
      final parsed = await KuaishouParser.parse(input);
      if (parsed.videoUrls.isEmpty) {
        _fail('没有拿到快手视频地址');
        return;
      }
      _result = parsed;
      _stage = ParseStage.done;
      notifyListeners();
    } catch (e) {
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

  void _fail(String message) {
    _timeout?.cancel();
    _stage = ParseStage.error;
    _error = message;
    notifyListeners();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _timeout?.cancel();
    super.dispose();
  }
}