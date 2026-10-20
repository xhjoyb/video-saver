import 'package:flutter/foundation.dart';

/// 轻量全局事件（避免引入状态管理库）：
/// - tabIndex：底部导航当前页，任何页面都可切换
/// - pendingParse：待解析的链接/ID，解析页监听后自动填入并解析
class AppEvents {
  AppEvents._();

  static final ValueNotifier<int> tabIndex = ValueNotifier<int>(0);
  static final ValueNotifier<String?> pendingParse = ValueNotifier<String?>(null);
}