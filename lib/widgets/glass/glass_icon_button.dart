import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';

/// Reusable glass icon button
class GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final double radius;

  const GlassIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.size = 44,
    this.radius = AppSpacing.radiusLg,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: AppColors.glassPrimary,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: AppColors.glassBorder, width: 1),
            ),
            child: Icon(icon, size: 22, color: AppColors.textPrimary),
          ),
        ),
      ),
    );
  }
}

