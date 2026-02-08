import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_shadows.dart';
import '../../core/constants/app_typography.dart';
import '../../widgets/glass/gradient_background.dart';
import '../../widgets/glass/glass_chip.dart';
import '../../widgets/navigation/app_header.dart';
import '../admin/create_task_screen.dart';
import 'todo_screen.dart';

/// Monitor Screen - Team Lead task monitoring view
/// Standard Dark Glass Design
class MonitorScreen extends StatefulWidget {
  const MonitorScreen({super.key});

  @override
  State<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends State<MonitorScreen> {
  String _selectedFilter = 'monitor';

  final List<Map<String, dynamic>> _assignees = [
    {
      'name': 'Rajesh Kumar',
      'status': 'Done',
      'time': '10:42 AM',
      'avatar': 'https://i.pravatar.cc/150?img=11',
      'isDone': true,
    },
    {
      'name': 'Priya Sharma',
      'status': 'Done',
      'time': '11:15 AM',
      'avatar': 'https://i.pravatar.cc/150?img=5',
      'isDone': true,
    },
    {
      'name': 'Amit Patel',
      'status': 'Done',
      'time': '12:30 PM',
      'avatar': 'https://i.pravatar.cc/150?img=12',
      'isDone': true,
    },
    {
      'name': 'Sunita Rao',
      'status': 'Pending',
      'time': null,
      'avatar': 'https://i.pravatar.cc/150?img=9',
      'isDone': false,
    },
    {
      'name': 'Rakesh Gupta',
      'status': 'Pending',
      'time': null,
      'avatar': 'https://i.pravatar.cc/150?img=8',
      'isDone': false,
    },
  ];

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
                title: 'Tasks',
                type: AppHeaderType.primary,
                showAvatar: false,
                actions: [
                  GestureDetector(
                    onTap: _openCreateTaskScreen,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.glassPrimary,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.glassBorder),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.add,
                            size: 18,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Create Task',
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              // Filter Tabs
              _buildFilterTabs(),
              const SizedBox(height: 16),

              // Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 120),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Main Task Card
                      _buildTaskCard(),
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

  Widget _buildFilterTabs() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: Row(
        children: [
          _buildFilterPill('Task', 'task'),
          const SizedBox(width: 12),
          _buildFilterPill('Monitor', 'monitor'),
        ],
      ),
    );
  }

  Widget _buildFilterPill(String label, String value) {
    final isSelected = _selectedFilter == value;
    return GlassChip(
      label: label,
      selected: isSelected,
      onTap: () {
        setState(() => _selectedFilter = value);
        if (value == 'task') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const TodoScreen(isTeamLead: true),
            ),
          );
        }
      },
    );
  }

  Widget _buildTaskCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: AppColors.glassPrimary,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.glassBorder),
        boxShadow: AppShadows.glass,
      ),
      child: Column(
        children: [
          // Title Section (no cover image)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Visit Region A', style: AppTypography.h2),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.group,
                          color: AppColors.textSecondary,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Assigned to: 5 employees',
                          style: AppTypography.caption,
                        ),
                      ],
                    ),
                  ],
                ),
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.glassPrimary,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.glassBorder),
                  ),
                  child: const Icon(
                    Icons.more_horiz,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),

          // Progress Section
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.check_circle,
                            color: AppColors.success, size: 20),
                        const SizedBox(width: 6),
                        Text(
                          'Completed: 3/5',
                          style: AppTypography.bodySmall.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const Icon(Icons.hourglass_top,
                            color: AppColors.primary, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          'Pending: 2',
                          style: AppTypography.caption.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: LinearProgressIndicator(
                    minHeight: 10,
                    value: 0.6,
                    backgroundColor: AppColors.glassBorder,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: AppColors.glassBorder),

          // Assignees List
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Column(
              children: _assignees
                  .map((assignee) => _buildAssigneeRow(assignee))
                  .toList(),
            ),
          ),

          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildAssigneeRow(Map<String, dynamic> assignee) {
    final bool isDone = assignee['isDone'];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Stack(
                children: [
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isDone ? AppColors.success : AppColors.primary,
                        width: 2,
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 20,
                      backgroundImage: NetworkImage(assignee['avatar']),
                    ),
                  ),
                  if (!isDone)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: AppColors.glassPrimary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.hourglass_top,
                          color: AppColors.primary,
                          size: 14,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    assignee['name'],
                    style: AppTypography.bodySmall.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    isDone ? 'Done' : 'Pending',
                    style: AppTypography.caption.copyWith(
                      color: isDone ? AppColors.success : AppColors.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (isDone)
            Text(
              assignee['time'],
              style: AppTypography.caption.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
        ],
      ),
    );
  }

  // New assignment removed per latest spec
  void _openCreateTaskScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreateTaskScreen()),
    );
  }

}

