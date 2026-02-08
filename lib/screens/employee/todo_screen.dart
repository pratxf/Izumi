import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';
import '../../widgets/glass/gradient_background.dart';
import '../../widgets/glass/glass_chip.dart';
import '../../widgets/glass/glass_panel.dart';
import '../../widgets/navigation/app_header.dart';
import '../../widgets/buttons/hold_button.dart';
import '../admin/create_task_screen.dart';
import 'team_lead_employee_detail_screen.dart';

/// Todo Screen - Redesigned per reference
/// Shows tasks and follow-ups with filter pills
class TodoScreen extends StatefulWidget {
  final bool isTeamLead;

  const TodoScreen({super.key, this.isTeamLead = false});

  @override
  State<TodoScreen> createState() => _TodoScreenState();
}

class _TodoScreenState extends State<TodoScreen> {
  String _selectedTab = 'task';
  String _leadView = 'my_work';
  String _employeeStatus = 'all';

  // Mock data - Active tasks
  final List<Map<String, dynamic>> _activeTasks = [
    {
      'id': 1,
      'title': 'Visit ABC Distributor',
      'emoji': 'âš ï¸',
      'priority': 'high',
      'assignedBy': 'Admin',
      'dueDate': '05 Feb 2026',
      'type': 'task',
      'completed': false,
    },
    {
      'id': 2,
      'title': 'Follow up: XYZ Farmer',
      'emoji': 'ðŸ“‹',
      'priority': 'medium',
      'type': 'followup',
      'contactType': 'Farmer',
      'dueToday': true,
      'completed': false,
    },
  ];

  // Mock data - Completed tasks
  final List<Map<String, dynamic>> _completedTasks = [
    {
      'id': 3,
      'title': 'Visit Region A',
      'emoji': 'âœ…',
      'completedAt': '10:30 AM',
      'type': 'task',
      'completed': true,
    },
  ];

  final List<Map<String, dynamic>> _leadMyWorkTasks = [
    {
      'title': 'Weekly Quality Audit',
      'detail': 'North Sector â€¢ Due Today',
      'priority': 'high',
      'status': 'In Progress',
      'statusColor': AppColors.warning,
    },
    {
      'title': 'Client Onboarding',
      'detail': 'Tech Park Zone â€¢ Due Tomorrow',
      'priority': 'medium',
      'status': 'Pending Review',
      'statusColor': AppColors.primary,
    },
    {
      'title': 'Inventory Check',
      'detail': 'Warehouse B â€¢ Due Oct 24',
      'priority': 'low',
      'status': 'Not Started',
      'statusColor': AppColors.textTertiary,
    },
    {
      'title': 'Team Performance Review',
      'detail': 'Quarterly â€¢ Due Oct 25',
      'priority': 'high',
      'status': 'Scheduled',
      'statusColor': AppColors.textTertiary,
    },
  ];

  final List<Map<String, dynamic>> _leadTeamMembers = [
    {
      'name': 'Amit Patel',
      'initials': 'AP',
      'tasks': '3 Tasks',
      'followUps': '2 Follow-ups',
      'isOnline': true,
      'color': const Color(0xFF6366F1),
    },
    {
      'name': 'Sunita Kumar',
      'initials': 'SK',
      'tasks': '5 Tasks',
      'followUps': '1 Follow-up',
      'isOnline': true,
      'color': const Color(0xFFEC4899),
    },
    {
      'name': 'Ravi Singh',
      'initials': 'RS',
      'tasks': '0 Tasks',
      'followUps': 'Offline',
      'isOnline': false,
      'color': const Color(0xFFF59E0B),
    },
    {
      'name': 'Jenny Li',
      'initials': 'JL',
      'tasks': '2 Tasks',
      'followUps': '4 Follow-ups',
      'isOnline': true,
      'color': const Color(0xFF06B6D4),
    },
  ];

  List<Map<String, dynamic>> get _filteredTasks {
    return _activeTasks.where((t) => t['type'] == _selectedTab).toList();
  }

  List<Map<String, dynamic>> get _filteredCompletedTasks {
    return _completedTasks.where((t) => t['type'] == _selectedTab).toList();
  }

