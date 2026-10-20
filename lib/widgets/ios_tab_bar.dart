import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_palette.dart';

/// 单个 Tab：常态图标 + 激活图标 + 文字
class IosTabItem {
  const IosTabItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
}

/// iOS 风格底部 Tab Bar。
///
/// 特征（对齐 iOS 系统 Tab Bar）：
/// - 贴底通栏，不浮起、不圆角、无左右留白
/// - 毛玻璃背景（BackdropFilter 24px）+ 半透明材质层
/// - 顶部 0.6px hairline 分隔线（深色模式白 7%、浅色模式黑 9%）
/// - 高度 49（iOS 标准）+ 底部安全区
/// - 图标 23 / 文字 10，选中青绿、未选中灰
/// - 选中态用 filled 图标交叉淡化切换（160ms），**没有滑块/胶囊/光点**
/// - 按下时整体压暗到 55%（iOS 的按压反馈），并触发选择触觉
class IosTabBar extends StatelessWidget {
  const IosTabBar({
    super.key,
    required this.items,
    required this.index,
    required this.onChanged,
  });

  final List<IosTabItem> items;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isDark = p.isDark;

    final material = isDark
        ? const Color(0xFF101018).withOpacity(0.70)
        : const Color(0xFFFDFDFE).withOpacity(0.86);
    final hairline = isDark
        ? Colors.white.withOpacity(0.07)
        : Colors.black.withOpacity(0.09);

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: material,
            border: Border(top: BorderSide(color: hairline, width: 0.6)),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 49,
              child: Row(
                children: [
                  for (var i = 0; i < items.length; i++)
                    Expanded(
                      child: _IosTab(
                        item: items[i],
                        selected: i == index,
                        onTap: () => onChanged(i),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IosTab extends StatefulWidget {
  const _IosTab({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final IosTabItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_IosTab> createState() => _IosTabState();
}

class _IosTabState extends State<_IosTab> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final selected = widget.selected;
    final color = selected ? p.accent : p.faint;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: AnimatedOpacity(
        opacity: _pressed ? 0.55 : 1,
        duration: const Duration(milliseconds: 90),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              child: Icon(
                selected ? widget.item.activeIcon : widget.item.icon,
                key: ValueKey<bool>(selected),
                size: 23,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              widget.item.label,
              style: TextStyle(
                fontSize: 10,
                height: 1.1,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}