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
  bool _checking = false;

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

  /// cookie 不可读，只能用页面内 JS 间接判断：
  /// 1) `document.cookie` 能看到 web_session；2) 已经离开登录页
  Future<void> _finish() async {
    if (_checking) return;
    setState(() => _checking = true);
    var loggedIn = false;
    try {
      final raw = await _web.runJavaScriptReturningResult(
        "(function(){try{"
        "var c=document.cookie||'';var p=location.pathname||'';"
        "if(c.indexOf('web_session')>=0)return '1';"
        "if(p.indexOf('/login')<0&&p.indexOf('/website-login')<0)return '2';"
        "return '';}catch(e){return '';}})()",
      );
      final value = raw.toString().replaceAll('"', '');
      loggedIn = value == '1' || value == '2';
    } catch (_) {}
    if (!mounted) return;
    Navigator.pop(context, loggedIn);
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
            onPressed: _checking ? null : _finish,
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