  List<Map<String, dynamic>> get _employeeAllItems {
    final items = [
      ..._activeTasks,
      ..._completedTasks,
    ].where((t) => t['type'] == _selectedTab).toList();

    if (_employeeStatus == 'completed') {
      return items.where((t) => t['completed'] == true).toList();
    }
    if (_employeeStatus == 'pending') {
      return items.where((t) => t['completed'] != true).toList();
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
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
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(
                      left: 20,
                      right: 20,
                      bottom: 120,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.isTeamLead) ...[
                          _buildLeadSummary(),
                          const SizedBox(height: 16),
                          if (_leadView == 'my_work')
                            ..._leadMyWorkTasks
                                .map(
                                  (task) => Padding(
                                    padding: const EdgeInsets.only(bottom: 16),
                                    child: _buildLeadMyWorkCard(task),
                                  ),
                                )
                          else
                            ..._leadTeamMembers
                                .map(
                                  (member) => Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: _buildLeadTeamMemberCard(member),
                                  ),
                                ),
                        ] else ...[
                          _buildEmployeeProgressCard(),
                          const SizedBox(height: 12),
                          _buildEmployeeTabs(),
                          const SizedBox(height: 12),
                          _buildEmployeeStatusFilters(),
                          const SizedBox(height: 12),
                          ..._employeeAllItems.map(
                            (task) => Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: _buildEmployeeTaskCard(task),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // Create task action is in header for team lead
          ],
        ),
      ),
    );
  }

  Widget _buildFilterPill(String label, String value) {
    final isSelected = value != 'monitor' && _selectedTab == value;
    return GlassChip(
      label: label,
      selected: isSelected,
      onTap: () {
        setState(() => _selectedTab = value);
      },
    );
  }

  Widget _buildEmployeeProgressCard() {
    final int total = _employeeAllItems.isEmpty ? 1 : _employeeAllItems.length;
    final int completed = _employeeAllItems
        .where((item) => item['completed'] == true)
        .length;
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

  Widget _buildEmployeeTaskCard(Map<String, dynamic> task) {
    final bool isCompleted = task['completed'] == true;
    final String priority = task['priority'] ?? 'medium';
    final Color badgeColor = priority == 'high'
        ? AppColors.critical
        : priority == 'medium'
            ? AppColors.warning
            : AppColors.success;
    final String label = _selectedTab == 'task' ? 'Task' : 'Follow-up';

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
                    'Due Today',
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
            task['title'],
            style: AppTypography.h3.copyWith(color: AppColors.textPrimary),
          ),
          if (task['contactType'] != null) ...[
            const SizedBox(height: 6),
            Text(
              task['contactType'],
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
              onComplete: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Task completed!'),
                    backgroundColor: AppColors.success,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
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

  Widget _buildLeadSummary() {
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
                  isTeam ? '8/10' : '6',
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
                  isTeam ? '42' : '4',
                  style: AppTypography.displayLarge.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isTeam ? 'Total Team Tasks' : 'Follow-ups',
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

  Widget _buildLeadMyWorkCard(Map<String, dynamic> task) {
    final String priority = task['priority'] as String;
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
                      task['title'] as String,
                      style: AppTypography.h3.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      task['detail'] as String,
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
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: task['statusColor'] as Color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    task['status'] as String,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox.shrink(),
            ],
          ),
          const SizedBox(height: 16),
          HoldButton(
            label: 'Hold to Complete',
            onComplete: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Task completed!'),
                  backgroundColor: AppColors.success,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLeadTeamMemberCard(Map<String, dynamic> member) {
    final bool isOnline = member['isOnline'] as bool;
    final Color dotColor = isOnline ? AppColors.success : AppColors.textTertiary;
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TeamLeadEmployeeDetailScreen(
              name: member['name'] as String,
              initials: member['initials'] as String,
              isOnline: member['isOnline'] as bool,
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.glassPrimary,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Stack(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: member['color'] as Color,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.glassBorder),
                      ),
                      child: Center(
                        child: Text(
                          member['initials'] as String,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 2,
                      bottom: 2,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: dotColor,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.gradientStart,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member['name'] as String,
                      style: AppTypography.bodyMedium.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          member['tasks'] as String,
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppColors.textTertiary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          member['followUps'] as String,
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.glassHover,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: const Icon(
                Iconsax.arrow_right_2,
                size: 18,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveTaskCard(Map<String, dynamic> task) {
    final priority = task['priority'] ?? 'medium';
    final isHighPriority = priority == 'high';
    final isFollowUp = task['type'] == 'followup';

    Color borderColor;
    Color badgeColor;
    Color badgeBgColor;
    String badgeText;

    switch (priority) {
      case 'high':
        borderColor = AppColors.critical;
        badgeColor = AppColors.critical;
        badgeBgColor = AppColors.critical.withValues(alpha: 0.2);
        badgeText = 'HIGH';
        break;
      case 'medium':
        borderColor = AppColors.warning;
        badgeColor = AppColors.warning;
        badgeBgColor = AppColors.warning.withValues(alpha: 0.2);
        badgeText = 'MEDIUM';
        break;
      default:
        borderColor = AppColors.success;
        badgeColor = AppColors.success;
        badgeBgColor = AppColors.success.withValues(alpha: 0.2);
        badgeText = 'LOW';
    }

    return GlassPanel(
      borderRadius: 24,
      padding: const EdgeInsets.all(20),
      backgroundColor: AppColors.glassStrong,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 4,
                height: 28,
                margin: const EdgeInsets.only(top: 2, right: 10),
                decoration: BoxDecoration(
                  color: borderColor,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              Text(
                task['emoji'] ?? '??',
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  task['title'],
                  style: AppTypography.headline.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
              if (isHighPriority)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: badgeBgColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    badgeText,
                    style: TextStyle(
                      color: badgeColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (!isFollowUp) ...[
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        Iconsax.user,
                        size: 16,
                        color: AppColors.textTertiary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Assigned by: ${task['assignedBy']}',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textSecondary,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    Icon(
                      Iconsax.calendar,
                      size: 16,
                      color: AppColors.textTertiary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Due: ${task['dueDate']}',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Type: ${task['contactType']}',
                style: TextStyle(
                  color: AppColors.warning,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Iconsax.call,
                      size: 16,
                      color: AppColors.textTertiary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      task['phone'],
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
                if (task['dueToday'] == true)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.glassPrimary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Due Today',
                      style: AppTypography.overline.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          HoldButton(
            label: 'Hold to Complete',
            onComplete: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Task completed!'),
                  backgroundColor: AppColors.success,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

Widget _buildCompletedTaskCard(Map<String, dynamic> task) {
    return Opacity(
      opacity: 0.6,
      child: GlassPanel(
        borderRadius: 24,
        padding: const EdgeInsets.all(16),
        backgroundColor: AppColors.glassStrong,
        child: Row(
          children: [
            Container(
              width: 4,
              height: 28,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: AppColors.textTertiary,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            Text(
              task['emoji'] ?? '?',
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task['title'],
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.bold,
                      decoration: TextDecoration.lineThrough,
                      decorationThickness: 2,
                      decorationColor: AppColors.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Completed at ${task['completedAt']}',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textTertiary,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Iconsax.arrow_right_2, color: AppColors.textTertiary),
          ],
        ),
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



