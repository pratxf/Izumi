import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_typography.dart';

/// App Header Widget - Glassmorphism Style
/// Shows logo/title with glass-style buttons
class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  final String? title;
  final bool showBackButton;
  final bool showAvatar;
  final bool showNotification;
  final String? avatarUrl;
  final VoidCallback? onAvatarTap;
  final VoidCallback? onBackTap;
  final VoidCallback? onNotificationTap;
  final List<Widget>? actions;
  final bool lightContent; // Use white text/icons for gradient backgrounds

  const AppHeader({
    super.key,
    this.title,
    this.showBackButton = false,
    this.showAvatar = true,
    this.showNotification = false,
    this.avatarUrl,
    this.onAvatarTap,
    this.onBackTap,
    this.onNotificationTap,
    this.actions,
    this.lightContent = true,
  });

  @override
  Size get preferredSize => const Size.fromHeight(AppSpacing.headerHeight);

  @override
  Widget build(BuildContext context) {
    final contentColor = lightContent
        ? AppColors.textOnGradient
        : AppColors.textPrimary;

    return Container(
      height: AppSpacing.headerHeight + MediaQuery.of(context).padding.top,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top,
        left: AppSpacing.lg,
        right: AppSpacing.lg,
      ),
      child: Row(
        children: [
          // Back Button or Logo Icon
          if (showBackButton)
            _GlassIconButton(
              icon: Icons.arrow_back_ios_new_rounded,
              onTap: onBackTap ?? () => Navigator.of(context).pop(),
              lightContent: lightContent,
            )
          else
            _GlassIconButton(
              icon: Iconsax.element_3,
              onTap: null,
              lightContent: lightContent,
            ),

          const SizedBox(width: AppSpacing.md),

          // Title or Brand
          if (title != null)
            Expanded(
              child: Text(
                title!,
                style: AppTypography.h3.copyWith(
                  color: contentColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          else
            Expanded(
              child: Text(
                'Izumi',
                style: AppTypography.h3.copyWith(
                  color: contentColor,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
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
                  lightContent: lightContent,
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
                        color: lightContent
                            ? AppColors.glassWhite
                            : Colors.white,
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
                  border: Border.all(color: AppColors.glassSlateSoft, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
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
    );
  }

  Widget _buildAvatarPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primary,
        shape: BoxShape.circle,
      ),
      child: const Center(
        child: Icon(Icons.person, size: 22, color: Colors.white),
      ),
    );
  }
}

/// Glass Icon Button
class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool lightContent;

  const _GlassIconButton({
    required this.icon,
    this.onTap,
    this.lightContent = true,
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
              color: AppColors.glassSlateSoft,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.glassSlateSoft, width: 1),
            ),
            child: Icon(
              icon,
              size: 22,
              color: lightContent ? Colors.white : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
