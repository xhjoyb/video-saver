import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

/// 平台入口：图标 + 名称，激活平台用主色描边
class PlatformItem extends StatelessWidget {
  const PlatformItem({
    super.key,
    required this.name,
    required this.icon,
    this.active = false,
    this.badge,
    this.onTap,
  });

  final String name;
  final IconData icon;
  final bool active;
  final String? badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: active ? p.accent.withOpacity(0.10) : p.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: active ? p.accent.withOpacity(0.34) : p.border,
                  ),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: active ? p.accent : p.faint,
                ),
              ),
              if (badge != null)
                Positioned(
                  top: -6,
                  right: -10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [p.accent, p.accent2]),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      badge!,
                      style: TextStyle(
                        fontSize: 8,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                        color: p.onAccent,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            name,
            style: TextStyle(
              fontSize: 11,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              color: active ? p.text : p.faint,
            ),
          ),
        ],
      ),
    );
  }
}