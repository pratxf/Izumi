import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:izumi/core/ui/app_icons.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_shadows.dart';
import '../../core/constants/app_typography.dart';
import '../../core/constants/app_spacing.dart';
import '../../models/task_model.dart';
import '../../models/group_model.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/task_provider.dart';
import '../../providers/group_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../widgets/glass/gradient_background.dart';
import '../../widgets/glass/glass_chip.dart';
import '../../widgets/navigation/app_header.dart';
import 'package:go_router/go_router.dart';

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
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initProviders();
    });
  }

  void _initProviders() {
    if (_initialized) return;
    _initialized = true;
    final auth = context.read<AuthProvider>();
    final enterpriseId =
        auth.enterpriseId ?? auth.currentUser?.enterpriseId ?? '';
    if (enterpriseId.isEmpty) return;

    // Stream enterprise tasks for live updates
    final taskProvider = context.read<TaskProvider>();
    taskProvider.streamEnterpriseTasks(enterpriseId);

    // Load groups and employees for team lead view
    if (!widget.isAdmin) {
      context.read<GroupProvider>().loadGroups(enterpriseId);
      final dashboardProvider = context.read<DashboardProvider>();
      if (dashboardProvider.employees.isEmpty) {
        dashboardProvider.initDashboard(enterpriseId);
      }
    }
  }

  String _dueLabel(DateTime dueDate) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(dueDate.year, dueDate.month, dueDate.day);
    final diff = due.difference(today).inDays;
    if (diff == 0) return 'Due Today';
    if (diff == 1) return 'Due Tomorrow';
    if (diff < 0) return 'Overdue';
    return DateFormat('MMM dd').format(dueDate);
  }

  @override
  Widget build(BuildContext context) {
    final taskProvider = context.watch<TaskProvider>();
    final allTasks = taskProvider.allTasks;

    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              AppHeader(
                title: widget.isAdmin ? 'Monitor' : 'Tasks',
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
                            AppIcons.add,
                            size: 18,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Assign Task',
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
                        _buildAdminOverviewCard(allTasks),
                        const SizedBox(height: 12),
                        _buildAdminTabBar(),
                        const SizedBox(height: 12),
                        _buildAdminStatusFilters(),
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            children: _filteredAdminItems(allTasks)
                                .map(_buildAdminTaskCard)
                                .toList(),
                          ),
                        ),
                        if (_filteredAdminItems(allTasks).isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 32),
                            child: Center(
                              child: Text(
                                'No ${_adminTab == 'tasks' ? 'tasks' : 'follow-ups'} found',
                                style: AppTypography.bodyMedium.copyWith(
                                  color: AppColors.textTertiary,
                                ),
                              ),
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
                    child: _buildTeamLeadContent(allTasks),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Admin View Helpers ──

  Widget _buildAdminOverviewCard(List<TaskModel> allTasks) {
    final bool isFollowUps = _adminTab == 'followups';
    final items = isFollowUps
        ? allTasks.where((t) => t.isFollowup).toList()
        : allTasks.where((t) => t.isTask).toList();
    final pendingCount = items.where((t) => t.isPending).length;
    final leftLabel = isFollowUps ? 'Total Follow-ups' : 'Total Tasks';
    final leftValue = items.length.toString();
    final rightLabel = isFollowUps ? 'Pending Follow-ups' : 'Pending Tasks';
    final rightValue = pendingCount.toString();

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

  List<TaskModel> _filteredAdminItems(List<TaskModel> allTasks) {
    final items = _adminTab == 'tasks'
        ? allTasks.where((t) => t.isTask).toList()
        : allTasks.where((t) => t.isFollowup).toList();
    if (_adminStatus == 'completed') {
      return items.where((t) => t.isCompleted).toList();
    }
    if (_adminStatus == 'pending') {
      return items.where((t) => t.isPending).toList();
    }
    return items;
  }

  Widget _buildAdminTabButton(
      {required String label, required String value}) {
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

  Widget _buildAdminTaskCard(TaskModel task) {
    final priorityColor = task.priority == 'high'
        ? AppColors.critical
        : task.priority == 'medium'
            ? AppColors.warning
            : AppColors.primary;
    final isCompleted = task.isCompleted;

    // Look up assignee details from DashboardProvider
    final dashboardProvider = context.read<DashboardProvider>();
    final employee = dashboardProvider.employees
        .where((e) => e.id == task.assignedTo)
        .firstOrNull;
    final assigneeName =
        task.assignedToName ?? employee?.name ?? 'Unassigned';
    final assigneeRole = employee?.displayRole ?? 'Employee';
    final initials = employee?.initials ??
        assigneeName
            .split(' ')
            .map((p) => p.isNotEmpty ? p[0] : '')
            .take(2)
            .join()
            .toUpperCase();

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
                            task.priority.toUpperCase(),
                            style: AppTypography.overline.copyWith(
                              color: priorityColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _dueLabel(task.dueDate),
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      task.title,
                      style: AppTypography.h3.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              _buildDeleteIconButton(task.id),
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
                        initials,
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
                        assigneeName,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        assigneeRole,
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
                      isCompleted ? AppIcons.check : AppIcons.timer,
                      size: 14,
                      color: isCompleted
                          ? AppColors.success
                          : AppColors.textSecondary,
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

  // ── Team Lead View Helpers ──

  Widget _buildTeamLeadContent(List<TaskModel> allTasks) {
    final groupProvider = context.watch<GroupProvider>();
    final dashboardProvider = context.watch<DashboardProvider>();

    final tasks = allTasks.where((t) => t.isTask).toList();
    final followUps = allTasks.where((t) => t.isFollowup).toList();

    // Separate group tasks (with groupId) from individual tasks
    final groupTasks = tasks.where((t) => t.groupId != null).toList();
    final individualTasks = tasks.where((t) => t.groupId == null).toList();
    final groupFollowUps = followUps.where((t) => t.groupId != null).toList();
    final individualFollowUps =
        followUps.where((t) => t.groupId == null).toList();

    // Group tasks by groupId
    final tasksByGroup = <String, List<TaskModel>>{};
    for (final t in groupTasks) {
      tasksByGroup.putIfAbsent(t.groupId!, () => []).add(t);
    }
    final followUpsByGroup = <String, List<TaskModel>>{};
    for (final t in groupFollowUps) {
      followUpsByGroup.putIfAbsent(t.groupId!, () => []).add(t);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        if (groupTasks.isNotEmpty || individualTasks.isNotEmpty)
          _buildSection(
            title: 'Task Monitor',
            groupTasksByGroup: tasksByGroup,
            individualTasks: individualTasks,
            groups: groupProvider.groups,
            employees: dashboardProvider.employees,
          ),
        if (groupFollowUps.isNotEmpty || individualFollowUps.isNotEmpty)
          _buildSection(
            title: 'Follow Up Monitor',
            groupTasksByGroup: followUpsByGroup,
            individualTasks: individualFollowUps,
            groups: groupProvider.groups,
            employees: dashboardProvider.employees,
          ),
        if (allTasks.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
            child: Center(
              child: Text(
                'No tasks to monitor',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ),
          ),
      ],
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
        if (value == _selectedFilter) return;
        setState(() => _selectedFilter = value);
        if (value == 'task') {
          context.go('/employee/tasks');
        }
      },
    );
  }

  Widget _buildSection({
    required String title,
    required Map<String, List<TaskModel>> groupTasksByGroup,
    required List<TaskModel> individualTasks,
    required List<GroupModel> groups,
    required List<UserModel> employees,
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
          ...groupTasksByGroup.entries.map((entry) {
            final groupId = entry.key;
            final tasksInGroup = entry.value;
            final group =
                groups.where((g) => g.id == groupId).firstOrNull;
            final groupName = group?.name ?? 'Group';
            final completedCount =
                tasksInGroup.where((t) => t.isCompleted).length;
            final totalCount = tasksInGroup.length;

            // Build assignee data from employees
            final assignees = <Map<String, dynamic>>[];
            for (final task in tasksInGroup) {
              final emp = employees
                  .where((e) => e.id == task.assignedTo)
                  .firstOrNull;
              assignees.add({
                'name': task.assignedToName ?? emp?.name ?? 'Unknown',
                'status': task.isCompleted ? 'Done' : 'Pending',
                'time': task.completedAt != null
                    ? DateFormat('h:mm a').format(task.completedAt!)
                    : null,
                'initials': emp?.initials ?? '?',
                'isDone': task.isCompleted,
              });
            }

            return _buildGroupTaskCard({
              'title': tasksInGroup.first.title,
              'group': groupName,
              'completed': completedCount,
              'total': totalCount,
              'assignees': assignees,
              'taskIds': tasksInGroup.map((t) => t.id).toList(),
            });
          }),
          if (groupTasksByGroup.isNotEmpty && individualTasks.isNotEmpty)
            const SizedBox(height: 12),
          ...individualTasks.map((task) {
            final emp = employees
                .where((e) => e.id == task.assignedTo)
                .firstOrNull;
            return _buildIndividualTaskCard({
              'title': task.title,
              'assignee': task.assignedToName ?? emp?.name ?? 'Unassigned',
              'due': _dueLabel(task.dueDate),
              'priority': task.priority[0].toUpperCase() +
                  task.priority.substring(1),
            });
          }),
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
                            AppIcons.people,
                            size: 16,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              '${task['group']} \u2022 $total members',
                              style: AppTypography.caption,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                _buildCardMenu(task['taskIds'] as List<String>? ?? []),
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
                        const Icon(AppIcons.check,
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
                        const Icon(AppIcons.timer,
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
                        const Icon(AppIcons.user,
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
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(AppIcons.calendar,
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
    final String initials = assignee['initials'] ?? '?';
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
                      backgroundColor:
                          AppColors.primary.withValues(alpha: 0.15),
                      child: Text(
                        initials,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
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
                          AppIcons.timer,
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
          if (isDone && assignee['time'] != null)
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

  Widget _buildCardMenu(List<String> taskIds) {
    return PopupMenuButton<String>(
      onSelected: (value) {
        if (value == 'delete' && taskIds.isNotEmpty) {
          _confirmDeleteTask(taskIds.first);
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
          AppIcons.more,
          color: AppColors.textPrimary,
          size: 18,
        ),
      ),
    );
  }

  Widget _buildDeleteIconButton(String taskId) {
    return GestureDetector(
      onTap: () => _confirmDeleteTask(taskId),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: AppColors.glassPrimary,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: const Icon(
          AppIcons.trash,
          color: AppColors.critical,
          size: 18,
        ),
      ),
    );
  }

  void _confirmDeleteTask(String taskId) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: AlertDialog(
          backgroundColor: AppColors.glassStrong,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Delete Task',
            style: AppTypography.h3.copyWith(color: AppColors.textPrimary),
          ),
          content: Text(
            'Are you sure you want to delete this task? This action cannot be undone.',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Cancel',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final success = await context.read<TaskProvider>().deleteTask(taskId);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        success ? 'Task deleted' : 'Failed to delete task',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                      backgroundColor: success ? AppColors.glassStrong : AppColors.critical,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              child: Text(
                'Delete',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.critical,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openCreateTaskScreen() {
    context.push('/admin/create-task', extra: {
      'isTeamLead': !widget.isAdmin,
    });
  }
}
