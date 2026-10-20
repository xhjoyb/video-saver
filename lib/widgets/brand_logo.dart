import 'package:flutter/material.dart';

/// 品牌 Logo：与 launcher 图标同源的「青绿渐变圆 + 墨绿播放三角」。
///
/// 解析页 header、关于页等需要品牌标识的地方统一用它，
/// 不再各自用 `Icon(Icons.play_arrow)` + 主题色渐变拼，避免和桌面图标不一致。
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 32, this.glow = false});

  final double size;

  /// 大尺寸展示时加一层外发光（小尺寸不必要，且会糊）
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _BrandLogoPainter(glow: glow)),
    );
  }
}

// 与 android res/values/colors.xml、lib/app/splash_overlay.dart 保持一致
const Color _mintBright = Color(0xFF6BFFDD);
const Color _mint = Color(0xFF19E8BE);
const Color _mintDeep = Color(0xFF00A98A);
const Color _ink = Color(0xFF04120F);

class _BrandLogoPainter extends CustomPainter {
  const _BrandLogoPainter({required this.glow});

  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.shortestSide * 0.47;

    if (glow) {
      canvas.drawCircle(
        center,
        r * 1.5,
        Paint()
          ..shader = RadialGradient(
            colors: [_mint.withOpacity(0.30), _mint.withOpacity(0)],
          ).createShader(Rect.fromCircle(center: center, radius: r * 1.5)),
      );
    }

    // 青绿渐变圆
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment(-0.55, -0.65),
          end: Alignment(0.60, 0.70),
          colors: [_mintBright, _mint, _mintDeep],
          stops: [0.0, 0.52, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: r)),
    );

    // 内描边高光（小尺寸会糊，只在较大尺寸画）
    if (size.shortestSide >= 40) {
      canvas.drawCircle(
        center,
        r * 0.94,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.shortestSide * 0.012
          ..color = Colors.white.withOpacity(0.35),
      );
    }

    // 墨绿播放三角（与图标同一比例：左 -0.32R，右 +0.66R，上下 ±0.48R）
    final path = Path()
      ..moveTo(center.dx - r * 0.32, center.dy - r * 0.48)
      ..lineTo(center.dx + r * 0.66, center.dy)
      ..lineTo(center.dx - r * 0.32, center.dy + r * 0.48)
      ..close();
    canvas.drawPath(path, Paint()..color = _ink);
  }

  @override
  bool shouldRepaint(covariant _BrandLogoPainter oldDelegate) =>
      oldDelegate.glow != glow;
}