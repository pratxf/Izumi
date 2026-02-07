import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_shadows.dart';
import '../../core/constants/app_typography.dart';
import '../../widgets/glass/gradient_background.dart';
import '../../widgets/navigation/app_header.dart';
import '../auth/welcome_screen.dart';

/// Profile Screen - Glassmorphism Design
/// User profile with settings and logout
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  void _logout(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: AlertDialog(
          backgroundColor: AppColors.glassStrong,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Text(
            'Logout',
            style: AppTypography.h3.copyWith(color: AppColors.textPrimary),
          ),
          content: Text(
            'Are you sure you want to logout?',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Cancel',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                  (route) => false,
                );
              },
              child: Text(
                'Logout',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.critical,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const AppHeader(
              title: 'Profile',
              type: AppHeaderType.secondary,
              showAvatar: false,
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 120),
                child: Column(
                  children: [
                    // Profile Card
                    _buildProfileCard(),
                    const SizedBox(height: 24),

                    // Menu Items Card
                    _buildMenuCard(context),
                    const SizedBox(height: 16),

                    // Logout Card
                    _buildLogoutCard(context),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            gradient: AppColors.glassPanelGradient,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: AppColors.glassBorder),
            boxShadow: AppShadows.glass,
          ),
          child: Column(
            children: [
              // Avatar
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.primary.withValues(alpha: 0.3),
                      AppColors.primary.withValues(alpha: 0.1),
                    ],
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.4),
                    width: 3,
                  ),
                ),
                child: Center(
                  child: Text(
                    'RK',
                    style: AppTypography.h2.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Name
              Text(
                'Rahul Kumar',
                style: AppTypography.h2.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),

              // Phone
              Text(
                '+91 98765 43210',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 12),

              // Role Badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.2),
                  ),
                ),
                child: Text(
                  'Field Employee',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuCard(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            gradient: AppColors.glassPanelGradient,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.glassBorder),
            boxShadow: AppShadows.glass,
          ),
          child: Column(
            children: [
              _buildMenuItem(
                icon: Iconsax.user_edit,
                label: 'Edit Profile',
                onTap: () {},
              ),
              _buildDivider(),
              _buildMenuItem(
                icon: Iconsax.message_question,
                label: 'Help & Support',
                onTap: () {},
              ),
              _buildDivider(),
              _buildMenuItem(
                icon: Iconsax.info_circle,
                label: 'About',
                onTap: () {},
              ),
              _buildDivider(),
              _buildMenuItem(
                icon: Iconsax.setting_2,
                label: 'Settings',
                onTap: () {},
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogoutCard(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            gradient: AppColors.glassPanelGradient,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.glassBorder),
            boxShadow: AppShadows.glass,
          ),
          child: _buildMenuItem(
            icon: Iconsax.logout,
            label: 'Logout',
            isDestructive: true,
            onTap: () => _logout(context),
          ),
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isDestructive
                    ? AppColors.critical.withValues(alpha: 0.1)
                    : AppColors.glassPrimary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 20,
                color: isDestructive
                    ? AppColors.critical
                    : AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: AppTypography.bodyMedium.copyWith(
                  color:
                      isDestructive ? AppColors.critical : AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(
      height: 1,
      indent: 72,
      endIndent: 20,
      color: AppColors.glassBorder,
    );
  }
}

