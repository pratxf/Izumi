import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';
import '../../models/group_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/group_provider.dart';
import '../../widgets/glass/gradient_background.dart';
import '../../widgets/navigation/app_header.dart';

/// Groups Screen - Enterprise Dark Glass Design
/// Team and group management
class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  void _loadGroups() {
    final enterpriseId = context.read<AuthProvider>().enterpriseId;
    if (enterpriseId != null) {
      context.read<GroupProvider>().streamGroups(enterpriseId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const AppHeader(
              title: 'Groups',
              type: AppHeaderType.primary,
              showAvatar: false,
            ),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
                child: const GroupsContent(showCreateButton: true),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reusable groups content widget used by both GroupsScreen and ManagementScreen
class GroupsContent extends StatelessWidget {
  final bool showCreateButton;

  const GroupsContent({super.key, this.showCreateButton = false});

  @override
  Widget build(BuildContext context) {
    final groupProvider = context.watch<GroupProvider>();
    final groups = groupProvider.groups;
    final dashboardProvider = context.watch<DashboardProvider>();

    if (groupProvider.isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.only(top: 48),
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showCreateButton) ...[
          _buildCreateButton(context),
          const SizedBox(height: 24),
        ],

        // Groups Label
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            'GROUPS (${groups.length})',
            style: AppTypography.caption.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Groups List
        if (groups.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 48),
              child: Column(
                children: [
                  Icon(
                    Iconsax.people,
                    size: 48,
                    color: AppColors.textTertiary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No groups yet',
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ...groups.map((group) {
            final lead = dashboardProvider.employees
                .where((e) => e.id == group.leadId)
                .firstOrNull;
            final leadName = lead?.name ?? 'Unassigned';

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildGroupCard(context, group, leadName),
            );
          }),
      ],
    );
  }

  Widget _buildCreateButton(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/admin/create-group'),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.3),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.1),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.2),
              ),
              child: const Icon(Iconsax.add, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Text(
              'Create New Group',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupCard(BuildContext context, GroupModel group, String leadName) {
    Color color;
    try {
      final hex = group.color.replaceFirst('#', '');
      color = Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      color = AppColors.info;
    }

    return GestureDetector(
      onTap: () {
        final dashboardProvider = context.read<DashboardProvider>();
        final memberMaps = group.memberIds.map((memberId) {
          final emp = dashboardProvider.employees
              .where((e) => e.id == memberId)
              .firstOrNull;
          return {
            'id': memberId,
            'name': emp?.name ?? 'Unknown',
            'initials': emp?.initials ?? '?',
            'status': dashboardProvider.getEmployeeStatus(memberId),
          };
        }).toList();

        context.push('/admin/edit-group', extra: {
          'groupId': group.id,
          'groupName': group.name,
          'teamLeadId': group.leadId,
          'members': memberMaps,
        });
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.glassPrimary,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.glassBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: Icon(Iconsax.people, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.name,
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Lead: $leadName • ${group.memberCount} members',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.glassPrimary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Iconsax.arrow_right_2,
                color: AppColors.textTertiary,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
