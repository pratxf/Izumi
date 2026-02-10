import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_shadows.dart';
import '../../core/constants/app_typography.dart';
import '../../models/task_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/task_provider.dart';
import '../../widgets/glass/gradient_background.dart';
import '../../widgets/navigation/app_header.dart';

/// Tasks Screen (Admin) - Enterprise Dark Glass Design
/// Task overview and creation
class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  String? _lastLoadedEnterpriseId;

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  void _loadTasks() {
    final enterpriseId = context.read<AuthProvider>().enterpriseId;
    if (enterpriseId != null) {
      _lastLoadedEnterpriseId = enterpriseId;
      final taskProvider = context.read<TaskProvider>();
      // Start stream for live updates
      taskProvider.streamEnterpriseTasks(enterpriseId);
      // Also do a one-time fetch as fallback in case stream is slow
      taskProvider.loadEnterpriseTasks(enterpriseId);
    }
  }

  Future<void> _runTaskMigration() async {
    final result =
        await context.read<TaskProvider>().migrateOrphanedTasks();
    if (!mounted) return;

    if (result != null) {
      final migrated = result['migrated'] ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            migrated > 0
                ? 'Fixed $migrated orphaned task(s)'
                : 'No orphaned tasks found',
          ),
          backgroundColor:
              migrated > 0 ? AppColors.success : AppColors.info,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to run migration'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Re-load if enterpriseId becomes available after a retry
    final enterpriseId = context.watch<AuthProvider>().enterpriseId;
    if (enterpriseId != null && enterpriseId != _lastLoadedEnterpriseId) {
      _lastLoadedEnterpriseId = enterpriseId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<TaskProvider>().streamEnterpriseTasks(enterpriseId);
      });
    }

    final taskProvider = context.watch<TaskProvider>();
    final allTasks = taskProvider.allTasks;
    final pending = taskProvider.pendingCount;
    final completed = taskProvider.completedCount;

    return GradientBackground(
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AppHeader(
              title: 'Tasks',
              type: AppHeaderType.primary,
              showAvatar: false,
              actions: [
                PopupMenuButton<String>(
                  icon: Icon(
                    Iconsax.more,
                    color: AppColors.textSecondary,
                    size: 22,
                  ),
                  color: AppColors.glassStrong,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: AppColors.glassBorder),
                  ),
                  onSelected: (value) {
                    if (value == 'fix') _runTaskMigration();
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'fix',
                      child: Row(
                        children: [
                          Icon(Iconsax.refresh, size: 18, color: AppColors.warning),
                          const SizedBox(width: 10),
                          Text(
                            'Fix Missing Tasks',
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => context.push('/admin/create-task'),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.4),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                      border: Border.all(
                        color: AppColors.textPrimary.withValues(alpha: 0.2),
                      ),
                    ),
                    child: const Icon(
                      Iconsax.add,
                      color: AppColors.textPrimary,
                      size: 22,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Quick Stats
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  _buildGlassStatCard(
                    Iconsax.task_square,
                    AppColors.info,
                    '${allTasks.length}',
                    'Total',
                  ),
                  const SizedBox(width: 12),
                  _buildGlassStatCard(
                    Iconsax.timer_1,
                    AppColors.warning,
                    '$pending',
                    'Pending',
                  ),
                  const SizedBox(width: 12),
                  _buildGlassStatCard(
                    Iconsax.tick_circle,
                    AppColors.success,
                    '$completed',
                    'Done',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Content Panel
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.glassPrimary,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(32),
                  ),
                  border: Border(
                    top: BorderSide(color: AppColors.glassBorder),
                    left: BorderSide(color: AppColors.glassBorder),
                    right: BorderSide(color: AppColors.glassBorder),
                  ),
                  boxShadow: AppShadows.glass,
                ),
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(32),
                  ),
                  child: taskProvider.isLoading
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: AppColors.primary,
                          ),
                        )
                      : SingleChildScrollView(
                          padding: EdgeInsets.only(
                            left: 20,
                            right: 20,
                            top: 24,
                            bottom: 120,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Section Header
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Recent Tasks',
                                    style: AppTypography.h3.copyWith(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.glassStrong,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: AppColors.glassBorder,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Iconsax.filter,
                                          size: 14,
                                          color: AppColors.textSecondary,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Filter',
                                          style:
                                              AppTypography.caption.copyWith(
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),

                              // Task List
                              if (allTasks.isEmpty)
                                Center(
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 48),
                                    child: Column(
                                      children: [
                                        Icon(
                                          Iconsax.task_square,
                                          size: 48,
                                          color: AppColors.textTertiary,
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          'No tasks yet',
                                          style: AppTypography.bodyMedium
                                              .copyWith(
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              else
                                ...allTasks.map(
                                  (task) => _buildTaskCard(task),
                                ),
                            ],
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

  Widget _buildGlassStatCard(
    IconData icon,
    Color color,
    String value,
    String label,
  ) {
    return Expanded(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.glassPrimary,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Column(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: color.withValues(alpha: 0.3)),
                  ),
                  child: Icon(icon, size: 18, color: color),
                ),
                const SizedBox(height: 12),
                Text(
                  value,
                  style: AppTypography.h3.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  label,
                  style: AppTypography.overline.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTaskCard(TaskModel task) {
    final completed = task.isCompleted;

    Color priorityColor;
    switch (task.priority) {
      case 'high':
        priorityColor = AppColors.error;
        break;
      case 'medium':
        priorityColor = AppColors.warning;
        break;
      default:
        priorityColor = AppColors.success;
    }

    // Format due date
    String dueDateLabel;
    if (task.isDueToday) {
      dueDateLabel = 'Today';
    } else {
      dueDateLabel = DateFormat('MMM d').format(task.dueDate);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.glassPrimary,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.glassBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Priority indicator strip
              Container(
                width: 6,
                color: completed ? AppColors.textDisabled : priorityColor,
              ),
              // Card content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      // Checkbox
                      GestureDetector(
                        onTap: completed
                            ? null
                            : () => context
                                .read<TaskProvider>()
                                .completeTask(task.id),
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: completed
                                ? AppColors.success
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: completed
                                  ? AppColors.success
                                  : AppColors.textDisabled,
                              width: 2,
                            ),
                          ),
                          child: completed
                              ? const Icon(Iconsax.check,
                                  color: AppColors.textPrimary, size: 16)
                              : null,
                        ),
                      ),
                      const SizedBox(width: 16),

                      // Content
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              task.title,
                              style: AppTypography.bodyMedium.copyWith(
                                decoration: completed
                                    ? TextDecoration.lineThrough
                                    : null,
                                color: completed
                                    ? AppColors.textTertiary
                                    : AppColors.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  Iconsax.user,
                                  size: 12,
                                  color: AppColors.textSecondary,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    task.assignedToName ?? task.assignedTo,
                                    style: AppTypography.caption.copyWith(
                                      color: AppColors.textSecondary,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Icon(
                                  Iconsax.calendar_1,
                                  size: 12,
                                  color: AppColors.textSecondary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  dueDateLabel,
                                  style: AppTypography.caption.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Priority Badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: (completed
                                  ? AppColors.textDisabled
                                  : priorityColor)
                              .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: (completed
                                    ? AppColors.textDisabled
                                    : priorityColor)
                                .withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          completed
                              ? 'Done'
                              : task.priority[0].toUpperCase() +
                                  task.priority.substring(1),
                          style: AppTypography.overline.copyWith(
                            color: completed
                                ? AppColors.textDisabled
                                : priorityColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
