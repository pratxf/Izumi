import 'dart:async';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:izumi/core/ui/app_icons.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../utils/alphabet_filter_utils.dart';
import '../../widgets/glass/gradient_background.dart';
import '../../widgets/navigation/app_header.dart';
import '../../services/geocoding_cache.dart';
import '../../widgets/inputs/text_input_field.dart';

/// Dashboard Screen - Enterprise Admin
/// Overview with search, stats, and employee list
class DashboardScreen extends StatefulWidget {
  final VoidCallback? onAvatarTap;

  const DashboardScreen({super.key, this.onAvatarTap});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  final _searchController = TextEditingController();
  String _statusFilter = 'active';
  String? _lastLoadedEnterpriseId;
  bool _hasUnread = false;
  StreamSubscription? _unreadSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDashboard();
      _listenUnread();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resumeData();
    }
  }

  void _resumeData() {
    if (!mounted) return;
    final enterpriseId = context.read<AuthProvider>().enterpriseId;
    if (enterpriseId != null) {
      context.read<DashboardProvider>().initDashboard(enterpriseId);
    }
  }

  void _listenUnread() {
    final userId = context.read<AuthProvider>().currentUser?.id;
    if (userId == null) return;
    _unreadSub = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .where('isRead', isEqualTo: false)
        .limit(1)
        .snapshots()
        .listen((snap) {
      if (mounted) setState(() => _hasUnread = snap.docs.isNotEmpty);
    });
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
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _unreadSub?.cancel();
    super.dispose();
  }

  String _signalLostLabel(Map<String, dynamic>? presence) {
    final signalLostAt = presence?['signalLostAt'];
    if (signalLostAt is! num) return 'Signal Lost';
    final minutes =
        DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(signalLostAt.toInt())).inMinutes;
    if (minutes < 5) return 'Signal Lost (Reconnecting...)';
    if (minutes < 15) return 'Signal Lost (${minutes}m ago)';
    return 'Signal Lost (Ending session...)';
  }

  String _statusFilterLabel() {
    switch (_statusFilter) {
      case 'signal_lost':
        return 'signal lost';
      default:
        return _statusFilter;
    }
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
        return e.name.toLowerCase().contains(query) || location.contains(query);
      }).toList();
    }

    employees = sortUsersByName(employees, true);

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
    if (_statusFilter == 'signal_lost') {
      return employees
          .where(
              (e) => dashboardProvider.getEmployeeStatus(e.id) == 'signal_lost')
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
              hasUnread: _hasUnread,
              showLeading: false,
              avatarUrl:
                  context.watch<AuthProvider>().currentUser?.profileImageUrl,
              onNotificationTap: () {
                context.push('/employee/notifications');
              },
              onAvatarTap: () => context.push('/admin/profile'),
            ),

            // Search Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: GlassInputField(
                controller: _searchController,
                hint: 'Search employees...',
                prefixIcon: AppIcons.search_normal,
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
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _buildOverviewCard(
                          icon: AppIcons.people,
                          label: 'Active',
                          value: '${dashboardProvider.activeCount}',
                          sublabel: 'Personnel online',
                          showPulse: true,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildOverviewCard(
                          icon: AppIcons.user_remove,
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
            const SizedBox(height: 18),

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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
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
                              const SizedBox(height: 14),
                              Center(
                                child: Wrap(
                                  alignment: WrapAlignment.center,
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _buildFilterPill(
                                      label: 'Active',
                                      selected: _statusFilter == 'active',
                                      onTap: () => setState(
                                          () => _statusFilter = 'active'),
                                    ),
                                    _buildFilterPill(
                                      label: 'Offline',
                                      selected: _statusFilter == 'offline',
                                      onTap: () => setState(
                                          () => _statusFilter = 'offline'),
                                    ),
                                    _buildFilterPill(
                                      label: 'Signal Lost',
                                      selected: _statusFilter == 'signal_lost',
                                      onTap: () => setState(
                                          () => _statusFilter = 'signal_lost'),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        Expanded(
                          child: filteredEmployees.isEmpty
                              ? Center(
                                  child: Text(
                                    'No ${_statusFilterLabel()} employees found',
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
    required String sublabel,
    bool showPulse = false,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 132,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.glassPrimary,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.glassBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
              ),
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
                  Flexible(
                    child: Text(
                      label,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: AppTypography.displayLarge.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 30,
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.glassStrong,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.glassBorder,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.14),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [],
        ),
        child: Text(
          label,
          style: AppTypography.caption.copyWith(
            color: selected ? Colors.white : AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  String _resolveLocationAddress(
      String rawAddress, Map<String, dynamic>? locationData) {
    if (!GeocodingCache.isCoordinateString(rawAddress)) return rawAddress;

    // Try to extract lat/lng and check cache
    final lat = (locationData?['latitude'] as num?)?.toDouble();
    final lng = (locationData?['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null) {
      final parsed = GeocodingCache.parseCoordinates(rawAddress);
      if (parsed == null) return rawAddress;
      final cached = GeocodingCache.instance.getCached(parsed.$1, parsed.$2);
      if (cached != null) return cached;
      // Fire async resolve and rebuild when done
      GeocodingCache.instance.resolve(parsed.$1, parsed.$2).then((_) {
        if (mounted) setState(() {});
      });
      return '${parsed.$1.toStringAsFixed(4)}, ${parsed.$2.toStringAsFixed(4)}';
    }

    final cached = GeocodingCache.instance.getCached(lat, lng);
    if (cached != null) return cached;
    // Fire async resolve and rebuild when done
    GeocodingCache.instance.resolve(lat, lng).then((_) {
      if (mounted) setState(() {});
    });
    return '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
  }

  Widget _buildEmployeeCard(
      UserModel employee, DashboardProvider dashboardProvider) {
    final status = dashboardProvider.getEmployeeStatus(employee.id);
    final isActive = status == 'active';
    final isBreak = status == 'break';
    final isSignalLost = status == 'signal_lost';
    final isOnClock = dashboardProvider.isEmployeeOnClock(employee.id);

    final locationData = dashboardProvider.getEmployeeLocation(employee.id);
    final rawAddress =
        locationData?['address'] as String? ?? 'Location unavailable';
    final locationAddress = _resolveLocationAddress(rawAddress, locationData);
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
    final durationSec = stats?['sessionDuration'] as num? ?? 0;
    final durationMin = (durationSec / 60).round();
    final durationStr = durationMin >= 60
        ? '${durationMin ~/ 60}h ${durationMin % 60}m'
        : '${durationMin}m';

    Color statusColor = isActive
        ? AppColors.success
        : isBreak
            ? AppColors.warning
            : isSignalLost
                ? AppColors.warningDark
                : AppColors.textDisabled;

    Color statusBgColor = isActive
        ? AppColors.badgeActiveBackground
        : isBreak
            ? AppColors.badgeBreakBackground
            : isSignalLost
                ? AppColors.badgeWarning
                : AppColors.badgeOfflineBackground;

    String statusLabel = isActive
        ? 'ACTIVE'
        : isBreak
            ? 'BREAK'
            : isSignalLost
                ? _signalLostLabel(dashboardProvider.presenceData[employee.id])
                : 'OFFLINE';

    return GestureDetector(
      onTap: () {
        context.push(
          '/admin/employee/${employee.id}',
          extra: {
            'name': employee.name,
            'isActive': isOnClock,
            'avatarUrl':
                employee.profileImageUrl ?? 'https://i.pravatar.cc/150?img=11',
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
                                AppIcons.location,
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
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: isSignalLost ? 124 : 96,
                      ),
                      child: Container(
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
                          maxLines: isSignalLost ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: isSignalLost ? 9 : 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
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
