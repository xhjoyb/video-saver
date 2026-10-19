import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../theme/app_palette.dart';
import '../theme/app_theme.dart';

/// 开发者探针：用真实 WebView 打开抖音分享页，探查能否拿到视频地址/接口数据。
/// 仅用于验证解析链路，不对外暴露。
class ParseProbeScreen extends StatefulWidget {
  const ParseProbeScreen({
    super.key,
    this.initialUrl = 'https://v.douyin.com/ZIzGpt-k4Yk/',
  });

  final String initialUrl;

  @override
  State<ParseProbeScreen> createState() => _ParseProbeScreenState();
}

class _ParseProbeScreenState extends State<ParseProbeScreen> {
  late final WebViewController _web;
  String _status = '准备中';
  Map<String, dynamic> _result = const {};

  /// 页面里能拿到的全部线索：video 元素、资源请求、_ROUTER_DATA
  static const String _probeJs = r'''
(function () {
  try {
    var v = document.querySelector('video');
    var res = performance.getEntriesByType('resource')
      .map(function (e) { return e.name; })
      .filter(function (n) {
        return n.indexOf('aweme') >= 0 || n.indexOf('douyin') >= 0 || n.indexOf('video') >= 0;
      })
      .slice(0, 60);
    var router = '';
    try {
      if (window._ROUTER_DATA) router = JSON.stringify(window._ROUTER_DATA).slice(0, 6000);
    } catch (e) { router = 'router-stringify-fail'; }
    return JSON.stringify({
      url: location.href,
      title: document.title,
      videoSrc: v ? (v.currentSrc || v.src || '') : '',
      sources: Array.prototype.map.call(document.querySelectorAll('video source'), function (s) { return s.src; }),
      resources: res,
      router: router
    });
  } catch (e) {
    return JSON.stringify({ error: String(e) });
  }
})()
''';

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            if (mounted) setState(() => _status = '加载中… $url');
          },
          onPageFinished: (url) async {
            if (!mounted) return;
            setState(() => _status = '页面已加载，等待 JS 渲染…');
            await Future.delayed(const Duration(seconds: 3));
            if (!mounted) return;
            await _probe();
            await Future.delayed(const Duration(seconds: 3));
            if (!mounted) return;
            await _probe();
          },
          onWebResourceError: (e) {
            if (mounted) setState(() => _status = '加载失败：${e.description}');
          },
        ),
      );
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _result = const {};
      _status = '开始加载 ${widget.initialUrl}';
    });
    try {
      await _web.loadRequest(Uri.parse(widget.initialUrl));
    } catch (e) {
      if (mounted) setState(() => _status = '加载异常：$e');
    }
  }

  Future<void> _probe() async {
    try {
      final raw = await _web.runJavaScriptReturningResult(_probeJs);
      var text = raw.toString();
      if (text.startsWith('"') && text.endsWith('"')) {
        text = jsonDecode(text) as String;
      }
      final decoded = jsonDecode(text) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _result = decoded;
        final now = DateTime.now();
        _status =
            '探测完成 ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
      });
    } catch (e) {
      if (mounted) setState(() => _status = '探测失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final videoSrc = (_result['videoSrc'] as String?) ?? '';
    final sources = (_result['sources'] as List?)?.cast<String>() ?? const <String>[];
    final resources = (_result['resources'] as List?)?.cast<String>() ?? const <String>[];
    final router = (_result['router'] as String?) ?? '';

    return Scaffold(
      backgroundColor: p.bgBottom,
      appBar: AppBar(
        title: const Text('解析探针'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 320,
            child: WebViewWidget(controller: _web),
          ),
          Container(height: 1, color: p.border),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
              children: [
                Text(_status, style: AppText.body(context)),
                const SizedBox(height: 8),
                _kv(context, 'videoSrc', videoSrc.isEmpty ? '(空)' : videoSrc),
                if (sources.isNotEmpty) _kv(context, 'sources', sources.join('\n')),
                if (resources.isNotEmpty)
                  _kv(context, 'resources', resources.take(20).join('\n')),
                if (router.isNotEmpty) _kv(context, 'router', router),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(BuildContext context, String key, String value) {
    final p = context.palette;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: p.cardAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(key, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: p.accent)),
          const SizedBox(height: 4),
          SelectableText(value, style: TextStyle(fontSize: 11.5, height: 1.45, color: p.dim)),
        ],
      ),
    );
  }
}