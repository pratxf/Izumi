import 'package:flutter/material.dart';
import 'package:izumi/core/ui/app_icons.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_shadows.dart';
import '../../core/constants/app_typography.dart';
import '../../models/task_model.dart';
import '../../providers/team_provider.dart';
import '../../widgets/glass/gradient_background.dart';
import '../../widgets/navigation/app_header.dart';

/// Team Lead Employee Detail Screen - Work Status Detail
class TeamLeadEmployeeDetailScreen extends StatefulWidget {
  final String name;
  final String initials;
  final bool isOnline;
  final String? employeeId;

  const TeamLeadEmployeeDetailScreen({
    super.key,
    required this.name,
    required this.initials,
    this.isOnline = true,
    this.employeeId,
  });

  @override
  State<TeamLeadEmployeeDetailScreen> createState() =>
      _TeamLeadEmployeeDetailScreenState();
}

class _TeamLeadEmployeeDetailScreenState
    extends State<TeamLeadEmployeeDetailScreen> {

  @override
  Widget build(BuildContext context) {
    final teamProvider = context.watch<TeamProvider>();

    // Filter tasks for this employee from team tasks
    final employeeTasks = widget.employeeId != null
        ? teamProvider.teamTasks
            .where((t) => t.assignedTo == widget.employeeId)
            .toList()
        : <TaskModel>[];

    final tasks = employeeTasks.where((t) => t.isTask).toList();
    final followUps = employeeTasks.where((t) => t.isFollowup).toList();
    final completedTaskCount = tasks.where((t) => t.isCompleted).length;
    final completedFollowUpCount = followUps.where((t) => t.isCompleted).length;
    final pendingTasks = tasks.length - completedTaskCount;
    final pendingFollowUps = followUps.length - completedFollowUpCount;

    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              AppHeader(
                title: widget.name,
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
                      completed: completedTaskCount,
                      total: tasks.length,
                      pendingLabel: '$pendingTasks Pending',
                    ),
                    const SizedBox(height: 12),
                    _buildTaskList(tasks),
                    const SizedBox(height: 20),
                    _buildSummaryCard(
                      title: 'Follow-ups',
                      accent: AppColors.primary,
                      completed: completedFollowUpCount,
                      total: followUps.length,
                      pendingLabel: '$pendingFollowUps Pending',
                    ),
                    const SizedBox(height: 12),
                    _buildTaskList(followUps),
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
                widget.initials,
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
                  widget.name,
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
                        color: widget.isOnline
                            ? AppColors.success
                            : AppColors.textTertiary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      widget.isOnline ? 'Online' : 'Offline',
                      style: AppTypography.caption.copyWith(
                        color: widget.isOnline
                            ? AppColors.success
                            : AppColors.textSecondary,
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
                      AppIcons.task_square,
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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

  Widget _buildTaskList(List<TaskModel> tasks) {
    if (tasks.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: Text(
            'No items assigned',
            style: AppTypography.caption.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
        ),
      );
    }

    final timeFormat = DateFormat('h:mm a');
    return Column(
      children: tasks.map((task) {
        final completed = task.isCompleted;
        String subtitle;
        if (completed && task.completedAt != null) {
          subtitle = 'Completed at ${timeFormat.format(task.completedAt!)}';
        } else if (task.isDueToday) {
          subtitle = 'Assigned \u2022 Due ${timeFormat.format(task.dueDate)}';
        } else {
          final dueStr = DateFormat('MMM d, h:mm a').format(task.dueDate);
          subtitle = 'Assigned \u2022 Due $dueStr';
        }

        // Determine icon & color based on task state
        IconData icon;
        Color accent;
        String statusLabel;
        if (completed) {
          icon = AppIcons.tick_circle;
          accent = AppColors.success;
          statusLabel = 'Completed';
        } else if (task.isHighPriority) {
          icon = AppIcons.warning_2;
          accent = AppColors.error;
          statusLabel = 'High Priority';
        } else if (task.isDueToday) {
          icon = AppIcons.clock;
          accent = AppColors.warning;
          statusLabel = 'Due Today';
        } else {
          icon = task.isFollowup ? AppIcons.call : AppIcons.task_square;
          accent = AppColors.primary;
          statusLabel = 'Pending';
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _buildStatusItem(
            icon: icon,
            accent: accent,
            title: task.title,
            subtitle: subtitle,
            status: statusLabel,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildStatusItem({
    required IconData icon,
    required Color accent,
    required String title,
    required String subtitle,
    required String status,
  }) {
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
          Expanded(
            child: Row(
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
                    icon,
                    size: 16,
                    color: accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
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
