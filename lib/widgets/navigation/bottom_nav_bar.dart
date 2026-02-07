import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_shadows.dart';

/// Tab Item Data
class BottomNavItem {
  final String label;
  final IconData icon;
  final IconData activeIcon;

  const BottomNavItem({
    required this.label,
    required this.icon,
    IconData? activeIcon,
  }) : activeIcon = activeIcon ?? icon;
}

/// Bottom Navigation Bar Widget
/// Floating glass-style nav bar with active tab highlight
class BottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<BottomNavItem> items;

  const BottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  /// Employee/Team Lead navigation items
  static List<BottomNavItem> get employeeItems => const [
    BottomNavItem(
      label: 'Home',
      icon: Iconsax.home_2_copy,
      activeIcon: Iconsax.home_2,
    ),
    BottomNavItem(
      label: 'Gallery',
      icon: Iconsax.camera_copy,
      activeIcon: Iconsax.camera,
    ),
    BottomNavItem(
      label: 'Todo',
      icon: Iconsax.task_square_copy,
      activeIcon: Iconsax.task_square,
    ),
    BottomNavItem(
      label: 'History',
      icon: Iconsax.clock_copy,
      activeIcon: Iconsax.clock,
    ),
  ];

  /// Admin navigation items
  static List<BottomNavItem> get adminItems => const [
    BottomNavItem(
      label: 'Dashboard',
      icon: Iconsax.element_3_copy,
      activeIcon: Iconsax.element_3,
    ),
    BottomNavItem(
      label: 'Images',
      icon: Iconsax.image_copy,
      activeIcon: Iconsax.image,
    ),
    BottomNavItem(
      label: 'Tasks',
      icon: Iconsax.clipboard_text_copy,
      activeIcon: Iconsax.clipboard_text,
    ),
    BottomNavItem(
      label: 'Analytics',
      icon: Iconsax.chart_2_copy,
      activeIcon: Iconsax.chart_2,
    ),
    BottomNavItem(
      label: 'Groups',
      icon: Iconsax.people_copy,
      activeIcon: Iconsax.people,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        bottom: bottomPadding + AppSpacing.sm,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            height: AppSpacing.navBarHeight,
            decoration: BoxDecoration(
              // Glass panel background
              color: AppColors.navBarBackground,
              borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
              border: Border.all(color: AppColors.glassBorder, width: 1),
              boxShadow: AppShadows.navBar,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(items.length, (index) {
                final item = items[index];
                final isActive = index == currentIndex;

                return GestureDetector(
                  onTap: () => onTap(index),
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    padding: EdgeInsets.symmetric(
                      horizontal: isActive ? 14 : 10,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: isActive
                          ? AppColors.glassHover
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                      border: isActive
                          ? Border.all(
                              color: AppColors.glassBorder,
                              width: 1,
                            )
                          : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isActive ? item.activeIcon : item.icon,
                          size: 22,
                          color: isActive
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                        ),
                        // Only show label for active tab
                        if (isActive) ...[
                          const SizedBox(width: 8),
                          Text(
                            item.label,
                            style: AppTypography.bodyMedium.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w500, // Medium
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

