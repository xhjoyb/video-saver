import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 青绿主题开屏动画（纯自绘，不引入第三方动画依赖）。
///
/// 视觉层次：
///   1. 背景径向光晕呼吸
///   2. 46 颗青绿光点缓慢上浮 + 闪烁
///   3. 三层光环错峰扩散
///   4. 中心圆环沿 SweepGradient 描边生长
///   5. 播放三角弹性放大
///   6. 标题字距收拢淡入 + 副标题
///   7. 底部光带扫过
///   8. 结束整体放大淡出，交回主界面
///
/// 时长 1.9s，点击任意位置可提前结束。
class SplashGate extends StatefulWidget {
  const SplashGate({super.key, required this.child});

  final Widget child;

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  bool _finished = false;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (!_finished)
          Positioned.fill(
            child: SplashOverlay(
              onDone: () {
                if (mounted) setState(() => _finished = true);
              },
            ),
          ),
      ],
    );
  }
}

const Color _ink = Color(0xFF04120F);
const Color _bg = Color(0xFF05100E);
const Color _mintBright = Color(0xFF6BFFDD);
const Color _mint = Color(0xFF19E8BE);
const Color _mintDeep = Color(0xFF00A98A);
const Color _mintClear = Color(0x0019E8BE);

class SplashOverlay extends StatefulWidget {
  const SplashOverlay({
    super.key,
    required this.onDone,
    this.duration = const Duration(milliseconds: 1900),
  });

  final VoidCallback onDone;
  final Duration duration;

  @override
  State<SplashOverlay> createState() => _SplashOverlayState();
}

