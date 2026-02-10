import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../widgets/glass/gradient_background.dart';
import '../../widgets/navigation/app_header.dart';
import '../../widgets/inputs/text_input_field.dart';
import '../notifications/notifications_screen.dart';

/// Dashboard Screen - Enterprise Admin
/// Overview with search, stats, and employee list
class DashboardScreen extends StatefulWidget {
  final VoidCallback? onAvatarTap;

  const DashboardScreen({super.key, this.onAvatarTap});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _searchController = TextEditingController();
  String _statusFilter = 'active';
  String? _lastLoadedEnterpriseId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDashboard());
  }

  void _loadDashboard() {
    final enterpriseId = context.read<AuthProvider>().enterpriseId;
    if (enterpriseId != null && enterpriseId != _lastLoadedEnterpriseId) {
      _lastLoadedEnterpriseId = enterpriseId;
      context.read<DashboardProvider>().initDashboard(enterpriseId);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: AlertDialog(
          backgroundColor: AppColors.glassStrong,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Text(
            'Logout',
            style: AppTypography.h3.copyWith(color: AppColors.textPrimary),
          ),
          content: Text(
            'Are you sure you want to logout?',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Cancel',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await context.read<AuthProvider>().signOut();
              },
              child: Text(
                'Logout',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.critical,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<UserModel> _getFilteredEmployees(DashboardProvider dashboardProvider) {
    final query = _searchController.text.toLowerCase();
    List<UserModel> employees = dashboardProvider.employees;

    // Apply search filter
    if (query.isNotEmpty) {
      employees = employees.where((e) {
        final location = dashboardProvider
                .getEmployeeLocation(e.id)?['address']
                ?.toString()
                .toLowerCase() ??
            '';
        return e.name.toLowerCase().contains(query) ||
            location.contains(query);
      }).toList();
    }

    // Apply status filter
    if (_statusFilter == 'active') {
      return employees
          .where((e) => dashboardProvider.getEmployeeStatus(e.id) == 'active')
          .toList();
    }
    if (_statusFilter == 'offline') {
      return employees
          .where((e) => dashboardProvider.getEmployeeStatus(e.id) == 'offline')
          .toList();
    }
    return employees;
  }

  @override
  Widget build(BuildContext context) {
    final dashboardProvider = context.watch<DashboardProvider>();
    final employees = dashboardProvider.employees;
    final filteredEmployees = _getFilteredEmployees(dashboardProvider);

    return GradientBackground(
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AppHeader(
              title: 'Dashboard',
              type: AppHeaderType.primary,
              showNotification: true,
              showLeading: false,
              onNotificationTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const NotificationsScreen(),
                  ),
                );
              },
              onAvatarTap: _showLogoutDialog,
            ),

            // Search Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: GlassInputField(
                controller: _searchController,
                hint: 'Search employees...',
                prefixIcon: Iconsax.search_normal,
                onChanged: (_) => setState(() {}),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),

            // Overview Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Overview',
                    style: AppTypography.h3.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _buildOverviewCard(
                          icon: Iconsax.people,
                          label: 'Active',
                          value: '${dashboardProvider.activeCount}',
                          sublabel: 'Personnel online',
                          showPulse: true,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildOverviewCard(
                          icon: Iconsax.user_remove,
                          label: 'Offline',
                          value: '${dashboardProvider.offlineCount}',
                          sublabel: 'Personnel offline',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // All Employees Section
            Expanded(
              child: dashboardProvider.isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              RichText(
                                text: TextSpan(
                                  style: AppTypography.h3.copyWith(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  children: [
                                    const TextSpan(text: 'All Employees '),
                                    TextSpan(
                                      text: '(${employees.length})',
                                      style: TextStyle(
                                        color: AppColors.textSecondary,
                                        fontWeight: FontWeight.normal,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Row(
                                children: [
                                  _buildFilterPill(
                                    label: 'Active',
                                    selected: _statusFilter == 'active',
                                    onTap: () =>
                                        setState(() => _statusFilter = 'active'),
                                  ),
                                  const SizedBox(width: 8),
                                  _buildFilterPill(
                                    label: 'Offline',
                                    selected: _statusFilter == 'offline',
                                    onTap: () => setState(
                                        () => _statusFilter = 'offline'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: filteredEmployees.isEmpty
                              ? Center(
                                  child: Text(
                                    'No $_statusFilter employees found',
                                    style: AppTypography.bodyMedium.copyWith(
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  padding: const EdgeInsets.only(
                                    left: 24,
                                    right: 24,
                                    bottom: 120,
                                  ),
                                  itemCount: filteredEmployees.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 16),
                                  itemBuilder: (context, index) {
                                    return _buildEmployeeCard(
                                      filteredEmployees[index],
                                      dashboardProvider,
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewCard({
    required IconData icon,
    required String label,
    required String value,
    String? unit,
    required String sublabel,
    bool showPulse = false,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 144,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.glassPrimary,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.glassBorder),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05), blurRadius: 10),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  if (showPulse)
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.success.withValues(alpha: 0.4),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    )
                  else
                    Icon(icon, size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: value,
                          style: AppTypography.displayLarge.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: unit != null ? 30 : 40,
                          ),
                        ),
                        if (unit != null)
                          TextSpan(
                            text: ' $unit',
                            style: AppTypography.headline.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    sublabel,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterPill({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.glassPrimary,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.glassBorder,
          ),
        ),
        child: Text(
          label,
          style: AppTypography.caption.copyWith(
            color: selected ? AppColors.textPrimary : AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildEmployeeCard(
      UserModel employee, DashboardProvider dashboardProvider) {
    final status = dashboardProvider.getEmployeeStatus(employee.id);
    final isActive = status == 'active';
    final isBreak = status == 'break';

    final locationData = dashboardProvider.getEmployeeLocation(employee.id);
    final locationAddress =
        locationData?['address'] as String? ?? 'Location unavailable';
    final lastUpdated = locationData?['timestamp'];
    String lastUpdatedStr = '';
    if (lastUpdated != null) {
      final ts = DateTime.fromMillisecondsSinceEpoch(lastUpdated is int
          ? lastUpdated
          : int.tryParse(lastUpdated.toString()) ?? 0);
      final diff = DateTime.now().difference(ts);
      if (diff.inMinutes < 1) {
        lastUpdatedStr = 'Just now';
      } else if (diff.inMinutes < 60) {
        lastUpdatedStr = '${diff.inMinutes} min ago';
      } else if (diff.inHours < 24) {
        lastUpdatedStr = '${diff.inHours}h ago';
      } else {
        lastUpdatedStr = '${diff.inDays}d ago';
      }
    }

    final stats = dashboardProvider.getEmployeeStats(employee.id);
    final distance = stats?['distance'] as num? ?? 0.0;
    final durationMs = stats?['duration'] as num? ?? 0;
    final durationMin = (durationMs / 60000).round();
    final durationStr = durationMin >= 60
        ? '${durationMin ~/ 60}h ${durationMin % 60}m'
        : '${durationMin}m';

    Color statusColor = isActive
        ? AppColors.success
        : isBreak
            ? AppColors.warning
            : AppColors.textDisabled;

    Color statusBgColor = isActive
        ? AppColors.badgeActiveBackground
        : isBreak
            ? AppColors.badgeBreakBackground
            : AppColors.badgeOfflineBackground;

    String statusLabel = isActive
        ? 'ACTIVE'
        : isBreak
            ? 'BREAK'
            : 'OFFLINE';

    return GestureDetector(
      onTap: () {
        context.push(
          '/admin/employee/${employee.id}',
          extra: {
            'name': employee.name,
            'isActive': isActive,
            'avatarUrl': employee.profileImageUrl ??
                'https://i.pravatar.cc/150?img=11',
          },
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.glassPrimary,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Column(
              children: [
                // Top row: Avatar, name, status
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Avatar with status dot
                    Stack(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: AppColors.glassBorder, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: employee.profileImageUrl != null
                                ? Image.network(
                                    employee.profileImageUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        _buildAvatarFallback(employee),
                                  )
                                : _buildAvatarFallback(employee),
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: statusColor,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.glassStrong,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    // Name and location
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            employee.name,
                            style: AppTypography.bodyMedium.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Iconsax.location,
                                size: 14,
                                color: AppColors.textSecondary,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  locationAddress,
                                  style: AppTypography.caption.copyWith(
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Status badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusBgColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: statusColor.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),

                // Divider
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Container(
                    height: 1,
                    color: AppColors.glassBorder,
                  ),
                ),

                // Bottom row: Stats
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        _buildStatColumn(
                          'DISTANCE',
                          '${distance.toStringAsFixed(1)} km',
                        ),
                        const SizedBox(width: 40),
                        _buildStatColumn('DURATION', durationStr),
                      ],
                    ),
                    if (lastUpdatedStr.isNotEmpty)
                      Text(
                        'Updated: $lastUpdatedStr',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textTertiary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarFallback(UserModel employee) {
    return Container(
      color: AppColors.surfaceMuted,
      child: Center(
        child: Text(
          employee.initials,
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildStatColumn(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppColors.textTertiary,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
