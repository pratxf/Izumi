import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';
import '../../models/task_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/task_provider.dart';
import '../../widgets/glass/gradient_background.dart';
import '../../widgets/glass/glass_chip.dart';
import '../../widgets/navigation/app_header.dart';
import '../../widgets/buttons/hold_button.dart';
import '../admin/create_task_screen.dart';
import 'monitor_screen.dart';

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
                  title: 'Todo',
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
                                    Iconsax.add,
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
                                        style: AppTypography.bodyMedium.copyWith(
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ),
                                  )
                                else
                                  ...filteredTasks.map(
                                    (task) => Padding(
                                      padding: const EdgeInsets.only(bottom: 16),
                                      child: _buildEmployeeTaskCard(task, taskProvider),
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
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
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
                'Due Today',
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
                      Iconsax.check,
                      size: 14,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Completed',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
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
                        success ? 'Task completed!' : 'Failed to complete task',
                      ),
                      backgroundColor: success ? AppColors.success : AppColors.critical,
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
          // Navigate to monitor screen for team view
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 20),
              child: GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const MonitorScreen(showFilter: true),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Iconsax.people, size: 20, color: AppColors.primary),
                      const SizedBox(width: 10),
                      Text(
                        'Open Team Monitor',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
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
                  isTeam ? '—' : '$pendingCount',
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
                  isTeam ? '—' : '$completedCount',
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
            label: 'Hold to Complete',
            onComplete: () async {
              final success = await taskProvider.completeTask(task.id);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      success ? 'Task completed!' : 'Failed to complete task',
                    ),
                    backgroundColor: success ? AppColors.success : AppColors.critical,
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

  void _openCreateTaskScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreateTaskScreen(isTeamLead: widget.isTeamLead),
      ),
    );
  }
}
