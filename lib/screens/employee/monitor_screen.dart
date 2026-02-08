import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_shadows.dart';
import '../../core/constants/app_typography.dart';
import '../../core/constants/app_spacing.dart';
import '../../widgets/glass/gradient_background.dart';
import '../../widgets/glass/glass_chip.dart';
import '../../widgets/navigation/app_header.dart';
import '../admin/create_task_screen.dart';
import 'todo_screen.dart';

/// Monitor Screen - Team Lead monitoring view
/// Unified enterprise glass styling
class MonitorScreen extends StatefulWidget {
  final bool showFilter;
  final bool isAdmin;

  const MonitorScreen({
    super.key,
    this.showFilter = true,
    this.isAdmin = false,
  });

  @override
  State<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends State<MonitorScreen> {
  String _selectedFilter = 'monitor';
  String _adminTab = 'tasks';
  String _adminStatus = 'all';

  final List<Map<String, dynamic>> _adminMonitorTasks = [
    {
      'priority': 'High',
      'dueLabel': 'Due Today',
      'title': 'Site Inspection - Sector 7',
      'assignee': 'John Doe',
      'role': 'Field Agent',
      'isCompleted': true,
    },
    {
      'priority': 'Medium',
      'dueLabel': 'Due Tomorrow',
      'title': 'Inventory Check - Warehouse B',
      'assignee': 'Sarah Miller',
      'role': 'Logistics Lead',
      'isCompleted': false,
    },
    {
      'priority': 'Low',
      'dueLabel': 'Dec 12',
      'title': 'Client Onboarding - Fresh Mart',
      'assignee': 'Rahul Jain',
      'role': 'Sales Executive',
      'isCompleted': false,
    },
  ];

  final List<Map<String, dynamic>> _adminMonitorFollowUps = [
    {
      'priority': 'High',
      'dueLabel': 'Due Today',
      'title': 'Follow-up: XYZ Distributor',
      'assignee': 'Neha Verma',
      'role': 'Field Supervisor',
      'isCompleted': true,
    },
    {
      'priority': 'Medium',
      'dueLabel': 'Due Tomorrow',
      'title': 'Follow-up: Green Valley Farms',
      'assignee': 'Suresh Patel',
      'role': 'Area Lead',
      'isCompleted': false,
    },
  ];
  final List<Map<String, dynamic>> _adminGroupTasks = [
    {
      'title': 'Visit Region A',
      'group': 'North Zone',
      'completed': 3,
      'total': 5,
      'assignees': [
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
      ],
    },
  ];

  final List<Map<String, dynamic>> _adminIndividualTasks = [
    {
      'title': 'Soil Sample Check',
      'assignee': 'Rahul Kumar',
      'due': '05 Feb 2026',
      'priority': 'High',
    },
  ];

  final List<Map<String, dynamic>> _leadGroupTasks = [
    {
      'title': 'Warehouse Inventory',
      'group': 'East Cluster',
      'completed': 2,
      'total': 4,
      'assignees': [
        {
          'name': 'Neha Verma',
          'status': 'Done',
          'time': '09:10 AM',
          'avatar': 'https://i.pravatar.cc/150?img=25',
          'isDone': true,
        },
        {
          'name': 'Suresh Patel',
          'status': 'Done',
          'time': '09:52 AM',
          'avatar': 'https://i.pravatar.cc/150?img=30',
          'isDone': true,
        },
        {
          'name': 'Amit Sharma',
          'status': 'Pending',
          'time': null,
          'avatar': 'https://i.pravatar.cc/150?img=33',
          'isDone': false,
        },
        {
          'name': 'Neeraj Singh',
          'status': 'Pending',
          'time': null,
          'avatar': 'https://i.pravatar.cc/150?img=36',
          'isDone': false,
        },
      ],
    },
  ];

  final List<Map<String, dynamic>> _leadIndividualTasks = [
    {
      'title': 'Retail Visit - Sector 45',
      'assignee': 'Priya Singh',
      'due': '06 Feb 2026',
      'priority': 'Medium',
    },
  ];

  final List<Map<String, dynamic>> _followUpGroupTasks = [
    {
      'title': 'Follow-up: XYZ Farmers',
      'group': 'South Zone',
      'completed': 1,
      'total': 3,
      'assignees': [
        {
          'name': 'Ayesha Khan',
          'status': 'Done',
          'time': '01:15 PM',
          'avatar': 'https://i.pravatar.cc/150?img=44',
          'isDone': true,
        },
        {
          'name': 'Vikram Singh',
          'status': 'Pending',
          'time': null,
          'avatar': 'https://i.pravatar.cc/150?img=47',
          'isDone': false,
        },
        {
          'name': 'Rohan Mehta',
          'status': 'Pending',
          'time': null,
          'avatar': 'https://i.pravatar.cc/150?img=49',
          'isDone': false,
        },
      ],
    },
  ];

  final List<Map<String, dynamic>> _followUpIndividualTasks = [
    {
      'title': 'Follow-up Call - ABC Distributor',
      'assignee': 'Sunita Rao',
      'due': 'Today',
      'priority': 'High',
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
                title: widget.isAdmin ? 'Monitor' : 'Todo',
                type: AppHeaderType.primary,
                showAvatar: false,
                showLeading: false,
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
              if (widget.isAdmin)
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 120),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 12),
                        _buildAdminOverviewCard(),
                        const SizedBox(height: 12),
                        _buildAdminTabBar(),
                        const SizedBox(height: 12),
                        _buildAdminStatusFilters(),
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            children: _filteredAdminItems()
                                .map(_buildAdminTaskCard)
                                .toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else ...[
                if (widget.showFilter) _buildFilterTabs(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 120),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 12),
                        _buildSection(
                          title: 'Admin Task Monitor',
                          groupTasks: _adminGroupTasks,
                          individualTasks: _adminIndividualTasks,
                        ),
                        _buildSection(
                          title: 'Team Lead Task Monitor',
                          groupTasks: _leadGroupTasks,
                          individualTasks: _leadIndividualTasks,
                        ),
                        _buildSection(
                          title: 'Follow Up Monitor',
                          groupTasks: _followUpGroupTasks,
                          individualTasks: _followUpIndividualTasks,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAdminOverviewCard() {
    final bool isFollowUps = _adminTab == 'followups';
    final List<Map<String, dynamic>> items =
        isFollowUps ? _adminMonitorFollowUps : _adminMonitorTasks;
    final int pendingCount =
        items.where((item) => item['isCompleted'] == false).length;
    final String leftLabel = isFollowUps ? 'Total Follow-ups' : 'Total Tasks';
    final String leftValue = items.length.toString();
    final String rightLabel =
        isFollowUps ? 'Pending Follow-ups' : 'Pending Tasks';
    final String rightValue = pendingCount.toString();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.glassPrimary,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.glassBorder),
          boxShadow: AppShadows.glass,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    leftValue,
                    style: AppTypography.displayLarge.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    leftLabel,
                    style: AppTypography.overline.copyWith(
                      color: AppColors.textSecondary,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 1,
              height: 44,
              color: AppColors.glassBorder,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    rightValue,
                    style: AppTypography.displayLarge.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    rightLabel,
                    textAlign: TextAlign.center,
                    style: AppTypography.overline.copyWith(
                      color: AppColors.textSecondary,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminTabBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          _buildAdminTabButton(label: 'Tasks', value: 'tasks'),
          const SizedBox(width: 16),
          _buildAdminTabButton(label: 'Follow-ups', value: 'followups'),
        ],
      ),
    );
  }

