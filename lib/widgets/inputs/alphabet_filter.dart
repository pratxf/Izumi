import 'package:flutter/material.dart';
import 'package:izumi/core/ui/app_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';

/// A→Z / Z→A sort toggle pill.
/// Tapping toggles between ascending and descending alphabetical order.
/// [isAscending] controls the current sort direction.
/// [onToggle] is called with the new value when tapped.
class AlphabetFilter extends StatelessWidget {
  final bool isAscending;
  final ValueChanged<bool> onToggle;

  /// Horizontal padding around the pill. Defaults to 20.
  final EdgeInsetsGeometry? padding;

  const AlphabetFilter({
    super.key,
    this.isAscending = true,
    required this.onToggle,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => onToggle(!isAscending),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.glassPrimary,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isAscending ? AppIcons.arrow_down : AppIcons.arrow_up,
                    size: 14,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isAscending ? 'A → Z' : 'Z → A',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
