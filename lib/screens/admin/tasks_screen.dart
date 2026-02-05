import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_shadows.dart';
import '../../core/constants/app_typography.dart';
import '../../widgets/glass/gradient_background.dart';
import '../../widgets/buttons/primary_button.dart';

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

  void _showCreateTaskSheet() {
    final titleController = TextEditingController();
    String selectedAssignee = 'Rahul Kumar';
    String selectedPriority = 'Medium';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          decoration: BoxDecoration(
            color: AppColors.glassSlateStrong,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
            border: Border.all(color: AppColors.glassSlateBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 40,
                spreadRadius: 0,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.glassSlateBorder,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Create New Task',
                          style: AppTypography.h3.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: AppColors.glassSlateSoft,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.close,
                              color: AppColors.textSecondary,
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    // Task Title
                    Text(
                      'Task Title',
                      style: AppTypography.label.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: titleController,
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Enter task description',
                        hintStyle: AppTypography.bodyMedium.copyWith(
                          color: AppColors.textTertiary,
                        ),
                        filled: true,
                        fillColor: AppColors.glassSlateSoft,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.all(16),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Assignee Dropdown
                    Text(
                      'Assign To',
                      style: AppTypography.label.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: AppColors.glassSlateSoft,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.glassSlateBorder),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selectedAssignee,
                          isExpanded: true,
                          dropdownColor: AppColors.surface,
                          icon: Icon(
                            Icons.keyboard_arrow_down,
                            color: AppColors.textSecondary,
                          ),
                          style: AppTypography.bodyMedium.copyWith(
                            color: AppColors.textPrimary,
                          ),
                          items:
                              [
                                    'Rahul Kumar',
                                    'Priya Singh',
                                    'Amit Sharma',
                                    'Neha Verma',
                                  ]
                                  .map(
                                    (e) => DropdownMenuItem(
                                      value: e,
                                      child: Text(e),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (v) =>
                              setSheetState(() => selectedAssignee = v!),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Priority Selection
                    Text(
                      'Priority',
                      style: AppTypography.label.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: ['Low', 'Medium', 'High'].map((p) {
                        final isSelected = selectedPriority == p;
                        Color color;
                        switch (p) {
                          case 'High':
                            color = AppColors.error;
                            break;
                          case 'Medium':
                            color = AppColors.warning;
                            break;
                          default:
                            color = AppColors.success;
                        }
                        return Expanded(
                          child: GestureDetector(
                            onTap: () =>
                                setSheetState(() => selectedPriority = p),
                            child: Container(
                              margin: EdgeInsets.only(
                                right: p != 'High' ? 8 : 0,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? color.withOpacity(0.15)
                                    : AppColors.glassSlateSoft,
                                border: Border.all(
                                  color: isSelected
                                      ? color
                                      : AppColors.glassSlateBorder,
                                  width: isSelected ? 1.5 : 1,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: Text(
                                  p,
                                  style: AppTypography.bodySmall.copyWith(
                                    color: isSelected
                                        ? color
                                        : AppColors.textSecondary,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 32),
                    // Create Button
                    PrimaryButton(
                      label: 'Create Task',
                      onPressed: () {
                        if (titleController.text.isNotEmpty) {
                          setState(() {
                            _tasks.insert(0, {
                              'title': titleController.text,
                              'assignee': selectedAssignee,
                              'priority': selectedPriority,
                              'completed': false,
                              'dueDate': 'Today',
                            });
                          });
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('Task created successfully!'),
                              backgroundColor: AppColors.success,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          );
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pending = _tasks.where((t) => !t['completed']).length;
    final completed = _tasks.where((t) => t['completed']).length;

    return GradientBackground(
      isDark: true, // Strict dark mode
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tasks',
                        style: AppTypography.h1.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Manage team assignments',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: _showCreateTaskSheet,
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
                          color: Colors.white.withOpacity(0.2),
                        ),
                      ),
                      child: const Icon(
                        Iconsax.add,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                ],
              ),
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
                  color: AppColors.glassSlateSoft,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(32),
                  ),
                  border: Border(
                    top: BorderSide(color: AppColors.glassSlateBorder),
                    left: BorderSide(color: AppColors.glassSlateBorder),
                    right: BorderSide(color: AppColors.glassSlateBorder),
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
                                color: AppColors.glassSlateStrong,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppColors.glassSlateBorder,
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
              color: AppColors.glassSlateSoft,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.glassSlateBorder),
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
        color: AppColors.glassSlateSoft,
        borderRadius: BorderRadius.circular(20),
        border: Border(
          left: BorderSide(
            color: completed ? AppColors.textMuted : priorityColor,
            width: 6,
          ),
          top: BorderSide(color: AppColors.glassSlateBorder, width: 1),
          right: BorderSide(color: AppColors.glassSlateBorder, width: 1),
          bottom: BorderSide(color: AppColors.glassSlateBorder, width: 1),
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
                color: completed ? AppColors.success : AppColors.textMuted,
                width: 2,
              ),
            ),
            child: completed
                ? const Icon(Icons.check, color: Colors.white, size: 16)
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
              color: (completed ? AppColors.textMuted : priorityColor)
                  .withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: (completed ? AppColors.textMuted : priorityColor)
                    .withOpacity(0.3),
              ),
            ),
            child: Text(
              completed ? 'Done' : priority,
              style: AppTypography.overline.copyWith(
                color: completed ? AppColors.textMuted : priorityColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
