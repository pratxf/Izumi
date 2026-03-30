import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:izumi/core/ui/app_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_typography.dart';

/// Employee Card Widget
/// Displays employee info with avatar, status, and location
class EmployeeCard extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  final bool isActive;
  final String? location;
  final String? lastUpdated;
  final String? distance;
  final String? duration;
  final VoidCallback? onTap;

  const EmployeeCard({
    super.key,
    required this.name,
    this.avatarUrl,
    this.isActive = false,
    this.location,
    this.lastUpdated,
    this.distance,
    this.duration,
    this.onTap,
  });

  String get _initials {
    final parts = name.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, 2).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.glassPrimary,
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Row(
              children: [
                // Avatar
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: avatarUrl != null
                      ? ClipOval(
                          child: Image.network(
                            avatarUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                _buildInitialsAvatar(),
                          ),
                        )
                      : _buildInitialsAvatar(),
                ),
                const SizedBox(width: AppSpacing.md),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: AppTypography.bodyMedium.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          // Status Indicator
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: isActive
                                  ? AppColors.success
                                  : AppColors.inactiveGrey,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              Text(
                                isActive ? 'Active' : 'Inactive',
                                style: AppTypography.caption.copyWith(
                                  color: isActive
                                  ? AppColors.success
                                  : AppColors.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      if (location != null) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Row(
                          children: [
                            Icon(
                              AppIcons.location,
                              size: 14,
                              color: AppColors.textTertiary,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                isActive ? location! : 'Last: $location',
                                style: AppTypography.caption,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (lastUpdated != null) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Row(
                          children: [
                            Icon(
                              AppIcons.clock,
                              size: 14,
                              color: AppColors.textTertiary,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                isActive
                                    ? 'Updated: $lastUpdated'
                                    : 'Ended: $lastUpdated',
                                style: AppTypography.small,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (distance != null || duration != null) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          [
                            if (distance != null) distance,
                            if (duration != null) duration,
                          ].join(' • '),
                          style: AppTypography.small.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Icon(
                  AppIcons.arrow_right_2,
                  color: AppColors.textTertiary,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInitialsAvatar() {
    return Center(
      child: Text(
        _initials,
        style: AppTypography.bodyMedium.copyWith(
          color: AppColors.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

