import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_typography.dart';

/// Primary Button Widget
/// Used for main actions - comes in round and rectangular variants
class PrimaryButton extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool isRound;
  final bool isLoading;
  final double? width;

  const PrimaryButton({
    super.key,
    this.label,
    this.icon,
    this.onPressed,
    this.isRound = false,
    this.isLoading = false,
    this.width,
  });

  /// Round button variant (56px diameter)
  const PrimaryButton.round({
    super.key,
    required IconData this.icon,
    this.onPressed,
    this.isLoading = false,
  }) : label = null,
       isRound = true,
       width = null;

  /// Rectangular button variant
  const PrimaryButton.rectangular({
    super.key,
    required String this.label,
    this.icon,
    this.onPressed,
    this.isLoading = false,
    this.width,
  }) : isRound = false;

  @override
  Widget build(BuildContext context) {
    if (isRound) {
      return _buildRoundButton();
    }
    return _buildRectangularButton();
  }

  Widget _buildRoundButton() {
    return Container(
      width: AppSpacing.buttonRound,
      height: AppSpacing.buttonRound,
      decoration: BoxDecoration(
        color: onPressed != null
            ? AppColors.primary
            : AppColors.primary.withValues(alpha: 0.4),
        shape: BoxShape.circle,
        boxShadow: [
          if (onPressed != null)
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.18),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLoading ? null : onPressed,
          customBorder: const CircleBorder(),
          child: Center(
            child: isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Colors.white,
                      ),
                    ),
                  )
                : Icon(
                    icon,
                    size: AppSpacing.iconSize,
                    color: Colors.white,
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildRectangularButton() {
    return SizedBox(
      width: width ?? double.infinity,
      height: AppSpacing.buttonHeight,
      child: Container(
        decoration: BoxDecoration(
          color: onPressed != null
              ? AppColors.primary
              : AppColors.primary.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          boxShadow: [
            if (onPressed != null)
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.16),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: isLoading ? null : onPressed,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            child: Center(
              child: isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.white,
                        ),
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null) ...[
                          Icon(
                            icon,
                            size: AppSpacing.iconSize,
                            color: Colors.white,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                        ],
                        Text(
                          label ?? '',
                          style: AppTypography.buttonLarge.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
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
