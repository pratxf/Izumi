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
  String _selectedTab = 'task';

  // Mock data - Active tasks
  final List<Map<String, dynamic>> _activeTasks = [
    {
      'id': 1,
      'title': 'Visit ABC Distributor',
      'emoji': '⚠️',
      'priority': 'high',
      'assignedBy': 'Admin',
      'dueDate': '05 Feb 2026',
      'type': 'task',
    },
    {
      'id': 2,
      'title': 'Follow up: XYZ Farmer',
      'emoji': '📋',
      'priority': 'medium',
      'type': 'followup',
      'contactType': 'Farmer',
      'phone': '+1 (555) 012-3456',
      'dueToday': true,
    },
  ];

  // Mock data - Completed tasks
  final List<Map<String, dynamic>> _completedTasks = [
    {
      'id': 3,
      'title': 'Visit Region A',
      'emoji': '✅',
      'completedAt': '10:30 AM',
      'type': 'task',
    },
  ];

  List<Map<String, dynamic>> get _filteredTasks {
    return _activeTasks.where((t) => t['type'] == _selectedTab).toList();
  }

  List<Map<String, dynamic>> get _filteredCompletedTasks {
    return _completedTasks.where((t) => t['type'] == _selectedTab).toList();
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
                        ]
                      : null,
                ),

                // Filter Pills
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  child: Row(
                    children: [
                      _buildFilterPill('Task', 'task'),
                      const SizedBox(width: 12),
                      _buildFilterPill('Follow Up', 'followup'),
                      if (widget.isTeamLead) ...[
                        const SizedBox(width: 12),
                        _buildFilterPill('Monitor', 'monitor'),
                      ],
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
                        // Active Section
                        if (_filteredTasks.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      'Active',
                                      style: AppTypography.headline.copyWith(
                                        color: AppColors.textPrimary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.glassPrimary,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        '${_filteredTasks.length}',
                                        style: AppTypography.caption.copyWith(
                                          color: AppColors.textPrimary,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                GestureDetector(
                                  onTap: () {},
                                  child: Text(
                                    'Sort by Due Date',
                                    style: AppTypography.caption.copyWith(
                                      color: AppColors.textSecondary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          ..._filteredTasks.map(
                            (task) => Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: _buildActiveTaskCard(task),
                            ),
                          ),
                        ],

                        // Completed Section
                        if (_filteredCompletedTasks.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Row(
                              children: [
                                Text(
                                  'Completed',
                                  style: AppTypography.headline.copyWith(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.glassPrimary,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${_filteredCompletedTasks.length}',
                                    style: AppTypography.caption.copyWith(
                                      color: AppColors.textSecondary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          ..._filteredCompletedTasks.map(
                            (task) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _buildCompletedTaskCard(task),
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
        if (value == 'monitor') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const MonitorScreen(showFilter: true),
            ),
          );
          return;
        }
        setState(() => _selectedTab = value);
      },
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
            Icon(Icons.chevron_right, color: AppColors.textTertiary),
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


