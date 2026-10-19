import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 平台入口：抖音为激活态，其余为「敬请期待」
class PlatformChip extends StatelessWidget {
  const PlatformChip({
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
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: active ? 1 : 0.55,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            gradient: active ? AppGradients.ice : null,
            color: active ? null : Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: active ? AppColors.cyan.withOpacity(0.28) : Colors.white.withOpacity(0.06),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    icon,
                    size: 24,
                    color: active ? AppColors.text : AppColors.textFaint,
                  ),
                  if (badge != null)
                    Positioned(
                      top: -6,
                      right: -14,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          gradient: AppGradients.brand,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          badge!,
                          style: const TextStyle(
                            fontSize: 8,
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
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
                  fontSize: 11.5,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  color: active ? AppColors.text : AppColors.textFaint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}