  Widget _buildAdminStatusFilters() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          GlassChip(
            label: 'All',
            selected: _adminStatus == 'all',
            onTap: () => setState(() => _adminStatus = 'all'),
          ),
          const SizedBox(width: 10),
          GlassChip(
            label: 'Completed',
            selected: _adminStatus == 'completed',
            onTap: () => setState(() => _adminStatus = 'completed'),
          ),
          const SizedBox(width: 10),
          GlassChip(
            label: 'Pending',
            selected: _adminStatus == 'pending',
            onTap: () => setState(() => _adminStatus = 'pending'),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _filteredAdminItems() {
    final List<Map<String, dynamic>> items =
        _adminTab == 'tasks' ? _adminMonitorTasks : _adminMonitorFollowUps;
    if (_adminStatus == 'completed') {
      return items.where((item) => item['isCompleted'] == true).toList();
    }
    if (_adminStatus == 'pending') {
      return items.where((item) => item['isCompleted'] == false).toList();
    }
    return items;
  }

  Widget _buildAdminTabButton({required String label, required String value}) {
    final bool isActive = _adminTab == value;
    return GestureDetector(
      onTap: () => setState(() => _adminTab = value),
      child: Container(
        padding: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? AppColors.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: AppTypography.bodySmall.copyWith(
            color: isActive ? AppColors.textPrimary : AppColors.textSecondary,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildAdminTaskCard(Map<String, dynamic> task) {
    final String priority = task['priority'] as String;
    final Color priorityColor = priority == 'High'
        ? AppColors.critical
        : priority == 'Medium'
            ? AppColors.warning
            : AppColors.primary;
    final bool isCompleted = task['isCompleted'] as bool;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.glassPrimary,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.glassBorder),
        boxShadow: AppShadows.glass,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: priorityColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: priorityColor.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Text(
                            priority.toUpperCase(),
                            style: AppTypography.overline.copyWith(
                              color: priorityColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          task['dueLabel'] as String,
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      task['title'] as String,
                      style: AppTypography.h3.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              _buildCardMenu(),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: priorityColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: priorityColor.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        task['assignee']
                            .toString()
                            .split(' ')
                            .map((part) => part.isNotEmpty ? part[0] : '')
                            .take(2)
                            .join()
                            .toUpperCase(),
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task['assignee'] as String,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        task['role'] as String,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isCompleted
                      ? AppColors.success.withValues(alpha: 0.2)
                      : AppColors.glassHover,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                  border: Border.all(
                    color: isCompleted
                        ? AppColors.success.withValues(alpha: 0.4)
                        : AppColors.glassBorder,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isCompleted ? Icons.check_circle : Icons.schedule,
                      size: 14,
                      color:
                          isCompleted ? AppColors.success : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isCompleted ? 'Completed' : 'Pending',
                      style: AppTypography.caption.copyWith(
                        color: isCompleted
                            ? AppColors.success
                            : AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
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
        if (value == _selectedFilter) {
          return;
        }
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

  Widget _buildSection({
    required String title,
    required List<Map<String, dynamic>> groupTasks,
    required List<Map<String, dynamic>> individualTasks,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTypography.h3.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: 12),
          ...groupTasks.map(_buildGroupTaskCard),
          if (groupTasks.isNotEmpty && individualTasks.isNotEmpty)
            const SizedBox(height: 12),
          ...individualTasks.map(_buildIndividualTaskCard),
        ],
      ),
    );
  }

  Widget _buildGroupTaskCard(Map<String, dynamic> task) {
    final int completed = task['completed'] as int;
    final int total = task['total'] as int;
    final double progress = total == 0 ? 0 : completed / total;
    final List<Map<String, dynamic>> assignees =
        (task['assignees'] as List).cast<Map<String, dynamic>>();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.glassPrimary,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.glassBorder),
        boxShadow: AppShadows.glass,
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(task['title'], style: AppTypography.h2),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(
                            Icons.groups_2,
                            size: 16,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              '${task['group']} • $total members',
                              style: AppTypography.caption,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                _buildCardMenu(),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.check_circle,
                            color: AppColors.success, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          'Completed: $completed/$total',
                          style: AppTypography.bodySmall.copyWith(
                            fontWeight: FontWeight.w600,
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
                          'Pending: ${total - completed}',
                          style: AppTypography.caption.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    minHeight: 8,
                    value: progress,
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Column(
              children: assignees
                  .map((assignee) => _buildAssigneeRow(assignee))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIndividualTaskCard(Map<String, dynamic> task) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.glassPrimary,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.glassBorder),
        boxShadow: AppShadows.glass,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(task['title'], style: AppTypography.h3),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.person_outline,
                            size: 16, color: AppColors.textSecondary),
                        const SizedBox(width: 6),
                        Text(
                          task['assignee'],
                          style: AppTypography.caption,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              _buildPriorityChip(task['priority'] as String),
              const SizedBox(width: 8),
              _buildCardMenu(),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.event,
                  size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(
                'Due: ${task['due']}',
                style: AppTypography.caption,
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.glassHover,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                  border: Border.all(color: AppColors.glassBorder),
                ),
                child: Text(
                  'Individual',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAssigneeRow(Map<String, dynamic> assignee) {
    final bool isDone = assignee['isDone'];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(6),
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
                      radius: 18,
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
                          size: 12,
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

  Widget _buildPriorityChip(String priority) {
    final Color chipColor = priority == 'High'
        ? AppColors.critical
        : priority == 'Medium'
            ? AppColors.warning
            : AppColors.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: chipColor.withValues(alpha: 0.4)),
      ),
      child: Text(
        priority,
        style: AppTypography.caption.copyWith(
          color: chipColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildCardMenu() {
    return PopupMenuButton<String>(
      onSelected: (value) {
        if (value == 'delete') {
          _showDeleteSnack();
        }
      },
      color: AppColors.glassPrimary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        side: BorderSide(color: AppColors.glassBorder),
      ),
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'delete',
          child: Text('Delete Task'),
        ),
      ],
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: AppColors.glassPrimary,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: const Icon(
          Icons.more_horiz,
          color: AppColors.textPrimary,
          size: 18,
        ),
      ),
    );
  }

  void _showDeleteSnack() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Task deleted',
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textPrimary,
          ),
        ),
        backgroundColor: AppColors.glassStrong,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _openCreateTaskScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreateTaskScreen(isTeamLead: true)),
    );
  }
}

