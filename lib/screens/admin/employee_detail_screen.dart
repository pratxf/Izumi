import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_shadows.dart';
import '../../core/constants/app_typography.dart';
import '../../widgets/glass/gradient_background.dart';
import '../../widgets/navigation/app_header.dart';
import '../employee/gallery_screen.dart';

/// Employee Detail Screen
/// Layout based on "Employee Activity Logs" HTML reference
class EmployeeDetailScreen extends StatelessWidget {
  final String name;
  final bool isActive;
  final String avatarUrl;

  const EmployeeDetailScreen({
    super.key,
    required this.name,
    required this.isActive,
    this.avatarUrl = 'https://i.pravatar.cc/150?img=11', // Default callback
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GradientBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              const AppHeader(
                title: 'Employee',
                type: AppHeaderType.secondary,
                showAvatar: false,
              ),

              // Scrollable Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 120),
                  child: Column(
                    children: [
                      // Stats Row
                      _buildStatsRow(),
                      const SizedBox(height: 32),

                      // Action Buttons (Horizontal Scroll)
                      _buildActionButtons(context),
                      const SizedBox(height: 32),

                      // Live Activity Feed Title
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Live Activity Feed',
                          style: AppTypography.h3.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Activity Feed
                      _buildActivityFeed(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      // Unified navigation handled by shell
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Back Button
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.textPrimary.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.textPrimary.withValues(alpha: 0.2),
                    ),
                  ),
                  child: const Icon(
                    Icons.arrow_back_ios_new,
                    color: AppColors.textPrimary,
                    size: 18,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),

          // Name and Role
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: AppTypography.h2.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    shadows: [
                      Shadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    Text(
                      'Field Executive',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textPrimary.withValues(alpha: 0.8),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.textPrimary.withValues(alpha: 0.6),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isActive ? 'Online' : 'Offline',
                      style: AppTypography.caption.copyWith(
                        color: isActive ? AppColors.success : AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Avatar
          Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.textPrimary, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: CircleAvatar(
                  radius: 24,
                  backgroundImage: NetworkImage(avatarUrl),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: isActive ? AppColors.success : AppColors.textDisabled,
                    shape: BoxShape.circle,
                    border: Border.all(
                    color: AppColors.textTertiary,
                      width: 2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.glassPrimary,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.glassBorder),
            boxShadow: AppShadows.glass,
          ),
          child: IntrinsicHeight(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Session Time
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SESSION TIME',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary.withValues(alpha: 0.7),
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '03:42:15',
                      style: AppTypography.h2.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                // Divider
                Container(width: 1, color: AppColors.glassBorder),
                // Total Distance
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'TOTAL DISTANCE',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary.withValues(alpha: 0.7),
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '12.4 km',
                      style: AppTypography.h2.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildActionButton(
            Iconsax.task_square,
            'Assign Task',
            () {}, // TODO: Implement Task Assignment
          ),
          const SizedBox(width: 12),
          _buildActionButton(Iconsax.gallery, 'View Photos', () {
            Navigator.push(
              context, // Using context from build method if available, but checking _buildActionButtons signature
              MaterialPageRoute(builder: (_) => const GalleryScreen()),
            );
          }),
          const SizedBox(width: 12),
          _buildActionButton(
            Iconsax.map,
            'View Route',
            () {}, // TODO: Implement Route View
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.glassPrimary,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.glassBorder),
              boxShadow: AppShadows.glass,
            ),
            child: Row(
              children: [
                Icon(icon, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActivityFeed() {
    return Column(
      children: [
        _buildTimelineItem(
          icon: Iconsax.location,
          title: 'Location Update',
          time: '2 MIN AGO',
          description: 'Checked in at Sector 45, Gurgaon',
          isLast: false,
        ),
        _buildTimelineItem(
          icon: Iconsax.box,
          title: 'Task Started',
          time: '15 MIN AGO',
          description: 'Inventory Check - Warehouse A',
          isLast: false,
        ),
        _buildTimelineItem(
          icon: Iconsax.camera,
          title: 'Photo Captured',
          time: '45 MIN AGO',
          description: 'Site Frontage - Evidence uploaded',
          isLast: false,
        ),
        _buildTimelineItem(
          icon: Iconsax.car,
          title: 'Commute Started',
          time: '1H AGO',
          description: 'Traveling to Sector 45',
          isLast: true,
          isOpacity: true,
        ),
      ],
    );
  }

  Widget _buildTimelineItem({
    required IconData icon,
    required String title,
    required String time,
    required String description,
    required bool isLast,
    bool isOpacity = false,
  }) {
    return Opacity(
      opacity: isOpacity ? 0.8 : 1.0,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Timeline Line & Icon Placeholder space
            SizedBox(
              width: 24, // Matches left padding for line alignment
              child: Stack(
                alignment: Alignment.topCenter,
                children: [
                  if (!isLast)
                    Positioned(
                      top: 40,
                      bottom: 0,
                      child: Container(
                        width: 2,
                        color: AppColors.glassBorder,
                      ),
                    ),
                ],
              ),
            ),
            // Card Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.glassPrimary,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: AppColors.glassBorder),
                        boxShadow: AppShadows.glass,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(
                              icon,
                              color: AppColors.primary,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      title,
                                      style: AppTypography.bodyMedium.copyWith(
                                        color: AppColors.textPrimary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      time,
                                      style: AppTypography.caption.copyWith(
                                        color: AppColors.textSecondary
                                            .withValues(alpha: 0.6),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  description,
                                  style: AppTypography.bodySmall.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingNav() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(40),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.textPrimary.withValues(alpha: 0.1), // Adjusted for nav
              borderRadius: BorderRadius.circular(40),
              border: Border.all(color: AppColors.textPrimary.withValues(alpha: 0.3)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildNavItem(Iconsax.grid_2, false),
                _buildNavItem(Iconsax.task_square, true), // Active item mock
                _buildNavItem(Iconsax.location, false),
                _buildNavItem(Iconsax.chart_2, false),
                _buildNavItem(Iconsax.setting_2, false),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, bool isActive) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          icon,
          size: 24,
          color: isActive
              ? AppColors.primary
              : AppColors.textSecondary.withValues(alpha: 0.5),
        ),
        if (isActive) ...[
          const SizedBox(height: 4),
          Container(
            width: 4,
            height: 4,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ],
    );
  }
}



