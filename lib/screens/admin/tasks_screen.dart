import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_shadows.dart';
import '../../core/constants/app_typography.dart';
import '../../widgets/glass/gradient_background.dart';
import '../../widgets/navigation/app_header.dart';
import 'create_task_screen.dart';

/// Tasks Screen (Admin) - Enterprise Dark Glass Design
/// Task overview and creation
class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  final List<Map<String, dynamic>> _tasks = [
    {
      'title': 'Visit Sharma Distributors',
      'assignee': 'Rahul Kumar',
      'priority': 'High',
      'completed': false,
      'dueDate': 'Today',
    },
    {
      'title': 'Check inventory at depot',
      'assignee': 'Priya Singh',
      'priority': 'Medium',
      'completed': false,
      'dueDate': 'Tomorrow',
    },
    {
      'title': 'Meet with new farmer',
      'assignee': 'Amit Sharma',
      'priority': 'Low',
      'completed': true,
      'dueDate': 'Yesterday',
    },
  ];

  @override
  Widget build(BuildContext context) {
    final pending = _tasks.where((t) => !t['completed']).length;
    final completed = _tasks.where((t) => t['completed']).length;

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
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const CreateTaskScreen(),
                      ),
                    );
                  },
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.4),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                      border: Border.all(
                        color: AppColors.textPrimary.withOpacity(0.2),
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
                    AppColors.info, // Blue
                    '${_tasks.length}',
                    'Total',
                  ),
                  const SizedBox(width: 12),
                  _buildGlassStatCard(
                    Iconsax.timer_1,
                    AppColors.warning, // Orange
                    '$pending',
                    'Pending',
                  ),
                  const SizedBox(width: 12),
                  _buildGlassStatCard(
                    Iconsax.tick_circle,
                    AppColors.success, // Green
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
                  child: SingleChildScrollView(
                    padding: EdgeInsets.only(
                      left: 20,
                      right: 20,
                      top: 24,
                      bottom: 120, // Space for bottom nav
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Section Header
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                                    style: AppTypography.caption.copyWith(
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
                        ..._tasks.map(
                          (task) => _buildTaskCard(
                            task['title'],
                            task['assignee'],
                            task['priority'],
                            task['completed'],
                            task['dueDate'],
                          ),
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
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: color.withOpacity(0.3)),
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

  Widget _buildTaskCard(
    String title,
    String assignee,
    String priority,
    bool completed,
    String dueDate,
  ) {
    Color priorityColor;
    switch (priority) {
      case 'High':
        priorityColor = AppColors.error;
        break;
      case 'Medium':
        priorityColor = AppColors.warning;
        break;
      default:
        priorityColor = AppColors.success; // Low priority is green/good
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.glassPrimary,
        borderRadius: BorderRadius.circular(20),
        border: Border(
          left: BorderSide(
            color: completed ? AppColors.textDisabled : priorityColor,
            width: 6,
          ),
          top: BorderSide(color: AppColors.glassBorder, width: 1),
          right: BorderSide(color: AppColors.glassBorder, width: 1),
          bottom: BorderSide(color: AppColors.glassBorder, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Checkbox
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: completed ? AppColors.success : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: completed ? AppColors.success : AppColors.textDisabled,
                width: 2,
              ),
            ),
            child: completed
                ? const Icon(Icons.check, color: AppColors.textPrimary, size: 16)
                : null,
          ),
          const SizedBox(width: 16),

          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.bodyMedium.copyWith(
                    decoration: completed ? TextDecoration.lineThrough : null,
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
                    Text(
                      assignee,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
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
                      dueDate,
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
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: (completed ? AppColors.textDisabled : priorityColor)
                  .withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: (completed ? AppColors.textDisabled : priorityColor)
                    .withOpacity(0.3),
              ),
            ),
            child: Text(
              completed ? 'Done' : priority,
              style: AppTypography.overline.copyWith(
                color: completed ? AppColors.textDisabled : priorityColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}


