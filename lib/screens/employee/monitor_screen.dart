import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_shadows.dart';
import '../../core/constants/app_typography.dart';
import '../../widgets/glass/gradient_background.dart';
import '../../widgets/glass/glass_chip.dart';
import '../../widgets/navigation/app_header.dart';
import '../admin/create_task_screen.dart';

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
                        Icons.add,
                        color: AppColors.textPrimary,
                        size: 22,
                      ),
                    ),
                  ),
                ],
              ),

              // Filter Tabs
              _buildFilterTabs(),
              const SizedBox(height: 20),

              // Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 120),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          'My Group Tasks',
                          style: AppTypography.h3,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Main Task Card
                      _buildTaskCard(),
                      const SizedBox(height: 24),

                      // New Region Assignment Card
                      _buildNewAssignmentCard(),
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
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
      child: Row(
        children: [
          _buildFilterPill('All', 'all'),
          const SizedBox(width: 12),
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
      onTap: () => setState(() => _selectedFilter = value),
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
          // Map Image Header
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: SizedBox(
              height: 192,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    'https://lh3.googleusercontent.com/aida-public/AB6AXuAbg-MMgaGbKRQwM82KB0Uwq3QJBENjWPVBxBnrGUgEC9H8ZG9rT3MOMLNcaihnp-qGfTyXZhNc0h1duikkQ-8Wi5cTrRxfS0m5QR1FaaSqWxZ1lwUfEgTPZNAX9soE1WXVgX891oQ-vo6PYirMzy4LZ5LCbyjR90VIIQ6f1cCkoycNkym5oXmUaRMTuX3BowkIsxP16jm3eaF9rScJ_56dcZj0zqktSNuGLMPAER4tvJYnZk27RFg5p7Q7Ila7kYhTHn8mnrmrfNsp',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        Container(color: AppColors.background),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          AppColors.gradientStart.withValues(alpha: 0.8),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 16,
                    left: 24,
                    right: 24,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
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
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.glassPrimary,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.glassBorder,
                            ),
                          ),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: const Icon(
                              Icons.more_horiz,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
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

          // View Full Report Button
          GestureDetector(
            onTap: () {}, // Add functionality
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: AppColors.glassPrimary,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(24),
                ),
                border: Border(
                  top: BorderSide(color: AppColors.glassBorder),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'View Full Report',
                    style: AppTypography.buttonMedium.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.arrow_forward,
                    size: 18,
                    color: AppColors.primary,
                  ),
                ],
              ),
            ),
          ),
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

  Widget _buildNewAssignmentCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      height: 96,
      decoration: BoxDecoration(
        color: AppColors.glassPrimary,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.glassBorder),
        boxShadow: AppShadows.glass,
      ),
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_circle, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Text(
              'New Region Assignment',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openCreateTaskScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreateTaskScreen()),
    );
  }

}

