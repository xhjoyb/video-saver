import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../parser/xiaohongshu_parser.dart';
import '../theme/app_palette.dart';

/// 小红书登录页：用 WebView 打开官方登录页，cookie 留在本机 WebView 里，
/// 解析流程直接复用（等同浏览器登录，凭据不经过应用代码）。
class XhsLoginScreen extends StatefulWidget {
  const XhsLoginScreen({super.key});

  @override
  State<XhsLoginScreen> createState() => _XhsLoginScreenState();
}

class _XhsLoginScreenState extends State<XhsLoginScreen> {
  late final WebViewController _web;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(XiaohongshuParser.userAgent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (value) {
            if (!mounted) return;
            setState(() => _progress = value / 100);
          },
          onPageFinished: (url) {
            if (!mounted) return;
            setState(() => _progress = 1);
          },
        ),
      )
      ..loadRequest(Uri.parse('https://www.xiaohongshu.com/login'));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.bgTop,
      appBar: AppBar(
        backgroundColor: p.bgTop,
        foregroundColor: p.text,
        elevation: 0,
        title: const Text('登录小红书'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('完成', style: TextStyle(color: p.accent)),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_progress < 1)
            LinearProgressIndicator(
              value: _progress,
              minHeight: 2,
              backgroundColor: p.cardAlt,
              valueColor: AlwaysStoppedAnimation(p.accent),
            ),
          Expanded(child: WebViewWidget(controller: _web)),
        ],
      ),
    );
  }
}