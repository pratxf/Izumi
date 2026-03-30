import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:izumi/core/ui/app_icons.dart';
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
  final bool hasUnread;
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
    this.hasUnread = false,
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
    final topPadding = MediaQuery.of(context).padding.top;

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          height: AppSpacing.headerHeight + topPadding,
          padding: EdgeInsets.only(
            top: topPadding,
            left: AppSpacing.lg,
            right: AppSpacing.lg,
          ),
          decoration: BoxDecoration(
            color: type == AppHeaderType.primary
                ? Colors.white.withValues(alpha: 0.92)
                : Colors.white.withValues(alpha: 0.84),
            border: Border(
              bottom: BorderSide(
                color: AppColors.divider.withValues(alpha: 0.8),
              ),
            ),
          ),
          child: Row(
            children: [
              if (!showLeading)
                const SizedBox.shrink()
              else if (type == AppHeaderType.secondary || showBackButton)
                _HeaderIconButton(
                  icon: AppIcons.arrow_left_2,
                  onTap: onBackTap ?? () => Navigator.of(context).pop(),
                )
              else
                _HeaderIconButton(
                  icon: AppIcons.element_3,
                  onTap: null,
                ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  title ?? 'Izumi',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.h3.copyWith(
                    color: AppColors.primaryDark,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              if (actions != null) ...actions!,
              if (showNotification) ...[
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _HeaderIconButton(
                      icon: AppIcons.notification,
                      onTap: onNotificationTap,
                    ),
                    if (hasUnread)
                      Positioned(
                        top: 2,
                        right: 2,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: AppColors.critical,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              if (showAvatar)
                GestureDetector(
                  onTap: onAvatarTap,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.16),
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
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: const Center(
        child: Icon(AppIcons.user, size: 20, color: AppColors.primaryDark),
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _HeaderIconButton({
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
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.12),
              ),
            ),
            child: Icon(
              icon,
              size: 20,
              color: AppColors.primaryDark,
            ),
          ),
        ),
      ),
    );
  }
}
