import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_shadows.dart';
import '../../core/constants/app_typography.dart';
import '../../widgets/glass/gradient_background.dart';
import '../../widgets/navigation/app_header.dart';

/// Team Lead Employee Detail Screen - Work Status Detail
class TeamLeadEmployeeDetailScreen extends StatelessWidget {
  final String name;
  final String initials;
  final bool isOnline;

  const TeamLeadEmployeeDetailScreen({
    super.key,
    required this.name,
    required this.initials,
    this.isOnline = true,
  });

  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              AppHeader(
                title: name,
                type: AppHeaderType.secondary,
                showAvatar: false,
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
                  children: [
                    _buildHeaderStatus(context),
                    const SizedBox(height: 16),
                    _buildSectionTitle('Work Summary'),
                    const SizedBox(height: 12),
                    _buildSummaryCard(
                      title: 'Tasks',
                      accent: AppColors.primary,
                      completed: 3,
                      total: 5,
                      pendingLabel: '3 Pending',
                    ),
                    const SizedBox(height: 12),
                    _buildTaskList(),
                    const SizedBox(height: 20),
                    _buildSummaryCard(
                      title: 'Follow-ups',
                      accent: AppColors.primary,
                      completed: 2,
                      total: 4,
                      pendingLabel: '2 Pending',
                    ),
                    const SizedBox(height: 12),
                    _buildFollowUpList(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderStatus(BuildContext context) {
    return Container(
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
              color: AppColors.glassHover,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Center(
              child: Text(
                initials,
                style: AppTypography.bodyMedium.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: AppTypography.h3.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isOnline ? AppColors.success : AppColors.textTertiary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isOnline ? 'Online' : 'Offline',
                      style: AppTypography.caption.copyWith(
                        color: isOnline ? AppColors.success : AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        label,
        style: AppTypography.bodyMedium.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required Color accent,
    required int completed,
    required int total,
    required String pendingLabel,
  }) {
    final double progress = total == 0 ? 0 : completed / total;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.glassPrimary,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: accent.withValues(alpha: 0.3)),
                    ),
                    child: const Icon(
                      Iconsax.task_square,
                      color: AppColors.textPrimary,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    title,
                    style: AppTypography.h3.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.glassHover,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.glassBorder),
                ),
                child: Text(
                  pendingLabel,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                '$completed',
                style: AppTypography.displayLarge.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '/ $total Completed',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: progress,
              backgroundColor: AppColors.glassBorder,
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskList() {
    return Column(
      children: [
        _buildStatusItem(
          title: 'Site Audit - Sector 4',
          subtitle: 'Completed at 10:30 AM',
          status: 'Completed',
          completed: true,
        ),
        const SizedBox(height: 10),
        _buildStatusItem(
          title: 'Safety Compliance',
          subtitle: 'Completed at 11:15 AM',
          status: 'Completed',
          completed: true,
        ),
        const SizedBox(height: 10),
        _buildStatusItem(
          title: 'Inventory Check',
          subtitle: 'Assigned • Due 2:00 PM',
          status: 'Pending',
          completed: false,
        ),
        const SizedBox(height: 10),
        _buildStatusItem(
          title: 'Shift Report',
          subtitle: 'Assigned • Due 5:00 PM',
          status: 'Pending',
          completed: false,
        ),
      ],
    );
  }

  Widget _buildFollowUpList() {
    return Column(
      children: [
        _buildStatusItem(
          title: 'Fresh Mart',
          subtitle: 'Ticket #209 • Closed',
          status: 'Completed',
          completed: true,
        ),
        const SizedBox(height: 10),
        _buildStatusItem(
          title: 'Urban Clothiers',
          subtitle: 'Ticket #211 • Closed',
          status: 'Completed',
          completed: true,
        ),
        const SizedBox(height: 10),
        _buildStatusItem(
          title: 'Daily Dairy',
          subtitle: 'Ticket #215 • Awaiting Reply',
          status: 'Pending',
          completed: false,
        ),
        const SizedBox(height: 10),
        _buildStatusItem(
          title: 'Tech Hub Zone',
          subtitle: 'Ticket #220 • Scheduled',
          status: 'Pending',
          completed: false,
        ),
      ],
    );
  }

  Widget _buildStatusItem({
    required String title,
    required String subtitle,
    required String status,
    required bool completed,
  }) {
    final Color accent = completed ? AppColors.primary : AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.glassPrimary,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: accent.withValues(alpha: 0.3)),
                ),
                child: Icon(
                  completed ? Iconsax.check : Iconsax.radio,
                  size: 16,
                  color: accent,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTypography.small.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: accent.withValues(alpha: 0.25)),
            ),
            child: Text(
              status,
              style: AppTypography.caption.copyWith(
                color: accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}


