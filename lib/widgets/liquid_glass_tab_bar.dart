import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_palette.dart';

/// 单个 Tab：常态图标 + 激活图标 + 文字
class LiquidGlassTabItem {
  const LiquidGlassTabItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
}

/// iOS 26「液态玻璃（Liquid Glass）」风格底部导航。
///
/// 三层结构：
/// 1. **玻璃外壳**：`BackdropFilter` 30px 模糊 + 白/黑低透明度渐变 + 1px 亮边 + 外投影，
///    让底栏像一块悬浮的磨砂玻璃，内容从后面滚过时透出模糊色块。
/// 2. **液态指示器**：选中块沿 tab 滑动，`sin(π·t)` 驱动体积变化——
///    宽度拉伸 18%、拖尾端圆角收窄、前端保持圆润，落位回弹成胶囊；
///    内部叠三层（色调渐变 / 玻璃高光 / 底部厚度阴影）+ 亮边 + 顶部镜面高光带 + 前端光点。
/// 3. **内容层**：图标 22 + 文字 10，选中 filled 图标 + 青绿 + 轻发光。
///
/// 刻意保留的克制：不做整条栏的形变、不做弹跳位移、不做彩色光效泛滥。
class LiquidGlassTabBar extends StatefulWidget {
  const LiquidGlassTabBar({
    super.key,
    required this.items,
    required this.index,
    required this.onChanged,
  });

  final List<LiquidGlassTabItem> items;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  State<LiquidGlassTabBar> createState() => _LiquidGlassTabBarState();
}

class _LiquidGlassTabBarState extends State<LiquidGlassTabBar>
    with SingleTickerProviderStateMixin {
  static const double _height = 62;
  static const double _radius = 28;

  late final AnimationController _controller;
  late double _from;
  late double _to;

  @override
  void initState() {
    super.initState();
    _from = _to = widget.index.toDouble();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 460),
      value: 1,
    );
  }

  @override
  void didUpdateWidget(covariant LiquidGlassTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      // 从当前插值位置起跳，连续切换不跳回起点
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
    final isDark = p.isDark;

    final shellGradient = isDark
        ? [
            Colors.white.withOpacity(0.10),
            Colors.white.withOpacity(0.04),
            Colors.black.withOpacity(0.06),
          ]
        : [
            Colors.white.withOpacity(0.72),
            Colors.white.withOpacity(0.48),
            Colors.white.withOpacity(0.62),
          ];
    final shellBorder = isDark
        ? Colors.white.withOpacity(0.16)
        : Colors.black.withOpacity(0.06);

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_radius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.42 : 0.14),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_radius),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_radius),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: shellGradient,
                  stops: const [0.0, 0.5, 1.0],
                ),
                border: Border.all(color: shellBorder, width: 1),
              ),
              child: SizedBox(
                height: _height,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _GlassIndicatorPainter(
                          animation: _controller,
                          from: _from,
                          to: _to,
                          count: widget.items.length,
                          accent: p.accent,
                          accent2: p.accent2,
                          isDark: isDark,
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        for (var i = 0; i < widget.items.length; i++)
                          Expanded(
                            child: _GlassTab(
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
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassTab extends StatefulWidget {
  const _GlassTab({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final LiquidGlassTabItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_GlassTab> createState() => _GlassTabState();
}

class _GlassTabState extends State<_GlassTab> {
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
        opacity: _pressed ? 0.6 : 1,
        duration: const Duration(milliseconds: 90),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Icon(
                selected ? widget.item.activeIcon : widget.item.icon,
                key: ValueKey<bool>(selected),
                size: 22,
                color: color,
                shadows: selected
                    ? [
                        Shadow(
                          color: p.accent.withOpacity(0.45),
                          blurRadius: 10,
                        ),
                      ]
                    : null,
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

class _GlassIndicatorPainter extends CustomPainter {
  _GlassIndicatorPainter({
    required this.animation,
    required this.from,
    required this.to,
    required this.count,
    required this.accent,
    required this.accent2,
    required this.isDark,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final double from;
  final double to;
  final int count;
  final Color accent;
  final Color accent2;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    final eased = Curves.easeOutCubic.transform(t);
    final position = from + (to - from) * eased;

    // 起止为 0，中段最大 → 静止是标准胶囊，移动中才形变
    final stretch = math.sin(math.pi * t).clamp(0.0, 1.0).toDouble();
    final dir = to >= from ? 1.0 : -1.0;

    const insetX = 6.0;
    const insetY = 8.0;
    final slot = size.width / count;
    final baseW = slot - insetX * 2;
    final h = size.height - insetY * 2;
    final baseX = position * slot + insetX;

    // 拖尾向后延伸
    final stretchPx = baseW * 0.18 * stretch;
    final x = dir > 0 ? baseX - stretchPx : baseX;
    final w = baseW + stretchPx;

    final rect = Rect.fromLTWH(x, insetY, w, h);
    final r = h / 2;
    final tail = r * (1 - 0.58 * stretch);

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

    // 1) 玻璃底色（白/黑随主题反向）
    final baseTop = isDark ? 0.20 : 0.85;
    final baseBottom = isDark ? 0.06 : 0.52;
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(baseTop),
            Colors.white.withOpacity(baseBottom),
          ],
        ).createShader(rect),
    );

    // 2) 青绿染色，让选中块带品牌色
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            accent.withOpacity(0.20 + 0.10 * stretch),
            accent2.withOpacity(0.10 + 0.08 * stretch),
          ],
        ).createShader(rect),
    );

    // 3) 底部厚度阴影，制造玻璃体积感
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withOpacity(0),
            Colors.black.withOpacity(isDark ? 0.18 : 0.06),
          ],
        ).createShader(rect),
    );

    // 4) 亮边：顶部更亮（模拟受光面）
    canvas.drawRRect(
      rrect.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withOpacity(isDark ? 0.50 : 0.90),
            Colors.white.withOpacity(isDark ? 0.14 : 0.40),
          ],
        ).createShader(rect),
    );

    // 5) 顶部镜面高光带
    final gloss = Rect.fromLTWH(
      rect.left + 7,
      rect.top + 2.5,
      math.max(0, rect.width - 14),
      h * 0.40,
    );
    if (gloss.width > 4) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(gloss, Radius.circular(gloss.height / 2)),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withOpacity(isDark ? 0.22 : 0.55),
              Colors.white.withOpacity(0),
            ],
          ).createShader(gloss),
      );
    }

    // 6) 前端流珠：随速度放大提亮
    final dot = Offset(
      dir > 0 ? rect.right - 8 : rect.left + 8,
      rect.center.dy,
    );
    final dotR = 2.0 + 1.4 * stretch;
    canvas.drawCircle(
      dot,
      dotR * 3.0,
      Paint()
        ..shader = RadialGradient(
          colors: [
            accent.withOpacity(0.22 + 0.26 * stretch),
            accent.withOpacity(0),
          ],
        ).createShader(Rect.fromCircle(center: dot, radius: dotR * 3.0)),
    );
    canvas.drawCircle(
      dot,
      dotR,
      Paint()
        ..color = Colors.white.withOpacity(isDark ? 0.85 : 0.95),
    );
  }

  @override
  bool shouldRepaint(covariant _GlassIndicatorPainter oldDelegate) =>
      oldDelegate.from != from ||
      oldDelegate.to != to ||
      oldDelegate.count != count ||
      oldDelegate.accent != accent ||
      oldDelegate.accent2 != accent2 ||
      oldDelegate.isDark != isDark;
}