import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../parser/bilibili_parser.dart';
import '../theme/app_palette.dart';

/// B 站登录页：WebView 打开官方登录页。
/// 点「完成」后由设置页通过原生 CookieManager 读取并保存 cookie。
class BilibiliLoginScreen extends StatefulWidget {
  const BilibiliLoginScreen({super.key});

  @override
  State<BilibiliLoginScreen> createState() => _BilibiliLoginScreenState();
}

class _BilibiliLoginScreenState extends State<BilibiliLoginScreen> {
  late final WebViewController _web;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(BilibiliParser.userAgent)
      ..setNavigationDelegate(
        NavigationDelegate(
          // 阻止 bilibili:// 等自定义 scheme 唤起，避免整页报错
          onNavigationRequest: (request) {
            final url = request.url;
            if (!url.startsWith('http://') && !url.startsWith('https://')) {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
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
      ..loadRequest(Uri.parse('https://passport.bilibili.com/login'));
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
        title: const Text('登录 B 站'),
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