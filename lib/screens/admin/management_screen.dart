import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_typography.dart';
import '../../providers/auth_provider.dart';
import '../../providers/group_provider.dart';
import '../../providers/user_provider.dart';
import '../../utils/alphabet_filter_utils.dart';
import '../../widgets/glass/gradient_background.dart';
import '../../widgets/glass/glass_chip.dart';
import '../../widgets/inputs/alphabet_filter.dart';
import '../../widgets/navigation/app_header.dart';
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
  bool _sortAscending = true;
  String? _lastLoadedEnterpriseId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    final enterpriseId = context.read<AuthProvider>().enterpriseId;
    if (enterpriseId != null) {
      _lastLoadedEnterpriseId = enterpriseId;
      context.read<UserProvider>().streamUsers(enterpriseId);
      context.read<GroupProvider>().streamGroups(enterpriseId);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Reactive re-load when enterpriseId becomes available after init
    final enterpriseId = context.watch<AuthProvider>().enterpriseId;
    if (enterpriseId != null && enterpriseId != _lastLoadedEnterpriseId) {
      _lastLoadedEnterpriseId = enterpriseId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<UserProvider>().streamUsers(enterpriseId);
        context.read<GroupProvider>().streamGroups(enterpriseId);
      });
    }

    final userProvider = context.watch<UserProvider>();
    final users = userProvider.users;
    final query = _searchController.text.trim().toLowerCase();
    final filteredUsers = query.isEmpty
        ? users
        : users.where((u) {
            return u.name.toLowerCase().contains(query) ||
                u.phone.contains(query) ||
                u.displayRole.toLowerCase().contains(query);
          }).toList();
    final sortedUsers = sortUsersByName(filteredUsers, _sortAscending);

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
                      '${users.length} Users',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textTertiary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
            if (_activeTab == 1)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: AlphabetFilter(
                  isAscending: _sortAscending,
                  onToggle: (val) => setState(() => _sortAscending = val),
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
                          users: sortedUsers,
                          searchController: _searchController,
                          onSearchChanged: (_) => setState(() {}),
                          onAddUser: () => context.push('/admin/add-user'),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
