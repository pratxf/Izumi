import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_shadows.dart';
import '../../core/constants/app_typography.dart';
import '../../models/user_model.dart';
import '../../providers/analytics_provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/glass/gradient_background.dart';
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
  final List<String> _periods = ['Today', 'This Week', 'This Month'];
  bool _initialized = false;

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
  Widget build(BuildContext context) {
    final analytics = context.watch<AnalyticsProvider>();
    final employees = analytics.employees;
    final sortedEmployees = List<UserModel>.from(employees)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

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
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Employee Logs',
                                    style: AppTypography.h3.copyWith(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.surfaceMuted,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: AppColors.glassBorder,
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Iconsax.sort,
                                          size: 14,
                                          color: AppColors.textSecondary,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Sort',
                                          style: AppTypography.caption.copyWith(
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
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
                                  final stats = analytics.getEmployeeStats(emp.id);
                                  final hours = stats['hours'] as int;
                                  final distance = stats['distance'] as double;
                                  final photos = stats['photos'] as int;

                                  return _buildEmployeeCard(
                                    name: emp.name,
                                    hours: hours,
                                    distance: distance,
                                    photos: photos,
                                    isTop: false,
                                    onTap: () {
                                      final logs = analytics.getLogsForEmployee(emp.id);
                                      final activities = logs
                                          .map((log) => <String, String>{
                                                'title': log.title,
                                                'time': log.timeAgo,
                                                'detail': log.detail,
                                                'type': log.type,
                                              })
                                          .toList();

                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => EmployeeActivityScreen(
                                            employeeName: emp.name,
                                            periodLabel: analytics.selectedPeriod,
                                            activities: activities,
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
            Icon(Iconsax.calendar_1, size: 18, color: AppColors.textPrimary),
            const SizedBox(width: 8),
            Text(
              analytics.selectedPeriod,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textOnGradient,
                fontWeight: FontWeight.w600,
              ),
            ),
            Icon(
              Iconsax.arrow_down_1,
              size: 18,
              color: AppColors.textPrimary,
            ),
          ],
        ),
      ),
    );
  }

  void _showPeriodPicker(AnalyticsProvider analytics) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
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
                    ? Icon(Iconsax.tick_circle, color: AppColors.primary)
                    : null,
                onTap: () {
                  final auth = context.read<AuthProvider>();
                  final enterpriseId = auth.enterpriseId ?? '';
                  analytics.loadAnalytics(enterpriseId, period: period);
                  Navigator.pop(context);
                },
              ),
            ),
          ],
        ),
      ),
    );
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
                  Icon(Iconsax.chart, size: 20, color: AppColors.textSecondary),
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
                children: [
                  _buildSummaryItem(
                    icon: Iconsax.people,
                    value: '${analytics.employees.length}',
                    label: 'Active',
                    color: AppColors.iconBlue,
                  ),
                  _buildSummaryItem(
                    icon: Iconsax.timer_1,
                    value: '${analytics.totalHours}h',
                    label: 'Hours',
                    color: AppColors.iconOrange,
                  ),
                  _buildSummaryItem(
                    icon: Iconsax.routing_2,
                    value: analytics.totalDistance.toStringAsFixed(0),
                    label: 'km',
                    color: AppColors.iconTeal,
                  ),
                  _buildSummaryItem(
                    icon: Iconsax.gallery,
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
          Text(
            value,
            style: AppTypography.h3.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: AppTypography.overline.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmployeeCard({
    required String name,
    required int hours,
    required double distance,
    required int photos,
    required VoidCallback onTap,
    bool isTop = false,
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
          border: Border.all(
            color: isTop
                ? AppColors.primary.withValues(alpha: 0.5)
                : AppColors.glassBorder,
          ),
          boxShadow: AppShadows.glass,
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isTop
                    ? AppColors.primary.withValues(alpha: 0.1)
                    : AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Text(
                  initials,
                  style: AppTypography.bodyMedium.copyWith(
                    color: isTop ? AppColors.primary : AppColors.textSecondary,
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
                  Row(
                    children: [
                      Text(
                        name,
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (isTop) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Top',
                            style: AppTypography.overline.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
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
                      Iconsax.timer_1,
                      '${hours}h',
                      AppColors.iconOrange,
                    ),
                    const SizedBox(width: 12),
                    _buildMiniStat(
                      Iconsax.routing_2,
                      '${distance.toStringAsFixed(0)}km',
                      AppColors.iconTeal,
                    ),
                    const SizedBox(width: 12),
                    _buildMiniStat(
                      Iconsax.gallery,
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
