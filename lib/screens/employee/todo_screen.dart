import 'package:flutter/material.dart';
import 'package:izumi/core/ui/app_icons.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';
import '../../models/task_model.dart';
import '../../models/upload_status.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/task_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/team_provider.dart';
import '../../widgets/glass/gradient_background.dart';
import '../../widgets/glass/glass_chip.dart';
import '../../widgets/navigation/app_header.dart';
import '../../widgets/buttons/hold_button.dart';
import 'package:go_router/go_router.dart';

const _avatarColors = [
  Color(0xFF7C4DFF), // purple
  Color(0xFFE91E63), // pink
  Color(0xFFFF9800), // orange
  Color(0xFF009688), // teal
  Color(0xFF2196F3), // blue
  Color(0xFF4CAF50), // green
  Color(0xFFFF5722), // deep orange
  Color(0xFF9C27B0), // deep purple
];

/// Todo Screen - Redesigned per reference
/// Shows tasks and follow-ups with filter pills
class TodoScreen extends StatefulWidget {
  final bool isTeamLead;

  const TodoScreen({super.key, this.isTeamLead = false});

  @override
  State<TodoScreen> createState() => _TodoScreenState();
}

class _TodoScreenState extends State<TodoScreen> {
  bool _initialized = false;
  String _selectedTab = 'task';
  String _employeeStatus = 'all';
  String _leadView = 'my_work';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initProvider();
    });
  }

  void _initProvider() {
    if (_initialized) return;
    _initialized = true;
    final auth = context.read<AuthProvider>();
    final userId = auth.currentUser?.id ?? '';
    if (userId.isEmpty) return;
    context.read<TaskProvider>().streamTasks(userId);

    // Init team data for team leads. Employee list comes from
    // EnterpriseProvider (splash-gated bootstrap) — no per-screen fetch.
    if (widget.isTeamLead) {
      final enterpriseId =
          auth.enterpriseId ?? auth.currentUser?.enterpriseId ?? '';
      if (enterpriseId.isNotEmpty) {
        context.read<TeamProvider>().initTeam(enterpriseId, userId);
      }
    }
  }

  // Filter tasks by selected tab (task/followup) and status
  List<TaskModel> _getFilteredTasks(List<TaskModel> tasks) {
    var filtered = tasks.where((t) {
      if (_selectedTab == 'task') return !t.isFollowup;
      return t.isFollowup;
    }).toList();

    if (_employeeStatus == 'completed') {
      filtered = filtered.where((t) => t.isCompleted).toList();
    } else if (_employeeStatus == 'pending') {
      filtered = filtered.where((t) => !t.isCompleted).toList();
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final taskProvider = context.watch<TaskProvider>();
    final allTasks = taskProvider.allTasks;
    final filteredTasks = _getFilteredTasks(allTasks);

    return GradientBackground(
      child: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                AppHeader(
                  title: 'Tasks',
                  type: AppHeaderType.primary,
                  showAvatar: false,
                  showLeading: false,
                  actions: widget.isTeamLead
                      ? [
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
                                border:
                                    Border.all(color: AppColors.glassBorder),
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
                        ]
                      : null,
                ),
                const SizedBox(height: 8),

                if (!widget.isTeamLead)
                  const SizedBox(height: 4)
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    child: Row(
                      children: [
                        _buildLeadToggle('My Work', 'my_work'),
                        const SizedBox(width: 16),
                        _buildLeadToggle('Team Monitor', 'team_monitor'),
                      ],
                    ),
                  ),

                // Content
                Expanded(
                  child: taskProvider.isLoading && taskProvider.allTasks.isEmpty
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: AppColors.primary,
                          ),
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.only(
                            left: 20,
                            right: 20,
                            bottom: 120,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (widget.isTeamLead) ...[
                                _buildLeadContent(taskProvider),
                              ] else ...[
                                _buildEmployeeProgressCard(filteredTasks),
                                const SizedBox(height: 12),
                                _buildEmployeeTabs(),
                                const SizedBox(height: 12),
                                _buildEmployeeStatusFilters(),
                                const SizedBox(height: 12),
                                if (filteredTasks.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 60),
                                    child: Center(
                                      child: Text(
                                        'No tasks yet',
                                        style:
                                            AppTypography.bodyMedium.copyWith(
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ),
                                  )
                                else
                                  ...filteredTasks.map(
                                    (task) => Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 16),
                                      child: _buildEmployeeTaskCard(
                                          task, taskProvider),
                                    ),
                                  ),
                              ],
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Employee UI ──────────────────────────────────────────────

  Widget _buildEmployeeProgressCard(List<TaskModel> tasks) {
    final int total = tasks.isEmpty ? 1 : tasks.length;
    final int completed = tasks.where((t) => t.isCompleted).length;
    final double progress = completed / total;
    final int dueToday =
        tasks.where((t) => t.isDueToday && !t.isCompleted).length;

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
              Text(
                'My Progress',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
              Text(
                '${(progress * 100).round()}%',
                style: AppTypography.h2.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: progress,
              backgroundColor: AppColors.glassBorder,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _selectedTab == 'task'
                    ? 'Tasks: $completed/$total Done'
                    : 'Follow-ups: $completed/$total Done',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                '$dueToday Due Today',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmployeeTabs() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          _buildEmployeeTab('Tasks', 'task'),
          const SizedBox(width: 16),
          _buildEmployeeTab('Follow-ups', 'followup'),
        ],
      ),
    );
  }

  Widget _buildEmployeeTab(String label, String value) {
    final bool isActive = _selectedTab == value;
    return GestureDetector(
      onTap: () => setState(() => _selectedTab = value),
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

  Widget _buildEmployeeStatusFilters() {
    return Row(
      children: [
        GlassChip(
          label: 'All',
          selected: _employeeStatus == 'all',
          onTap: () => setState(() => _employeeStatus = 'all'),
        ),
        const SizedBox(width: 10),
        GlassChip(
          label: 'Completed',
          selected: _employeeStatus == 'completed',
          onTap: () => setState(() => _employeeStatus = 'completed'),
        ),
        const SizedBox(width: 10),
        GlassChip(
          label: 'Pending',
          selected: _employeeStatus == 'pending',
          onTap: () => setState(() => _employeeStatus = 'pending'),
        ),
      ],
    );
  }

  Widget _buildEmployeeTaskCard(TaskModel task, TaskProvider taskProvider) {
    final bool isCompleted = task.isCompleted;
    final String priority = task.priority;
    final Color badgeColor = priority == 'high'
        ? AppColors.critical
        : priority == 'medium'
            ? AppColors.warning
            : AppColors.success;
    final String label = task.isFollowup ? 'Follow-up' : 'Task';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.glassPrimary,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: badgeColor.withValues(alpha: 0.35)),
                    ),
                    child: Text(
                      label.toUpperCase(),
                      style: AppTypography.overline.copyWith(
                        color: badgeColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    task.isDueToday
                        ? 'Due Today'
                        : 'Due ${DateFormat('dd MMM').format(task.dueDate)}',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            task.title,
            style: AppTypography.h3.copyWith(color: AppColors.textPrimary),
          ),
          if (task.contactType != null) ...[
            const SizedBox(height: 6),
            Text(
              task.contactType!,
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (isCompleted)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.glassHover,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: const BoxDecoration(
                      color: AppColors.success,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      AppIcons.check,
                      size: 14,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    task.uploadStatus == UploadStatus.pending
                        ? 'Completing...'
                        : task.uploadStatus == UploadStatus.error
                            ? 'Retry completion'
                            : 'Completed',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (task.uploadStatus == UploadStatus.pending) ...[
                    const SizedBox(width: 8),
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ],
              ),
            )
          else
            HoldButton(
              label: 'Hold to Complete',
              onComplete: () async {
                final success = await taskProvider.completeTask(task.id);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        success
                            ? 'Task update queued'
                            : 'Failed to complete task',
                      ),
                      backgroundColor:
                          success ? AppColors.success : AppColors.critical,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  );
                }
              },
            ),
        ],
      ),
    );
  }

  // ── Team Lead UI ─────────────────────────────────────────────

  Widget _buildLeadContent(TaskProvider taskProvider) {
    final activeTasks = taskProvider.activeTasks;
    final completedTasks = taskProvider.completedTasks;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLeadSummary(activeTasks.length, completedTasks.length),
        const SizedBox(height: 16),
        if (_leadView == 'my_work')
          ...activeTasks.map(
            (task) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _buildLeadMyWorkCard(task, taskProvider),
            ),
          )
        else
          ..._buildTeamMemberList(),
      ],
    );
  }

  Widget _buildLeadToggle(String label, String value) {
    final bool isActive = _leadView == value;
    return GestureDetector(
      onTap: () => setState(() => _leadView = value),
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

  Widget _buildLeadSummary(int pendingCount, int completedCount) {
    final bool isTeam = _leadView == 'team_monitor';
    final dashboardProvider = context.watch<DashboardProvider>();
    final teamProvider = context.watch<TeamProvider>();

    final groupActiveCount = isTeam
        ? teamProvider.teamMembers
            .where((m) {
              final s = dashboardProvider.getEmployeeStatus(m.id);
              return s == 'active' || s == 'break';
            })
            .length
        : 0;
    final String leftValue = isTeam
        ? '$groupActiveCount/${teamProvider.teamMembers.length}'
        : '$pendingCount';
    final String rightValue =
        isTeam ? '${teamProvider.totalTasks}' : '$completedCount';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.glassPrimary,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                Text(
                  leftValue,
                  style: AppTypography.displayLarge.copyWith(
                    color: isTeam ? AppColors.success : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isTeam ? 'Active Agents' : 'Pending Tasks',
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
              children: [
                Text(
                  rightValue,
                  style: AppTypography.displayLarge.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isTeam ? 'Total Team Tasks' : 'Completed',
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
    );
  }

  Widget _buildLeadMyWorkCard(TaskModel task, TaskProvider taskProvider) {
    final String priority = task.priority;
    final Color badgeColor = priority == 'high'
        ? AppColors.critical
        : priority == 'medium'
            ? AppColors.warning
            : AppColors.success;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.glassPrimary,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.glassBorder),
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
                    Text(
                      task.title,
                      style: AppTypography.h3.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      task.isDueToday
                          ? 'Due Today'
                          : 'Due ${DateFormat('dd MMM yyyy').format(task.dueDate)}',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: badgeColor.withValues(alpha: 0.35)),
                ),
                child: Text(
                  priority.toUpperCase(),
                  style: AppTypography.overline.copyWith(
                    color: badgeColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          HoldButton(
            label: task.uploadStatus == UploadStatus.pending
                ? 'Completing...'
                : 'Hold to Complete',
            onComplete: () async {
              final success = await taskProvider.completeTask(task.id);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      success
                          ? 'Task update queued'
                          : 'Failed to complete task',
                    ),
                    backgroundColor:
                        success ? AppColors.success : AppColors.critical,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  List<Widget> _buildTeamMemberList() {
    final teamProvider = context.watch<TeamProvider>();
    final dashboardProvider = context.watch<DashboardProvider>();
    final members = teamProvider.teamMembers;

    if (teamProvider.isLoading && members.isEmpty) {
      return [
        const Padding(
          padding: EdgeInsets.only(top: 40),
          child: Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
        ),
      ];
    }

    if (members.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.only(top: 40),
          child: Center(
            child: Text(
              'No team members yet',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ];
    }

    return members.map((member) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _buildTeamMemberCard(
          member,
          teamProvider.teamTasks,
          dashboardProvider,
        ),
      );
    }).toList();
  }

  Widget _buildTeamMemberCard(
    UserModel member,
    List<TaskModel> teamTasks,
    DashboardProvider dashboardProvider,
  ) {
    final status = dashboardProvider.getEmployeeStatus(member.id);
    final isActive = status == 'active';
    final isOnClock = dashboardProvider.isEmployeeOnClock(member.id);

    // Per-member task and follow-up counts
    final memberTasks = teamTasks.where((t) => t.assignedTo == member.id);
    final taskCount = memberTasks.where((t) => t.isTask).length;
    final followupCount = memberTasks.where((t) => t.isFollowup).length;

    // Avatar color based on name hash
    final colorIndex = member.name.hashCode.abs() % _avatarColors.length;
    final avatarColor = _avatarColors[colorIndex];

    final String subtitle = isActive
        ? '$taskCount Tasks . $followupCount Follow-ups'
        : '$taskCount Tasks . Offline';

    return GestureDetector(
      onTap: () => context.push('/employee/team-lead-detail', extra: {
        'name': member.name,
        'initials': member.initials,
        'isOnline': isOnClock,
        'employeeId': member.id,
      }),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.glassPrimary,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Row(
          children: [
            // Avatar with status dot
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: avatarColor.withValues(alpha: 0.2),
                  child: Text(
                    member.initials,
                    style: AppTypography.bodySmall.copyWith(
                      color: avatarColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  bottom: 0,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: isActive
                          ? AppColors.success
                          : AppColors.textTertiary,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.glassPrimary,
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 14),

            // Name & subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member.name,
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),

            // Arrow icon
            Icon(
              AppIcons.arrow_right_3,
              size: 20,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }

  void _openCreateTaskScreen() {
    context.push('/admin/create-task', extra: {
      'isTeamLead': widget.isTeamLead,
    });
  }
}
