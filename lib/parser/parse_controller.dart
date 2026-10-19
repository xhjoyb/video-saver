import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'douyin_parser.dart';
import 'parse_result.dart';

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
          onPageFinished: (url) {
            if (_stage != ParseStage.loading) return;
            _scheduleProbe();
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
    _result = null;
    _error = null;
    _stage = ParseStage.resolving;
    notifyListeners();

    final id = await DouyinParser.resolveAwemeId(input);
    if (id == null) {
      _fail('没有识别到抖音视频链接');
      return;
    }
    _awemeId = id;
    _stage = ParseStage.loading;
    notifyListeners();

    _timeout = Timer(const Duration(seconds: 22), () {
      if (busy) _fail('解析超时，请检查网络后重试');
    });

    try {
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
    _probeStarted = true;
    _stage = ParseStage.parsing;
    notifyListeners();

    final id = _awemeId;
    if (id == null) {
      _fail('缺少视频 ID');
      return;
    }
    try {
      await web.runJavaScriptReturningResult(DouyinParser.detailJs(id));
      final data = await _waitResult();
      if (data == null) {
        _fail('解析超时：页面未返回数据');
        return;
      }
      if (data['error'] != null) {
        _fail('接口返回异常：${data['error']}');
        return;
      }
      final parsed = ParseResult.fromDouyin(data);
      if (parsed.videoUrls.isEmpty) {
        _fail(parsed.imageUrls.isNotEmpty ? '这是图集，暂不支持下载' : '没有拿到视频地址');
        return;
      }
      _result = parsed;
      _stage = ParseStage.done;
      _timeout?.cancel();
      notifyListeners();
    } catch (e) {
      _fail('解析失败：$e');
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