import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';
import '../../widgets/glass/gradient_background.dart';
import '../../widgets/glass/glass_panel.dart';
import '../../widgets/navigation/app_header.dart';

/// Notifications Screen - Unified Glass Design
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final today = [
      _NotificationItem(
        title: 'Urgent: Equipment Check',
        time: '2m ago',
        description: 'Immediate inspection required for Tractor Unit #42.',
        icon: Iconsax.warning_2,
        color: AppColors.warning,
      ),
      _NotificationItem(
        title: 'New Task Assigned',
        time: '1h ago',
        description: 'Visit Rajendra Nagar for soil sampling collection.',
        icon: Iconsax.task_square,
        color: AppColors.primary,
      ),
      _NotificationItem(
        title: 'System Update',
        time: '3h ago',
        description: 'Izumi app has been updated to the latest build.',
        icon: Iconsax.refresh_square_2,
        color: AppColors.info,
      ),
    ];

    final earlier = [
      _NotificationItem(
        title: 'Location Verified',
        time: 'Yesterday',
        description: 'Check-in confirmed at Warehouse B distribution center.',
        icon: Iconsax.location,
        color: AppColors.success,
      ),
      _NotificationItem(
        title: 'Field Report Submitted',
        time: 'Yesterday',
        description: 'Report #8892 successfully uploaded to cloud storage.',
        icon: Iconsax.note_2,
        color: AppColors.textSecondary,
        isMuted: true,
      ),
    ];

    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              const AppHeader(
                title: 'Notifications',
                type: AppHeaderType.secondary,
                showAvatar: false,
                actions: [],
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
                  children: [
                    _buildSectionHeader('Today'),
                    const SizedBox(height: 12),
                    ...today.map(_buildNotificationCard),
                    const SizedBox(height: 24),
                    _buildSectionHeader('Earlier'),
                    const SizedBox(height: 12),
                    ...earlier.map(_buildNotificationCard),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        label.toUpperCase(),
        style: AppTypography.caption.copyWith(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildNotificationCard(_NotificationItem item) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      borderRadius: 22,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: 56,
            decoration: BoxDecoration(
              color: item.isMuted ? AppColors.glassBorder : item.color,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: item.color.withValues(alpha: item.isMuted ? 0.08 : 0.2),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: item.color.withValues(alpha: 0.3),
              ),
            ),
            child: Icon(
              item.icon,
              color: item.isMuted ? AppColors.textTertiary : item.color,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        item.title,
                        style: AppTypography.bodyMedium.copyWith(
                          color: item.isMuted
                              ? AppColors.textSecondary
                              : AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      item.time,
                      style: AppTypography.small.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  item.description,
                  style: AppTypography.caption.copyWith(
                    color: item.isMuted
                        ? AppColors.textTertiary
                        : AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationItem {
  final String title;
  final String time;
  final String description;
  final IconData icon;
  final Color color;
  final bool isMuted;

  const _NotificationItem({
    required this.title,
    required this.time,
    required this.description,
    required this.icon,
    required this.color,
    this.isMuted = false,
  });
}
