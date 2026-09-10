import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'check_d_design.dart';

class GlassButton extends StatelessWidget {
  const GlassButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.color = AppColors.primary,
    this.filled = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    final foreground = disabled ? AppColors.muted : color;
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: filled && !disabled ? AppGradients.primary : null,
            color: filled && !disabled ? null : AppColors.glass,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: disabled ? AppColors.border : color.withValues(alpha: .42),
            ),
            boxShadow: const [AppShadows.glass],
          ),
          child: CheckDPressable(
            onTap: onPressed,
            pressedScale: .97,
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(
                      icon,
                      size: 16,
                      color: filled ? Colors.white : foreground,
                    ),
                    const SizedBox(width: 5),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      color: filled ? Colors.white : foreground,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
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
