import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:izumi/core/ui/app_icons.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_shadows.dart';
import '../../core/constants/app_typography.dart';
import '../../providers/analytics_provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/glass/gradient_background.dart';
import '../../widgets/inputs/text_input_field.dart';
import '../../widgets/navigation/app_header.dart';
import 'employee_activity_screen.dart';

/// Analytics Screen - Glassmorphism Design
/// Enterprise activity overview
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final List<String> _periods = ['Today', 'This Week', 'This Month', 'Custom'];
  final TextEditingController _searchController = TextEditingController();
  bool _initialized = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initProvider();
    });
  }

  void _initProvider() {
    if (_initialized) return;
    _initialized = true;
    final auth = context.read<AuthProvider>();
    final enterpriseId = auth.enterpriseId ?? '';
    if (enterpriseId.isEmpty) return;
    context.read<AnalyticsProvider>().loadAnalytics(enterpriseId);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final analytics = context.watch<AnalyticsProvider>();
    final employees = analytics.employees;
    final normalizedQuery = _searchQuery.trim().toLowerCase();
    final filteredEmployees = normalizedQuery.isEmpty
        ? employees
        : employees
            .where((employee) =>
                employee.name.toLowerCase().contains(normalizedQuery) ||
                employee.phone.toLowerCase().contains(normalizedQuery))
            .toList();
    final sortedEmployees = [...filteredEmployees]..sort((a, b) {
        final aStats = analytics.getEmployeeStats(a.id);
        final bStats = analytics.getEmployeeStats(b.id);
        final aDuration = aStats['durationSecs'] as int? ?? 0;
        final bDuration = bStats['durationSecs'] as int? ?? 0;
        final durationCompare = bDuration.compareTo(aDuration);
        if (durationCompare != 0) return durationCompare;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    return GradientBackground(
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AppHeader(
              title: 'Analytics',
              type: AppHeaderType.primary,
              showAvatar: false,
              showLeading: false,
              actions: [_buildPeriodSelector(analytics)],
            ),
            const SizedBox(height: 16),

            // Summary Stats
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _buildSummaryCard(analytics),
            ),
            const SizedBox(height: 24),

            // Content Panel
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.glassStrong,
                      AppColors.glassPrimary,
                    ],
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(32),
                  ),
                  border: Border(
                    top: BorderSide(color: AppColors.glassBorder),
                    left: BorderSide(color: AppColors.glassBorder),
                    right: BorderSide(color: AppColors.glassBorder),
                  ),
                  boxShadow: AppShadows.glass,
                ),
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(32),
                  ),
                  child: analytics.isLoading
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: AppColors.primary,
                          ),
                        )
                      : SingleChildScrollView(
                          padding: EdgeInsets.only(
                            left: 20,
                            right: 20,
                            top: 24,
                            bottom: 120,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Section Header
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Employee Logs',
                                    style: AppTypography.h3.copyWith(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              GlassInputField(
                                controller: _searchController,
                                hint: 'Search employees',
                                prefixIcon: AppIcons.search_normal,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                onChanged: (value) =>
                                    setState(() => _searchQuery = value),
                              ),
                              const SizedBox(height: 16),

                              if (sortedEmployees.isEmpty)
                                Center(
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 32),
                                    child: Text(
                                      'No employee data',
                                      style: AppTypography.bodyMedium.copyWith(
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ),
                                )
                              else
                                // Employee Performance Cards
                                ...sortedEmployees.map((emp) {
                                  final stats =
                                      analytics.getEmployeeStats(emp.id);
                                  final resolvedProfileImageUrl =
                                      analytics.getResolvedProfileImageUrl(
                                    emp.id,
                                  );
                                  final duration = stats['duration'] as String;
                                  final distance = stats['distance'] as double;
                                  final photos = stats['photos'] as int;

                                  return _buildEmployeeCard(
                                    name: emp.name,
                                    profileImageUrl: resolvedProfileImageUrl,
                                    duration: duration,
                                    distance: distance,
                                    photos: photos,
                                    onTap: () {
                                      final liveStats =
                                          analytics.activeStatsData[emp.id];
                                      final filterRange =
                                          _resolveFilterRange(analytics);
                                      final initialDate =
                                          filterRange.$1 ?? DateTime.now();

                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              EmployeeActivityScreen(
                                            employeeName: emp.name,
                                            employeeId: emp.id,
                                            profileImageUrl:
                                                resolvedProfileImageUrl,
                                            linkedEmployeeIds: [
                                              emp.id,
                                              if (emp.migratedFrom != null &&
                                                  emp.migratedFrom!.isNotEmpty)
                                                emp.migratedFrom!,
                                            ],
                                            initialActivities: const [],
                                            initialDate: initialDate,
                                            initialLiveStats: liveStats,
                                            initialAggregateStats: stats,
                                            selectedPeriod:
                                                analytics.selectedPeriod,
                                            rangeStart: filterRange.$1,
                                            rangeEnd: filterRange.$2,
                                          ),
                                        ),
                                      );
                                    },
                                  );
                                }),
                            ],
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodSelector(AnalyticsProvider analytics) {
    String label = analytics.selectedPeriod;
    if (analytics.selectedPeriod == 'Custom' &&
        analytics.customStart != null &&
        analytics.customEnd != null) {
      final fmt = DateFormat('dd MMM');
      label =
          '${fmt.format(analytics.customStart!)} – ${fmt.format(analytics.customEnd!)}';
    }

    return GestureDetector(
      onTap: () => _showPeriodPicker(analytics),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.glassPrimary,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppIcons.calendar_1, size: 18, color: AppColors.textPrimary),
            const SizedBox(width: 8),
            Text(
              label,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textOnGradient,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPeriodPicker(AnalyticsProvider analytics) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          24 + MediaQuery.of(sheetContext).viewPadding.bottom,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Select Period', style: AppTypography.h3),
            const SizedBox(height: 16),
            ..._periods.map(
              (period) => ListTile(
                title: Text(period),
                trailing: analytics.selectedPeriod == period
                    ? Icon(AppIcons.check, color: AppColors.primary)
                    : null,
                onTap: () {
                  Navigator.pop(sheetContext);
                  if (period == 'Custom') {
                    _showCustomDatePicker(analytics);
                  } else {
                    final auth = context.read<AuthProvider>();
                    final enterpriseId = auth.enterpriseId ?? '';
                    analytics.loadAnalytics(enterpriseId, period: period);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCustomDatePicker(AnalyticsProvider analytics) async {
    final now = DateTime.now();
    final initialRange = DateTimeRange(
      start: analytics.customStart ?? now.subtract(const Duration(days: 7)),
      end: analytics.customEnd ?? now,
    );

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: now,
      initialDateRange: initialRange,
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              surface: AppColors.gradientMid,
              onSurface: AppColors.textPrimary,
            ),
            dialogTheme: const DialogThemeData(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(24)),
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && mounted) {
      final auth = context.read<AuthProvider>();
      final enterpriseId = auth.enterpriseId ?? '';
      analytics.loadCustomRange(enterpriseId, picked.start, picked.end);
    }
  }

  (DateTime?, DateTime?) _resolveFilterRange(AnalyticsProvider analytics) {
    final now = DateTime.now();
    switch (analytics.selectedPeriod) {
      case 'Today':
        final start = DateTime(now.year, now.month, now.day);
        return (start, now);
      case 'This Week':
        final start = now.subtract(Duration(days: now.weekday - 1));
        return (DateTime(start.year, start.month, start.day), now);
      case 'This Month':
        return (DateTime(now.year, now.month, 1), now);
      case 'Custom':
        return (analytics.customStart, analytics.customEnd);
      default:
        return (null, null);
    }
  }

  Widget _buildSummaryCard(AnalyticsProvider analytics) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: AppColors.glassPanelGradient,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(AppIcons.chart, size: 20, color: AppColors.textSecondary),
                  const SizedBox(width: 8),
                  Text(
                    'Enterprise Summary',
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSummaryItem(
                    icon: AppIcons.timer_1,
                    value: analytics.formattedTotalDuration,
                    label: 'Hours',
                    color: AppColors.iconOrange,
                  ),
                  const SizedBox(width: 12),
                  _buildSummaryItem(
                    icon: AppIcons.routing_2,
                    value: analytics.totalDistance.toStringAsFixed(0),
                    label: 'km',
                    color: AppColors.iconTeal,
                  ),
                  const SizedBox(width: 12),
                  _buildSummaryItem(
                    icon: AppIcons.gallery,
                    value: '${analytics.totalPhotos}',
                    label: 'Photos',
                    color: AppColors.iconAmber,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryItem({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 28,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  style: AppTypography.h3.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 16,
            child: Center(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: AppTypography.overline.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmployeeCard({
    required String name,
    required String? profileImageUrl,
    required String duration,
    required double distance,
    required int photos,
    required VoidCallback onTap,
  }) {
    final initials = name.split(' ').take(2).map((e) => e[0]).join('');

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.glassPrimary,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.glassBorder),
          boxShadow: AppShadows.glass,
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(16),
              ),
              clipBehavior: Clip.antiAlias,
              child: profileImageUrl != null && profileImageUrl.isNotEmpty
                  ? Image.network(
                      profileImageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Center(
                        child: Text(
                          initials,
                          style: AppTypography.bodyMedium.copyWith(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    )
                  : Center(
                      child: Text(
                        initials,
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 16),

            // Name
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            // Stats
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildMiniStat(
                      AppIcons.timer_1,
                      duration,
                      AppColors.iconOrange,
                    ),
                    const SizedBox(width: 12),
                    _buildMiniStat(
                      AppIcons.routing_2,
                      '${distance.toStringAsFixed(0)}km',
                      AppColors.iconTeal,
                    ),
                    const SizedBox(width: 12),
                    _buildMiniStat(
                      AppIcons.gallery,
                      '$photos',
                      AppColors.iconAmber,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniStat(IconData icon, String value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(
          value,
          style: AppTypography.caption.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
