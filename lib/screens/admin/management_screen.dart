import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_typography.dart';
import '../../widgets/glass/gradient_background.dart';
import '../../widgets/glass/glass_chip.dart';
import '../../widgets/navigation/app_header.dart';
import 'add_user_screen.dart';
import 'groups_screen.dart';
import 'user_management_screen.dart';

class ManagementScreen extends StatefulWidget {
  const ManagementScreen({super.key});

  @override
  State<ManagementScreen> createState() => _ManagementScreenState();
}

class _ManagementScreenState extends State<ManagementScreen> {
  int _activeTab = 0;
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const AppHeader(
              title: 'Management',
              type: AppHeaderType.primary,
              showAvatar: false,
              showLeading: false,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.sm,
                AppSpacing.xl,
                AppSpacing.md,
              ),
              child: Row(
                children: [
                  GlassChip(
                    label: 'Manage Group',
                    selected: _activeTab == 0,
                    onTap: () => setState(() => _activeTab = 0),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  GlassChip(
                    label: 'Manage User',
                    selected: _activeTab == 1,
                    onTap: () => setState(() => _activeTab = 1),
                  ),
                  const Spacer(),
                  if (_activeTab == 1)
                    Text(
                      'Users',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textTertiary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.sm,
                  AppSpacing.xl,
                  120,
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: _activeTab == 0
                      ? const GroupsContent(
                          key: ValueKey('groups'),
                          showCreateButton: true,
                        )
                      : UserManagementContent(
                          key: const ValueKey('users'),
                          users: demoUsers,
                          searchController: _searchController,
                          onAddUser: _openAddUser,
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openAddUser() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AddUserScreen()),
    );
  }
}
