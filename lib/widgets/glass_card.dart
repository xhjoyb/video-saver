import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 玻璃拟态卡片：模糊背景 + 半透明描边
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 24,
    this.blur = 18,
    this.color,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double blur;
  final Color? color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: color ?? Colors.white.withOpacity(0.035),
            borderRadius: borderRadius,
            border: Border.all(
              color: borderColor ?? Colors.white.withOpacity(0.07),
              width: 1,
            ),
            gradient: color == null ? AppGradients.cardSheen : null,
          ),
          child: child,
        ),
      ),
    );
  }
}