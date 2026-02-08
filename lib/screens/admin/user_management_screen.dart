import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';
import '../../widgets/glass/gradient_background.dart';
import '../../widgets/glass/glass_panel.dart';
import '../../widgets/inputs/text_input_field.dart';
import '../../widgets/navigation/app_header.dart';
import 'add_user_screen.dart';

const List<Map<String, String>> demoUsers = [
  {'name': 'Amit Patel', 'role': 'Team Lead', 'initials': 'AP'},
  {'name': 'Priya Sharma', 'role': 'Senior Field Officer', 'initials': 'PS'},
  {'name': 'David Kim', 'role': 'Logistics Coordinator', 'initials': 'DK'},
  {'name': 'Elena Rodriguez', 'role': 'Field Technician', 'initials': 'ER'},
  {'name': 'James Bond', 'role': 'Security Lead', 'initials': 'JB'},
];

class UserManagementScreen extends StatefulWidget {
  final bool showHeader;

  const UserManagementScreen({super.key, this.showHeader = true});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  final _searchController = TextEditingController();

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
            if (widget.showHeader)
              const AppHeader(
                title: 'User Management',
                type: AppHeaderType.primary,
                showAvatar: false,
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  20,
                  widget.showHeader ? 16 : 4,
                  20,
                  120,
                ),
                child: UserManagementContent(
                  users: demoUsers,
                  searchController: _searchController,
                  onAddUser: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AddUserScreen(),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class UserManagementContent extends StatelessWidget {
  final List<Map<String, String>> users;
  final TextEditingController searchController;
  final VoidCallback onAddUser;

  const UserManagementContent({
    super.key,
    required this.users,
    required this.searchController,
    required this.onAddUser,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GlassPanel(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: GlassInputField(
                  controller: searchController,
                  hint: 'Search users...',
                  prefixIcon: Iconsax.search_normal,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: onAddUser,
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Iconsax.add,
                        color: AppColors.textPrimary,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Add User',
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
        ),
        const SizedBox(height: 16),
        Text(
          'All Users (${users.length})',
          style: AppTypography.h3.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        ...users.map(_buildUserCard),
      ],
    );
  }

  Widget _buildUserCard(Map<String, String> user) {
    return GlassPanel(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withValues(alpha: 0.15),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Center(
              child: Text(
                user['initials'] ?? 'U',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user['name'] ?? '',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  user['role'] ?? '',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () {},
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.glassPrimary,
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: const Icon(
                Iconsax.trash,
                size: 18,
                color: AppColors.critical,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
