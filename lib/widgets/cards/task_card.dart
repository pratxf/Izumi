import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_shadows.dart';
import '../../core/constants/app_typography.dart';
import '../buttons/hold_button.dart';

/// Task Priority Enum
enum TaskPriority { high, medium, low }

/// Task Card Widget
/// Displays task with priority border, details, and hold-to-complete button
class TaskCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? dueDate;
  final TaskPriority priority;
  final bool isCompleted;
  final String? completedDate;
  final String? notes;
  final bool showHoldButton;
  final VoidCallback? onComplete;
  final VoidCallback? onTap;

  const TaskCard({
    super.key,
    required this.title,
    this.subtitle,
    this.dueDate,
    this.priority = TaskPriority.medium,
    this.isCompleted = false,
    this.completedDate,
    this.notes,
    this.showHoldButton = true,
    this.onComplete,
    this.onTap,
  });

  Color get _priorityColor {
    if (isCompleted) return AppColors.textTertiary;
    switch (priority) {
      case TaskPriority.high:
        return AppColors.priorityHigh;
      case TaskPriority.medium:
        return AppColors.priorityMedium;
      case TaskPriority.low:
        return AppColors.priorityLow;
    }
  }

  String get _priorityIcon {
    if (isCompleted) return '✅';
    switch (priority) {
      case TaskPriority.high:
        return '⚠️';
      case TaskPriority.medium:
        return '📋';
      case TaskPriority.low:
        return '📝';
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.glassPrimary,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border(
            left: BorderSide(color: _priorityColor, width: 4),
            top: const BorderSide(color: AppColors.glassBorder),
            right: const BorderSide(color: AppColors.glassBorder),
            bottom: const BorderSide(color: AppColors.glassBorder),
          ),
          boxShadow: AppShadows.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_priorityIcon, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppTypography.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                          color: isCompleted
                              ? AppColors.textTertiary
                              : AppColors.textPrimary,
                          decoration: isCompleted
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          subtitle!,
                          style: AppTypography.caption.copyWith(
                            color: isCompleted
                                ? AppColors.textTertiary
                                : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // Status Badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: isCompleted
                        ? AppColors.badgeSuccess
                        : AppColors.badgeWarning,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
                  ),
                  child: Text(
                    isCompleted ? 'Completed' : 'Pending',
                    style: AppTypography.small.copyWith(
                      fontWeight: FontWeight.w500,
                      color: isCompleted
                          ? AppColors.successDark
                          : AppColors.warningDark,
                    ),
                  ),
                ),
              ],
            ),
            // Due Date or Completed Date
            if (dueDate != null || completedDate != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                isCompleted
                    ? 'Completed: ${completedDate ?? ''}'
                    : 'Due: $dueDate',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ],
            // Notes
            if (notes != null && isCompleted) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Notes: $notes',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textTertiary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            // Hold Button
            if (showHoldButton && !isCompleted) ...[
              const SizedBox(height: AppSpacing.md),
              HoldButton(label: 'Hold to Complete', onComplete: onComplete),
            ],
          ],
        ),
      ),
    );
  }
}

