import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../state/app_settings.dart';
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

/// iOS 26「液态玻璃」底部导航。
///
/// 交互：
/// - 点击切换（指示器 380ms 缓动滑过去）
/// - **水平拖动**：指示器跟手移动，松手按甩动速度投影落点，用弹簧吸附到最近一格
/// - 移动速度驱动形变：越快拉伸越长、拖尾圆角越尖；静止时是标准胶囊
///
/// 视觉：
/// - 外壳 = 强模糊 + 饱和度提升（模拟玻璃对背景色的「渗色」）+ 低透明度渐变 + 1px 亮边
/// - 指示器 = 近乎透明的白玻璃 + 极淡青绿染色 + 顶部镜面高光 + 受光边（顶亮底暗）
/// - **没有**白点/流珠/彩色光斑——纯玻璃，不发光
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
  static const double _radius = 30;
  static const double _saturation = 1.5;

  late final AnimationController _controller;
  late final ImageFilter _glassFilter;

  double _prev = 0;
  double _stretch = 0;
  double _dir = 1;
  double _slot = 1;
  bool _dragging = false;
  bool _syncing = false;
  bool _hapticEnabled = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController.unbounded(
      vsync: this,
      value: widget.index.toDouble(),
    );
    _prev = _controller.value;
    _controller.addListener(_onTick);
    _glassFilter = ImageFilter.compose(
      outer: ColorFilter.matrix(_saturationMatrix(_saturation)),
      inner: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
    );
  }

  static List<double> _saturationMatrix(double s) {
    const lumR = 0.2126;
    const lumG = 0.7152;
    const lumB = 0.0722;
    final sr = (1 - s) * lumR;
    final sg = (1 - s) * lumG;
    final sb = (1 - s) * lumB;
    return <double>[
      sr + s, sg, sb, 0, 0,
      sr, sg + s, sb, 0, 0,
      sr, sg, sb + s, 0, 0,
      0, 0, 0, 1, 0,
    ];
  }

  void _onTick() {
    final value = _controller.value;
    final delta = value - _prev;
    _prev = value;
    if (delta.abs() > 1e-4) {
      _dir = delta > 0 ? 1 : -1;
    }
    // 每帧位移 × 60 ≈ 每秒格数；映射到 0..1 的形变强度并做平滑
    final speed = (delta * 60).abs();
    final target = (speed / 2.6).clamp(0.0, 1.0).toDouble();
    _stretch += (target - _stretch) * 0.35;
  }

  void _animateTo(int index) {
    final target = index.toDouble();
    if ((_controller.value - target).abs() < 0.005) return;
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void didUpdateWidget(covariant LiquidGlassTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      if (_syncing) {
        _syncing = false;
        return;
      }
      if (!_dragging) _animateTo(widget.index);
    }
  }

  void _onDragStart(DragStartDetails _) {
    _dragging = true;
    _controller.stop();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_slot <= 0) return;
    final maxIndex = (widget.items.length - 1).toDouble();
    final next = (_controller.value + details.delta.dx / _slot)
        .clamp(0.0, maxIndex)
        .toDouble();
    _controller.value = next;
  }

  void _onDragEnd(DragEndDetails details) {
    _dragging = false;
    if (_slot <= 0) return;
    final maxIndex = widget.items.length - 1;
    final velocitySlots = details.velocity.pixelsPerSecond.dx / _slot;
    // 按甩动速度往前投影一点，轻扫即可越格
    final projected = _controller.value + velocitySlots * 0.09;
    final target = projected.round().clamp(0, maxIndex).toInt();

    _controller.animateWith(
      SpringSimulation(
        const SpringDescription(mass: 1, stiffness: 320, damping: 30),
        _controller.value,
        target.toDouble(),
        velocitySlots,
      ),
    );

    if (target != widget.index) {
      _syncing = true;
      if (_hapticEnabled) HapticFeedback.selectionClick();
      widget.onChanged(target);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTick);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isDark = p.isDark;
    _hapticEnabled = AppSettingsScope.of(context).haptic;

    final shellGradient = isDark
        ? [
            Colors.white.withOpacity(0.12),
            Colors.white.withOpacity(0.03),
            Colors.white.withOpacity(0.07),
          ]
        : [
            Colors.white.withOpacity(0.62),
            Colors.white.withOpacity(0.34),
            Colors.white.withOpacity(0.52),
          ];
    final shellBorder =
        isDark ? Colors.white.withOpacity(0.18) : Colors.black.withOpacity(0.05);

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_radius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.38 : 0.12),
              blurRadius: 26,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_radius),
          child: BackdropFilter(
            filter: _glassFilter,
            child: LayoutBuilder(
              builder: (context, constraints) {
                _slot = constraints.maxWidth / widget.items.length;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: _onDragStart,
                  onHorizontalDragUpdate: _onDragUpdate,
                  onHorizontalDragEnd: _onDragEnd,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(_radius),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: shellGradient,
                        stops: const [0.0, 0.48, 1.0],
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
                                stretchOf: () => _stretch,
                                dirOf: () => _dir,
                                draggingOf: () => _dragging,
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
                );
              },
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
    final haptic = AppSettingsScope.of(context).haptic;
    final selected = widget.selected;
    final color = selected ? p.accent : p.faint;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: () {
        if (haptic) HapticFeedback.selectionClick();
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
    required this.stretchOf,
    required this.dirOf,
    required this.draggingOf,
    required this.count,
    required this.accent,
    required this.accent2,
    required this.isDark,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final double Function() stretchOf;
  final double Function() dirOf;
  final bool Function() draggingOf;
  final int count;
  final Color accent;
  final Color accent2;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final position = animation.value;
    // 只有正在移动（拖动中 / 动画中）才形变，静止时强制标准胶囊
    final moving = draggingOf() ||
        animation.status == AnimationStatus.forward ||
        animation.status == AnimationStatus.reverse;
    final stretch =
        moving ? stretchOf().clamp(0.0, 1.0).toDouble() : 0.0;
    final dir = dirOf();

    const insetX = 6.0;
    const insetY = 8.0;
    final slot = size.width / count;
    final baseW = slot - insetX * 2;
    final h = size.height - insetY * 2;
    final baseX = position * slot + insetX;

    // 拖尾向后延伸
    final stretchPx = baseW * 0.22 * stretch;
    final x = dir > 0 ? baseX - stretchPx : baseX;
    final w = baseW + stretchPx;

    final rect = Rect.fromLTWH(x, insetY, w, h);
    final r = h / 2;
    final tail = r * (1 - 0.50 * stretch);

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

    // 1) 玻璃白底：几乎透明，只提亮一点点
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  Colors.white.withOpacity(0.18),
                  Colors.white.withOpacity(0.05),
                ]
              : [
                  Colors.white.withOpacity(0.90),
                  Colors.white.withOpacity(0.55),
                ],
        ).createShader(rect),
    );

    // 2) 极淡青绿染色（只给玻璃一点色温，不做大面积色块）
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            accent.withOpacity(0.10 + 0.05 * stretch),
            accent2.withOpacity(0.05 + 0.04 * stretch),
          ],
        ).createShader(rect),
    );

    // 3) 底部厚度：玻璃有实体感
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withOpacity(0),
            Colors.black.withOpacity(isDark ? 0.14 : 0.05),
          ],
        ).createShader(rect),
    );

    // 4) 受光边：顶部亮、底部暗
    canvas.drawRRect(
      rrect.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? [
                  Colors.white.withOpacity(0.55),
                  Colors.white.withOpacity(0.10),
                ]
              : [
                  Colors.white.withOpacity(0.95),
                  Colors.white.withOpacity(0.40),
                ],
        ).createShader(rect),
    );

    // 5) 顶部镜面高光带
    final gloss = Rect.fromLTWH(
      rect.left + 8,
      rect.top + 2,
      math.max(0, rect.width - 16),
      h * 0.42,
    );
    if (gloss.width > 4) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(gloss, Radius.circular(gloss.height / 2)),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withOpacity(isDark ? 0.28 : 0.60),
              Colors.white.withOpacity(0),
            ],
          ).createShader(gloss),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GlassIndicatorPainter oldDelegate) =>
      oldDelegate.count != count ||
      oldDelegate.accent != accent ||
      oldDelegate.accent2 != accent2 ||
      oldDelegate.isDark != isDark;
}