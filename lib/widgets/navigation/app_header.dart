import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_typography.dart';

/// App Header Widget - Unified Glass Header
/// Primary: root/dashboard, Secondary: detail/drill-down
enum AppHeaderType { primary, secondary }

class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  final String? title;
  final bool showBackButton;
  final bool showAvatar;
  final bool showNotification;
  final bool showLeading;
  final String? avatarUrl;
  final VoidCallback? onAvatarTap;
  final VoidCallback? onBackTap;
  final VoidCallback? onNotificationTap;
  final List<Widget>? actions;
  final AppHeaderType type;

  const AppHeader({
    super.key,
    this.title,
    this.showBackButton = false,
    this.showAvatar = true,
    this.showNotification = false,
    this.showLeading = true,
    this.avatarUrl,
    this.onAvatarTap,
    this.onBackTap,
    this.onNotificationTap,
    this.actions,
    this.type = AppHeaderType.primary,
  });

  @override
  Size get preferredSize => const Size.fromHeight(AppSpacing.headerHeight);

  @override
  Widget build(BuildContext context) {
    final contentColor = AppColors.textPrimary;

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          height: AppSpacing.headerHeight + MediaQuery.of(context).padding.top,
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top,
            left: AppSpacing.lg,
            right: AppSpacing.lg,
          ),
          decoration: BoxDecoration(
            color: AppColors.glassHeader,
            border: Border(
              bottom: BorderSide(color: AppColors.glassBorder, width: 1),
            ),
          ),
          child: Row(
            children: [
              // Back Button or Identity Icon
              if (!showLeading)
                const SizedBox.shrink()
              else if (type == AppHeaderType.secondary || showBackButton)
                _GlassIconButton(
                  icon: Iconsax.arrow_left_2,
                  onTap: onBackTap ?? () => Navigator.of(context).pop(),
                )
              else
                _GlassIconButton(
                  icon: Iconsax.element_3,
                  onTap: null,
                ),

              const SizedBox(width: AppSpacing.md),

              // Title or Brand
              Expanded(
                child: Text(
                  title ?? 'Izumi',
                  style: AppTypography.h3.copyWith(color: contentColor),
                ),
              ),

              // Actions
              if (actions != null) ...actions!,

              // Notification Bell
              if (showNotification) ...[
                Stack(
                  children: [
                    _GlassIconButton(
                      icon: Iconsax.notification,
                      onTap: onNotificationTap,
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: AppColors.error,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.glassBorder,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: AppSpacing.sm),
              ],

              // Avatar
              if (showAvatar) ...[
                GestureDetector(
                  onTap: onAvatarTap,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.glassBorder,
                        width: 1.5,
                      ),
                    ),
                    child: avatarUrl != null
                        ? ClipOval(
                            child: Image.network(
                              avatarUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  _buildAvatarPlaceholder(),
                            ),
                          )
                        : _buildAvatarPlaceholder(),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primary,
        shape: BoxShape.circle,
      ),
      child: const Center(
        child: Icon(Iconsax.user, size: 22, color: AppColors.textPrimary),
      ),
    );
  }
}

/// Glass Icon Button
class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _GlassIconButton({
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.glassPrimary,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.glassBorder, width: 1),
            ),
            child: Icon(
              icon,
              size: 22,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}


