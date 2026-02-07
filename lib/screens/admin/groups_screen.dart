import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';
import '../../widgets/glass/gradient_background.dart';
import '../../widgets/navigation/app_header.dart';
import 'create_group_screen.dart';
import 'edit_group_screen.dart';

/// Groups Screen - Enterprise Dark Glass Design
/// Team and group management
class GroupsScreen extends StatelessWidget {
  const GroupsScreen({super.key});

  // Mock groups data
  static const List<Map<String, dynamic>> _groups = [
    {
      'id': '1',
      'name': 'North Zone',
      'lead': 'Rahul Kumar',
      'leadId': 'rajesh',
      'members': 3,
      'color': AppColors.info, // Indigo
      'membersList': [
        {'name': 'Amit Patel', 'initials': 'AP', 'status': 'active'},
        {'name': 'Priya Sharma', 'initials': 'PS', 'status': 'active'},
        {'name': 'David Kim', 'initials': 'DK', 'status': 'away'},
      ],
    },
    {
      'id': '2',
      'name': 'South Zone',
      'lead': 'Priya Singh',
      'leadId': 'sarah',
      'members': 4,
      'color': AppColors.success, // Green
      'membersList': [],
    },
    {
      'id': '3',
      'name': 'Central District',
      'lead': 'Amit Sharma',
      'leadId': 'mike',
      'members': 2,
      'color': AppColors.warning, // Orange/Amber
      'membersList': [],
    },
  ];

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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Create Group Button
                    _buildCreateButton(context),
                    const SizedBox(height: 24),

                    // Groups Label
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Text(
                        'GROUPS (${_groups.length})',
                        style: AppTypography.caption.copyWith(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Groups List
                    ...List.generate(_groups.length, (index) {
                      final group = _groups[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildGroupCard(context, group),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCreateButton(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CreateGroupScreen()),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: AppColors.primary.withOpacity(0.3),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.1),
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
                color: AppColors.primary.withOpacity(0.2),
              ),
              child: const Icon(Icons.add, color: AppColors.primary, size: 20),
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

  Widget _buildGroupCard(BuildContext context, Map<String, dynamic> group) {
    final color = group['color'] as Color;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => EditGroupScreen(
              groupId: group['id'],
              groupName: group['name'],
              teamLeadId: group['leadId'],
              members: List<Map<String, dynamic>>.from(
                group['membersList'] ?? [],
              ),
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.glassPrimary,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.glassBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Icon
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: color.withOpacity(0.3)),
              ),
              child: Icon(Iconsax.people, color: color, size: 24),
            ),
            const SizedBox(width: 16),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group['name'],
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textPrimary, // White text
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Lead: ${group['lead']} • ${group['members']} members',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary, // Light grey text
                    ),
                  ),
                ],
              ),
            ),

            // Arrow
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.glassPrimary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.chevron_right,
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

