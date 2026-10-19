import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../theme/app_palette.dart';
import '../theme/app_theme.dart';

/// 开发者探针：两阶段验证 WebView 能否加载抖音分享页，并抓 cookie / 视频地址。
/// 结果写 /sdcard/Android/data/<pkg>/files/probe_result.json
class ParseProbeScreen extends StatefulWidget {
  const ParseProbeScreen({super.key});

  @override
  State<ParseProbeScreen> createState() => _ParseProbeScreenState();
}

class _ParseProbeScreenState extends State<ParseProbeScreen> {
  static const String targetUrl =
      'https://www.iesdouyin.com/share/video/7695215729926784320/';
  static const String baselineUrl = 'https://example.com/';
  static const String probeUa =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  late final WebViewController _web;
  String _stage = 'baseline';

  final Map<String, dynamic> _data = <String, dynamic>{
    'stage': 'init',
    'baseline': <String, dynamic>{},
    'douyin': <String, dynamic>{},
    'cookies': <String, dynamic>{},
  };

  static const String _js = r'''
(function () {
  try {
    var v = document.querySelector('video');
    var res = performance.getEntriesByType('resource')
      .map(function (e) { return e.name; })
      .filter(function (n) { return n.indexOf('aweme') >= 0 || n.indexOf('douyin') >= 0; })
      .slice(0, 40);
    return JSON.stringify({
      title: document.title,
      href: location.href,
      docCookieLen: (document.cookie || '').length,
      videoSrc: v ? (v.currentSrc || v.src || '') : '',
      sources: Array.prototype.map.call(document.querySelectorAll('video source'), function (s) { return s.src; }),
      resources: res,
      router: window._ROUTER_DATA ? JSON.stringify(window._ROUTER_DATA).slice(0, 2000) : ''
    });
  } catch (e) { return JSON.stringify({ jsError: String(e) }); }
})()
''';

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(probeUa)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            _merge(_stage, {'startedUrl': url});
          },
          onPageFinished: (url) async {
            _merge(_stage, {'ok': true, 'finishedUrl': url});
            if (_stage == 'baseline') {
              _stage = 'douyin';
              _data['stage'] = 'douyin_loading';
              await _dump();
              await _web.loadRequest(Uri.parse(targetUrl));
              return;
            }
            await _probe();
            await Future.delayed(const Duration(milliseconds: 1200));
            await _probe();
            await _readCookies();
            _data['stage'] = 'done';
            await _dump();
          },
          onWebResourceError: (e) async {
            _merge(_stage, {
              'ok': false,
              'errorCode': e.errorCode,
              'errorDesc': e.description,
              'isForMainFrame': e.isForMainFrame,
            });
            if (_stage == 'baseline') {
              _stage = 'douyin';
              _data['stage'] = 'douyin_loading';
              await _dump();
              await _web.loadRequest(Uri.parse(targetUrl));
            }
          },
        ),
      );
    _web.loadRequest(Uri.parse(baselineUrl));
    _dump();
  }

  void _merge(String stage, Map<String, dynamic> patch) {
    final current = Map<String, dynamic>.from(_data[stage] as Map);
    current.addAll(patch);
    _data[stage] = current;
    _dump();
    if (mounted) setState(() {});
  }

  Future<void> _probe() async {
    try {
      final raw = await _web.runJavaScriptReturningResult(_js);
      var text = raw.toString();
      if (text.startsWith('"') && text.endsWith('"')) {
        text = jsonDecode(text) as String;
      }
      final decoded = jsonDecode(text) as Map<String, dynamic>;
      _merge('douyin', decoded);
    } catch (e) {
      _merge('douyin', {'probeError': e.toString()});
    }
  }

  Future<void> _readCookies() async {
    try {
      final manager = WebCookieManager(_web);
      final cookies = <String, String>{};
      for (final url in const ['https://www.douyin.com', 'https://www.iesdouyin.com']) {
        try {
          final list = await manager.getCookies(Uri.parse(url));
          for (final c in list) {
            cookies[c.name] = c.value;
          }
        } catch (_) {}
      }
      final keep = <String, String>{};
      for (final key in const [
        'uifid',
        'UIFID',
        'ttwid',
        'msToken',
        '__ac_nonce',
        's_v_web_id',
        'odinzx',
      ]) {
        if (cookies.containsKey(key)) keep[key] = cookies[key]!;
      }
      _data['cookies'] = keep;
      _data['cookieTotal'] = cookies.length;
      _data['cookieNames'] = cookies.keys.take(30).toList();
      await _dump();
    } catch (e) {
      _data['cookieError'] = e.toString();
      await _dump();
    }
  }

  Future<void> _dump() async {
    try {
      final dir = await getExternalStorageDirectory();
      if (dir != null) {
        await dir.create(recursive: true);
        await File('${dir.path}/probe_result.json')
            .writeAsString(jsonEncode(_data));
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.bgBottom,
      appBar: AppBar(
        title: const Text('解析探针'),
        actions: [
          IconButton(
            onPressed: () {
              setState(() {
                _stage = 'baseline';
                _data['stage'] = 'restart';
                _data['baseline'] = <String, dynamic>{};
                _data['douyin'] = <String, dynamic>{};
                _data['cookies'] = <String, dynamic>{};
              });
              _web.loadRequest(Uri.parse(baselineUrl));
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(height: 260, child: WebViewWidget(controller: _web)),
          Container(height: 1, color: p.border),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Text('stage: ${_data['stage']}', style: AppText.body(context)),
                const SizedBox(height: 8),
                SelectableText(
                  const JsonEncoder.withIndent('  ').convert(_data),
                  style: TextStyle(fontSize: 11, height: 1.4, color: p.dim),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}