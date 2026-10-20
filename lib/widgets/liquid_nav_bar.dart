import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_palette.dart';

/// 单个导航项：常态图标 + 激活图标 + 文字
class LiquidNavItem {
  const LiquidNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
}

/// 液态形变底部导航。
///
/// 选中指示器不是"点亮某一格"，而是一枚会移动的液态胶囊：
/// - 位移用 420ms easeOutCubic 插值，连续点击可中途接续，不会跳回起点
/// - 移动过程按 sin(π·t) 拉伸：宽度增长 20%，**拖尾端圆角收窄**、前端保持圆润
/// - 落位时形变归零、回弹成标准胶囊
/// - 前端带一颗随速度放大的青绿光点
///
/// 相比静态底色方案，切换有明确的"从哪来、到哪去"的空间感。
class LiquidNavBar extends StatefulWidget {
  const LiquidNavBar({
    super.key,
    required this.items,
    required this.index,
    required this.onChanged,
    this.height = 46,
  });

  final List<LiquidNavItem> items;
  final int index;
  final ValueChanged<int> onChanged;
  final double height;

  @override
  State<LiquidNavBar> createState() => _LiquidNavBarState();
}

class _LiquidNavBarState extends State<LiquidNavBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late double _from;
  late double _to;

  @override
  void initState() {
    super.initState();
    _from = _to = widget.index.toDouble();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
      value: 1,
    );
  }

  @override
  void didUpdateWidget(covariant LiquidNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      // 从当前插值位置起跳，连续切换也顺滑
      _from = _position;
      _to = widget.index.toDouble();
      _controller.forward(from: 0);
    }
  }

  double get _position {
    if (!_controller.isAnimating) return _to;
    final eased = Curves.easeOutCubic.transform(_controller.value);
    return _from + (_to - _from) * eased;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SizedBox(
      height: widget.height,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _LiquidIndicatorPainter(
                animation: _controller,
                from: _from,
                to: _to,
                count: widget.items.length,
                accent: p.accent,
                accent2: p.accent2,
              ),
            ),
          ),
          Row(
            children: [
              for (var i = 0; i < widget.items.length; i++)
                Expanded(
                  child: _NavTab(
                    item: widget.items[i],
                    selected: i == widget.index,
                    onTap: () {
                      if (i == widget.index) return;
                      HapticFeedback.selectionClick();
                      widget.onChanged(i);
                    },
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  const _NavTab({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final LiquidNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = selected ? p.accent : p.faint;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedScale(
            scale: selected ? 1.12 : 1.0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutBack,
            child: Icon(
              selected ? item.activeIcon : item.icon,
              size: 19,
              color: color,
            ),
          ),
          const SizedBox(height: 3),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(
              fontSize: 10,
              height: 1.2,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: color,
            ),
            child: Text(item.label),
          ),
        ],
      ),
    );
  }
}

class _LiquidIndicatorPainter extends CustomPainter {
  _LiquidIndicatorPainter({
    required this.animation,
    required this.from,
    required this.to,
    required this.count,
    required this.accent,
    required this.accent2,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final double from;
  final double to;
  final int count;
  final Color accent;
  final Color accent2;

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    final eased = Curves.easeOutCubic.transform(t);
    final position = from + (to - from) * eased;

    // 起止速度为 0 → 形变为 0；中段最大
    final stretch = math.sin(math.pi * t).clamp(0.0, 1.0).toDouble();
    final dir = to >= from ? 1.0 : -1.0;

    const inset = 3.0;
    final slot = size.width / count;
    final baseW = slot - inset * 2;
    final h = size.height - inset * 2;
    final baseX = position * slot + inset;

    // 拖尾向后延伸
    final stretchPx = baseW * 0.20 * stretch;
    final x = dir > 0 ? baseX - stretchPx : baseX;
    final w = baseW + stretchPx;

    final rect = Rect.fromLTWH(x, inset, w, h);
    final r = h / 2;
    final tail = r * (1 - 0.55 * stretch);

    final radius = dir > 0
        ? BorderRadius.only(
            topLeft: Radius.circular(tail),
            bottomLeft: Radius.circular(tail),
            topRight: Radius.circular(r),
            bottomRight: Radius.circular(r),
          )
        : BorderRadius.only(
            topLeft: Radius.circular(r),
            bottomLeft: Radius.circular(r),
            topRight: Radius.circular(tail),
            bottomRight: Radius.circular(tail),
          );
    final rrect = radius.toRRect(rect);

    // 液态主体：青绿渐变 + 透明度随拉伸略增强
    final body = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          accent.withOpacity(0.22 + 0.06 * stretch),
          accent2.withOpacity(0.13 + 0.05 * stretch),
        ],
      ).createShader(rect);
    canvas.drawRRect(rrect, body);

    // 内描边，勾出液体边缘
    canvas.drawRRect(
      rrect.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = accent.withOpacity(0.28 + 0.22 * stretch),
    );

    // 顶部高光弧，让胶囊有厚度
    final glossRect = Rect.fromLTWH(rect.left + 6, rect.top + 2.5, rect.width - 12, h * 0.45);
    canvas.drawRRect(
      RRect.fromRectAndRadius(glossRect, Radius.circular(h * 0.22)),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withOpacity(0.06),
            Colors.white.withOpacity(0.0),
          ],
        ).createShader(glossRect),
    );

    // 前端光点（随速度放大、提亮）
    final dotCenter = Offset(dir > 0 ? rect.right - 7 : rect.left + 7, rect.center.dy);
    final dotR = 2.0 + 1.6 * stretch;
    canvas.drawCircle(
      dotCenter,
      dotR * 2.8,
      Paint()
        ..shader = RadialGradient(
          colors: [
            accent.withOpacity(0.20 + 0.25 * stretch),
            accent.withOpacity(0),
          ],
        ).createShader(Rect.fromCircle(center: dotCenter, radius: dotR * 2.8)),
    );
    canvas.drawCircle(
      dotCenter,
      dotR,
      Paint()..color = accent.withOpacity(0.45 + 0.40 * stretch),
    );
  }

  @override
  bool shouldRepaint(covariant _LiquidIndicatorPainter oldDelegate) =>
      oldDelegate.from != from ||
      oldDelegate.to != to ||
      oldDelegate.count != count ||
      oldDelegate.accent != accent ||
      oldDelegate.accent2 != accent2;
}