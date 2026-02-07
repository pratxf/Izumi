import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_typography.dart';

/// Glass badge for semantic status
class GlassBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const GlassBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  factory GlassBadge.success(String label, {IconData? icon}) => GlassBadge(
        label: label,
        color: AppColors.success,
        icon: icon,
      );

  factory GlassBadge.warning(String label, {IconData? icon}) => GlassBadge(
        label: label,
        color: AppColors.warning,
        icon: icon,
      );

  factory GlassBadge.critical(String label, {IconData? icon}) => GlassBadge(
        label: label,
        color: AppColors.critical,
        icon: icon,
      );

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: color),
                const SizedBox(width: AppSpacing.xs),
              ],
              Text(
                label,
                style: AppTypography.caption.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

