import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:izumi/core/ui/app_icons.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/team_provider.dart';
import '../../utils/alphabet_filter_utils.dart';
import '../../widgets/glass/gradient_background.dart';
import '../../widgets/glass/glass_panel.dart';
import '../../widgets/inputs/alphabet_filter.dart';
import '../../widgets/navigation/app_header.dart';

/// Team Screen - Team Lead's dashboard for managing their team
class TeamScreen extends StatefulWidget {
  const TeamScreen({super.key});

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
    _loadTeamData();
  }

  void _loadTeamData() {
    final authProvider = context.read<AuthProvider>();
    final userId = authProvider.currentUser?.id;
    final enterpriseId =
        authProvider.enterpriseId ?? authProvider.currentUser?.enterpriseId;

    if (userId != null && enterpriseId != null) {
      context.read<TeamProvider>().initTeam(enterpriseId, userId);
      // Initialize dashboard streams for live presence, location & stats
      final dashboardProvider = context.read<DashboardProvider>();
      if (dashboardProvider.employees.isEmpty) {
        dashboardProvider.initDashboard(enterpriseId);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final teamProvider = context.watch<TeamProvider>();
    final dashboardProvider = context.watch<DashboardProvider>();

    return GradientBackground(
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AppHeader(
              title: 'My Team',
              type: AppHeaderType.primary,
              showAvatar: false,
              actions: [
                GestureDetector(
                  onTap: () => context.push('/admin/create-task', extra: {
                    'isTeamLead': true,
                  }),
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
                        Icon(AppIcons.add, size: 18, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Text(
                          'Task',
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
            Expanded(
              child: teamProvider.isLoading
                  ? const Center(
                      child:
                          CircularProgressIndicator(color: AppColors.primary),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Team Header Card
                          _buildTeamHeader(teamProvider),
                          const SizedBox(height: 20),

                          // Task Summary
                          _buildTaskSummary(teamProvider),
                          const SizedBox(height: 20),

                          // Team Members
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Text(
                              'TEAM MEMBERS (${teamProvider.teamMembers.length})',
                              style: AppTypography.caption.copyWith(
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.0,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          AlphabetFilter(
                            isAscending: _sortAscending,
                            padding: EdgeInsets.zero,
                            onToggle: (val) =>
                                setState(() => _sortAscending = val),
                          ),
                          const SizedBox(height: 12),

                          if (teamProvider.teamMembers.isEmpty)
                            _buildEmptyState()
                          else
                            ...sortUsersByName(
                              teamProvider.teamMembers,
                              _sortAscending,
                            ).map((member) =>
                                _buildMemberCard(member, dashboardProvider)),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTeamHeader(TeamProvider teamProvider) {
    final groupName = teamProvider.group?.name ?? 'My Team';
    final memberCount = teamProvider.teamMembers.length;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.primary.withValues(alpha: 0.15),
                AppColors.primary.withValues(alpha: 0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.4),
                  ),
                ),
                child: const Icon(
                  AppIcons.people,
                  color: AppColors.primary,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      groupName,
                      style: AppTypography.h2.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$memberCount members',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTaskSummary(TeamProvider teamProvider) {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            'Total Tasks',
            teamProvider.totalTasks.toString(),
            AppColors.primary,
            AppIcons.task_square,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            'Pending',
            teamProvider.pendingTasks.toString(),
            AppColors.warning,
            AppIcons.clock,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            'Done',
            teamProvider.completedTasks.toString(),
            AppColors.success,
            AppIcons.tick_circle,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(
      String label, String value, Color color, IconData icon) {
    return GlassPanel(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 8),
          Text(
            value,
            style: AppTypography.h2.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberCard(
      UserModel member, DashboardProvider dashboardProvider) {
    final status = dashboardProvider.getEmployeeStatus(member.id);
    final location = dashboardProvider.getEmployeeLocation(member.id);
    final stats = dashboardProvider.getEmployeeStats(member.id);
    final address = location?['address'] as String? ?? 'Unknown location';
    final isActive = status == 'active';
    final isBreak = status == 'break';
    final isSignalLost = status == 'signal_lost';
    final isOnClock = dashboardProvider.isEmployeeOnClock(member.id);

    Color statusColor;
    String statusLabel;
    if (isActive) {
      statusColor = AppColors.success;
      statusLabel = 'ACTIVE';
    } else if (isBreak) {
      statusColor = AppColors.warning;
      statusLabel = 'BREAK';
    } else if (isSignalLost) {
      statusColor = AppColors.warningDark;
      statusLabel = 'SIGNAL LOST';
    } else {
      statusColor = AppColors.textTertiary;
      statusLabel = 'OFFLINE';
    }

    final durationSec = stats?['sessionDuration'] as int? ?? 0;
    final hours = durationSec ~/ 3600;
    final minutes = (durationSec % 3600) ~/ 60;
    final durationStr = hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () => context.push('/employee/team-lead-detail', extra: {
          'name': member.name,
          'initials': member.initials,
          'isOnline': isOnClock,
          'employeeId': member.id,
        }),
        child: GlassPanel(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Avatar with status ring
              Stack(
                children: [
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: statusColor, width: 2),
                    ),
                    child: CircleAvatar(
                      radius: 22,
                      backgroundColor:
                          AppColors.primary.withValues(alpha: 0.15),
                      child: Text(
                        member.initials,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: statusColor,
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

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            member.name,
                            style: AppTypography.bodyMedium.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            statusLabel,
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          AppIcons.location,
                          size: 13,
                          color: AppColors.textTertiary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            address,
                            style: AppTypography.caption.copyWith(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isOnClock) ...[
                          const SizedBox(width: 8),
                          Icon(AppIcons.clock,
                              size: 12, color: AppColors.textTertiary),
                          const SizedBox(width: 3),
                          Text(
                            durationStr,
                            style: AppTypography.caption.copyWith(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 48),
        child: Column(
          children: [
            Icon(
              AppIcons.people,
              size: 48,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: 16),
            Text(
              'No team members yet',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Ask your admin to assign members to your group',
              style: AppTypography.caption.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
