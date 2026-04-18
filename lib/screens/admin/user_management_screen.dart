import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:go_router/go_router.dart';
import 'package:izumi/core/ui/app_icons.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/user_provider.dart';
import '../../utils/alphabet_filter_utils.dart';
import '../../widgets/glass/gradient_background.dart';
import '../../widgets/glass/glass_panel.dart';
import '../../widgets/inputs/alphabet_filter.dart';
import '../../widgets/inputs/text_input_field.dart';
import '../../widgets/navigation/app_header.dart';

class UserManagementScreen extends StatefulWidget {
  final bool showHeader;

  const UserManagementScreen({super.key, this.showHeader = true});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  final _searchController = TextEditingController();
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  void _loadUsers() {
    final enterpriseId = context.read<AuthProvider>().enterpriseId;
    if (enterpriseId != null) {
      context.read<UserProvider>().streamUsers(enterpriseId);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();
    final allUsers = userProvider.users;
    final sortedUsers = sortUsersByName(allUsers, _sortAscending);
    final query = _searchController.text.trim().toLowerCase();
    final filteredUsers = query.isEmpty
        ? sortedUsers
        : sortedUsers.where((u) {
            return u.name.toLowerCase().contains(query) ||
                u.phone.contains(query) ||
                u.displayRole.toLowerCase().contains(query);
          }).toList();

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
            Padding(
              padding: EdgeInsets.only(
                top: widget.showHeader ? 16 : 8,
                bottom: 8,
              ),
              child: AlphabetFilter(
                isAscending: _sortAscending,
                onToggle: (val) => setState(() => _sortAscending = val),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  20,
                  4,
                  20,
                  120,
                ),
                child: UserManagementContent(
                  users: filteredUsers,
                  searchController: _searchController,
                  onSearchChanged: (_) => setState(() {}),
                  onAddUser: () => context.push('/admin/add-user'),
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
  final List<UserModel> users;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onAddUser;

  const UserManagementContent({
    super.key,
    required this.users,
    required this.searchController,
    required this.onSearchChanged,
    required this.onAddUser,
  });

  void _confirmDeleteUser(BuildContext context, UserModel user) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.glassStrong,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.glassBorder),
        ),
        title: Text(
          'Delete User',
          style: AppTypography.h3.copyWith(color: AppColors.textPrimary),
        ),
        content: Text(
          'Are you sure you want to remove ${user.name}? This action cannot be undone.',
          style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                final callable = FirebaseFunctions.instanceFor(region: 'asia-south1')
                    .httpsCallable('deleteUser');
                await callable.call({'targetUserId': user.id});
                // Also delete Auth by phone as fallback
                try {
                  final cleanup = FirebaseFunctions.instanceFor(region: 'asia-south1')
                      .httpsCallable('adminCleanup');
                  await cleanup.call({
                    'phone': user.phone,
                    'deleteOnly': true,
                  });
                } catch (_) {}
                if (context.mounted) {
                  // Refresh user list
                  final auth = context.read<AuthProvider>();
                  final eid = auth.enterpriseId ?? '';
                  if (eid.isNotEmpty) context.read<UserProvider>().loadUsers(eid);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${user.name} removed')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to delete: $e')),
                  );
                }
              }
            },
            child: Text(
              'Delete',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.critical,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditUserDialog(BuildContext context, UserModel user) async {
    final nameController = TextEditingController(text: user.name);
    final phoneController = TextEditingController(text: user.phone);
    String selectedRole = user.activeRole;
    bool isSaving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          backgroundColor: AppColors.glassStrong,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.glassBorder),
          ),
          title: Text(
            'Edit User',
            style: AppTypography.h3.copyWith(color: AppColors.textPrimary),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GlassInputField(
                  controller: nameController,
                  label: 'Full Name',
                  hint: 'Enter full name',
                ),
                const SizedBox(height: 12),
                GlassInputField(
                  controller: phoneController,
                  label: 'Phone Number',
                  hint: 'Enter phone number',
                ),
                const SizedBox(height: 12),
                Text(
                  'Role',
                  style: AppTypography.label,
                ),
                const SizedBox(height: 8),
                if (user.isAdmin)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.glassPrimary,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.glassBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Enterprise Admin',
                          style: AppTypography.bodyMedium.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Admin role cannot be changed from this screen.',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: _RolePill(
                          label: 'Field Employee',
                          selected: selectedRole == 'employee',
                          onTap: isSaving
                              ? null
                              : () => setModalState(() => selectedRole = 'employee'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _RolePill(
                          label: 'Team Lead',
                          selected: selectedRole == 'team_lead',
                          onTap: isSaving
                              ? null
                              : () => setModalState(() => selectedRole = 'team_lead'),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.of(ctx).pop(),
              child: Text(
                'Cancel',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            TextButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      final name = nameController.text.trim();
                      final phone = phoneController.text.trim();
                      if (name.isEmpty || phone.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Name and phone are required')),
                        );
                        return;
                      }

                      setModalState(() => isSaving = true);
                      try {
                        final payload = <String, dynamic>{
                          'targetUserId': user.id,
                        };
                        if (name != user.name) payload['name'] = name;
                        if (phone != user.phone) payload['phone'] = phone;
                        if (!user.isAdmin && selectedRole != user.activeRole) {
                          payload['role'] = selectedRole;
                        }
                        if (payload.length == 1) {
                          // Nothing changed — close silently.
                          if (ctx.mounted) Navigator.of(ctx).pop();
                          return;
                        }

                        final callable =
                            FirebaseFunctions.instanceFor(region: 'asia-south1')
                                .httpsCallable('updateUser');
                        await callable.call(payload);

                        if (context.mounted) {
                          final auth = context.read<AuthProvider>();
                          final eid = auth.enterpriseId ?? '';
                          if (eid.isNotEmpty) {
                            await context.read<UserProvider>().loadUsers(eid);
                          }
                          if (!context.mounted) return;
                          Navigator.of(ctx).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('User updated')),
                          );
                        }
                      } on FirebaseFunctionsException catch (e) {
                        final msg = e.code == 'already-exists'
                            ? (e.message ??
                                'This phone number is already in use.')
                            : (e.message ?? 'Failed to update user.');
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(msg)),
                          );
                        }
                        if (ctx.mounted) {
                          setModalState(() => isSaving = false);
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Failed to update user: $e')),
                          );
                        }
                        if (ctx.mounted) {
                          setModalState(() => isSaving = false);
                        }
                      }
                    },
              child: Text(
                isSaving ? 'Saving...' : 'Save',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

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
                  prefixIcon: AppIcons.search_normal,
                  onChanged: onSearchChanged,
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
                        AppIcons.add,
                        color: Colors.white,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Add User',
                        style: AppTypography.bodySmall.copyWith(
                          color: Colors.white,
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
        ...users.map((user) => _buildUserCard(context, user)),
      ],
    );
  }



  Widget _buildUserCard(BuildContext context, UserModel user) {
    return GestureDetector(
      onTap: () => _showEditUserDialog(context, user),
      child: GlassPanel(
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
                  user.initials,
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
                    user.name,
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    user.displayRole,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    user.phone,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textTertiary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(
              AppIcons.edit_2,
              size: 16,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () => _confirmDeleteUser(context, user),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.glassPrimary,
                  border: Border.all(color: AppColors.glassBorder),
                ),
                child: const Icon(
                  AppIcons.trash,
                  size: 18,
                  color: AppColors.critical,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RolePill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _RolePill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 48,
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.glassPrimary,
          borderRadius: BorderRadius.circular(24),
          border: selected ? null : Border.all(color: AppColors.glassBorder),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Text(
            label,
            style: AppTypography.bodySmall.copyWith(
              fontWeight: FontWeight.bold,
              color: selected ? Colors.white : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