class _SplashOverlayState extends State<SplashOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _finish();
      })
      ..forward();
  }

  void _finish() {
    if (_done) return;
    _done = true;
    widget.onDone();
  }

  void _skip() {
    if (_controller.value >= 0.90) {
      _finish();
      return;
    }
    _controller.animateTo(
      1.0,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static double _seg(double t, double begin, double end) {
    if (end <= begin) return t >= end ? 1 : 0;
    final v = (t - begin) / (end - begin);
    return v.clamp(0.0, 1.0).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _skip,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          final exit = Curves.easeIn.transform(_seg(t, 0.90, 1.0));
          final ring = Curves.easeOutCubic.transform(_seg(t, 0.10, 0.52));
          final tri = Curves.elasticOut
              .transform(_seg(t, 0.44, 0.78))
              .clamp(0.0, 1.10)
              .toDouble();
          final titleT = Curves.easeOutCubic.transform(_seg(t, 0.52, 0.78));
          final subT = Curves.easeOutCubic.transform(_seg(t, 0.62, 0.86));
          final sweepT = _seg(t, 0.34, 0.92);
          final glow = 0.6 + 0.4 * math.sin(t * math.pi * 2.2);

          return Opacity(
            opacity: 1 - exit,
            child: Transform.scale(
              scale: 1 + 0.06 * exit,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0, -0.25),
                    radius: 1.15,
                    colors: [Color(0xFF0A2A24), _bg, Color(0xFF020807)],
                    stops: [0.0, 0.55, 1.0],
                  ),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CustomPaint(painter: _BackdropPainter(t)),
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 172,
                            height: 172,
                            child: CustomPaint(
                              painter: _LogoPainter(
                                ring: ring,
                                triangle: tri,
                                glow: glow.clamp(0.0, 1.0).toDouble(),
                                ripples: [
                                  _seg(t, 0.02, 0.46),
                                  _seg(t, 0.10, 0.56),
                                  _seg(t, 0.18, 0.66),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 26),
                          Opacity(
                            opacity: titleT,
                            child: Text(
                              '视频嗅探',
                              style: TextStyle(
                                fontSize: 23,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                                letterSpacing: 12 - 10 * titleT,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Opacity(
                            opacity: subT * 0.75,
                            child: Text(
                              'VIDEO SNIFFER',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w500,
                                color: _mint.withOpacity(0.75),
                                letterSpacing: 4.5 - 1.5 * subT,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 92,
                      child: Center(
                        child: ClipRect(
                          child: SizedBox(
                            width: 168,
                            height: 2,
                            child: CustomPaint(
                              painter: _SweepPainter(sweepT),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Particle {
  const _Particle(this.x, this.y, this.radius, this.phase, this.speed);

  final double x;
  final double y;
  final double radius;
  final double phase;
  final double speed;
}

/// 背景：呼吸光晕 + 上升光点
class _BackdropPainter extends CustomPainter {
  _BackdropPainter(this.t);

  final double t;

  static final List<_Particle> _particles = () {
    final rnd = math.Random(11);
    return List.generate(46, (_) {
      return _Particle(
        rnd.nextDouble(),
        rnd.nextDouble(),
        0.7 + rnd.nextDouble() * 1.7,
        rnd.nextDouble(),
        0.4 + rnd.nextDouble(),
      );
    });
  }();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.42);
    final pulse = 0.55 + 0.45 * math.sin(t * math.pi * 2.4);
    final radius = size.shortestSide * 0.82;
    final halo = Paint()
      ..shader = RadialGradient(
        colors: [
          _mint.withOpacity(0.15 * pulse),
          _mint.withOpacity(0.04 * pulse),
          _mintClear,
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, halo);

    for (final p in _particles) {
      final drift = (p.y - t * p.speed * 0.16) % 1.0;
      final dx = p.x * size.width;
      final dy = drift * size.height;
      final twinkle =
          (0.35 + 0.65 * math.sin((t * 2.0 + p.phase) * math.pi * 2).abs());
      canvas.drawCircle(
        Offset(dx, dy),
        p.radius,
        Paint()..color = _mintBright.withOpacity(0.34 * twinkle),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BackdropPainter oldDelegate) =>
      oldDelegate.t != t;
}

/// 中心：渐变描边圆环 + 播放三角 + 呼吸辉光
class _LogoPainter extends CustomPainter {
  const _LogoPainter({
    required this.ring,
    required this.triangle,
    required this.glow,
    required this.ripples,
  });

  final double ring;
  final double triangle;
  final double glow;

  /// 三层扩散光环的进度（0→1）
  final List<double> ripples;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.shortestSide * 0.30;

    // 外辉光
    canvas.drawCircle(
      center,
      r * 1.55,
      Paint()
        ..shader = RadialGradient(
          colors: [_mint.withOpacity(0.26 * glow), _mintClear],
        ).createShader(Rect.fromCircle(center: center, radius: r * 1.55)),
    );

    // 三层扩散光环（错峰向外扩散并淡出）
    for (final rp in ripples) {
      if (rp <= 0 || rp >= 1) continue;
      canvas.drawCircle(
        center,
        r * (1.02 + 0.95 * rp),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.4 + 1.6 * (1 - rp)
          ..color = _mint.withOpacity(0.40 * (1 - rp)),
      );
    }

    // 内侧淡色底盘，让三角在深色上有对比
    canvas.drawCircle(
      center,
      r,
      Paint()..color = _mint.withOpacity(0.10 + 0.05 * glow),
    );

    // 渐变描边圆环
    final rect = Rect.fromCircle(center: center, radius: r);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * ring,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.4
        ..strokeCap = StrokeCap.round
        ..shader = const SweepGradient(
          colors: [_mintBright, _mint, _mintDeep, _mintBright],
          transform: GradientRotation(-math.pi / 2),
        ).createShader(rect),
    );

    // 播放三角（弹性放大）
    final s = 0.62 + 0.38 * triangle;
    final apexX = center.dx + r * 0.66 * s;
    final leftX = center.dx - r * 0.32 * s;
    final halfY = r * 0.48 * s;
    final path = Path()
      ..moveTo(leftX, center.dy - halfY)
      ..lineTo(apexX, center.dy)
      ..lineTo(leftX, center.dy + halfY)
      ..close();
    final alpha = triangle.clamp(0.0, 1.0).toDouble();
    canvas.drawPath(path, Paint()..color = _ink.withOpacity(alpha));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = _mintBright.withOpacity(0.30 * alpha),
    );
  }

  @override
  bool shouldRepaint(covariant _LogoPainter oldDelegate) =>
      oldDelegate.ring != ring ||
      oldDelegate.triangle != triangle ||
      oldDelegate.glow != glow ||
      !_sameRipples(oldDelegate.ripples, ripples);

  static bool _sameRipples(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// 底部扫光
class _SweepPainter extends CustomPainter {
  const _SweepPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final x = -60 + progress * (size.width + 60);
    final rect = Rect.fromLTWH(x, 0, 60, size.height);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          colors: [_mintClear, _mintBright, _mintClear],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _SweepPainter oldDelegate) =>
      oldDelegate.progress != progress;
}