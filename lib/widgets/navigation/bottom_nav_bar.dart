import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';

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
      padding: EdgeInsets.only(left: 16, right: 16, bottom: bottomPadding + 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            height: 72,
            decoration: BoxDecoration(
              // Glass panel background
              color: AppColors.glassSlateSoft,
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: AppColors.glassSlateSoft, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
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
                      horizontal: isActive ? 16 : 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: isActive
                          ? AppColors.gradientStart
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isActive ? item.activeIcon : item.icon,
                          size: 22,
                          color: isActive
                              ? Colors.white
                              : AppColors.textSecondary,
                        ),
                        // Only show label for active tab
                        if (isActive) ...[
                          const SizedBox(width: 8),
                          Text(
                            item.label,
                            style: AppTypography.bodyMedium.copyWith(
                              color: Colors.white,
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
