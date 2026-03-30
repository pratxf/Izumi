import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:izumi/core/ui/app_icons.dart';
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
      icon: AppIcons.home_2_copy,
      activeIcon: AppIcons.home_2,
    ),
    BottomNavItem(
      label: 'Gallery',
      icon: AppIcons.camera_copy,
      activeIcon: AppIcons.camera,
    ),
    BottomNavItem(
      label: 'Tasks',
      icon: AppIcons.task_square_copy,
      activeIcon: AppIcons.task_square,
    ),
    BottomNavItem(
      label: 'History',
      icon: AppIcons.clock_copy,
      activeIcon: AppIcons.clock,
    ),
    BottomNavItem(
      label: 'Chat',
      icon: AppIcons.message_copy,
      activeIcon: AppIcons.message,
    ),
  ];


  /// Admin navigation items
  static List<BottomNavItem> get adminItems => const [
    BottomNavItem(
      label: 'Dashboard',
      icon: AppIcons.element_3_copy,
      activeIcon: AppIcons.element_3,
    ),
    BottomNavItem(
      label: 'Tasks',
      icon: AppIcons.clipboard_text_copy,
      activeIcon: AppIcons.clipboard_text,
    ),
    BottomNavItem(
      label: 'Analytics',
      icon: AppIcons.chart_2_copy,
      activeIcon: AppIcons.chart_2,
    ),
    BottomNavItem(
      label: 'Management',
      icon: AppIcons.people_copy,
      activeIcon: AppIcons.people,
    ),
    BottomNavItem(
      label: 'Chat',
      icon: AppIcons.message_copy,
      activeIcon: AppIcons.message,
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
                          ? AppColors.primary
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isActive ? item.activeIcon : item.icon,
                          size: 22,
                          color: isActive
                              ? Colors.white
                              : AppColors.navBarInactiveIcon,
                        ),
                        // Only show label for active tab
                        if (isActive) ...[
                          const SizedBox(width: 8),
                          Text(
                            item.label,
                            style: AppTypography.bodyMedium.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
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

