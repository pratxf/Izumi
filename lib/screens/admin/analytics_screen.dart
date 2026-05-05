import 'package:flutter/material.dart';
import 'package:izumi/core/ui/app_icons.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';
import '../../providers/analytics_provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/glass/gradient_background.dart';
import '../../widgets/navigation/app_header.dart';
import 'employee_activity_screen.dart';

/// Analytics Screen - Enterprise activity overview with daily bar chart
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  String _searchQuery = '';
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
    final enterpriseId = context.read<AuthProvider>().enterpriseId;
    if (enterpriseId == null || enterpriseId.isEmpty) return;
    context.read<AnalyticsProvider>().loadAnalytics(enterpriseId);
  }

  // ---------------------------------------------------------------------------
  // Period selection
  // ---------------------------------------------------------------------------

  void _onPeriodSelected(String period) {
    final enterpriseId = context.read<AuthProvider>().enterpriseId;
    if (enterpriseId == null || enterpriseId.isEmpty) return;

    if (period == 'Custom') {
      _showCustomDatePicker();
    } else {
      context.read<AnalyticsProvider>().loadAnalytics(
            enterpriseId,
            period: period,
          );
    }
  }

  void _showPeriodPicker() {
    final analytics = context.read<AnalyticsProvider>();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text(
                  'Select Period',
                  style: AppTypography.headline.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                for (final period in [
                  'Today',
                  'Yesterday',
                  'This Month',
                  'Custom',
                ])
                  ListTile(
                    title: Text(
                      period,
                      style: AppTypography.body.copyWith(
                        color: analytics.selectedPeriod == period
                            ? AppColors.primary
                            : AppColors.textPrimary,
                        fontWeight: analytics.selectedPeriod == period
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                    trailing: analytics.selectedPeriod == period
                        ? const Icon(Icons.check, color: AppColors.primary)
                        : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      _onPeriodSelected(period);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showCustomDatePicker() async {
    final analytics = context.read<AnalyticsProvider>();
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
      builder: (ctx, child) {
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
      final enterpriseId = context.read<AuthProvider>().enterpriseId;
      if (enterpriseId == null || enterpriseId.isEmpty) return;
      context.read<AnalyticsProvider>().loadCustomRange(
            enterpriseId,
            picked.start,
            picked.end,
          );
    }
  }

  // ---------------------------------------------------------------------------
  // Filter range helper
  // ---------------------------------------------------------------------------

  (DateTime?, DateTime?) _resolveFilterRange(AnalyticsProvider analytics) {
    final now = DateTime.now();
    switch (analytics.selectedPeriod) {
      case 'Today':
        return (DateTime(now.year, now.month, now.day), now);
      case 'Yesterday':
        final yesterday = now.subtract(const Duration(days: 1));
        return (
          DateTime(yesterday.year, yesterday.month, yesterday.day),
          DateTime(yesterday.year, yesterday.month, yesterday.day, 23, 59, 59),
        );
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

  // ---------------------------------------------------------------------------
  // Chip label mapping
  // ---------------------------------------------------------------------------

  String _periodLabel(AnalyticsProvider analytics) {
    if (analytics.selectedPeriod == 'Custom' &&
        analytics.customStart != null &&
        analytics.customEnd != null) {
      final fmt = MaterialLocalizations.of(context);
      return '${fmt.formatShortDate(analytics.customStart!)} - ${fmt.formatShortDate(analytics.customEnd!)}';
    }
    return analytics.selectedPeriod;
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final analytics = context.watch<AnalyticsProvider>();

    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppHeader(
          title: 'Analytics',
          showAvatar: false,
          showLeading: false,
          actions: [_buildPeriodButton(analytics)],
        ),
        body: analytics.isLoading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            : _buildBody(analytics),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Period pill chips
  // ---------------------------------------------------------------------------

  Widget _buildPeriodButton(AnalyticsProvider analytics) {
    return GestureDetector(
      onTap: _showPeriodPicker,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppIcons.calendar, size: 14, color: AppColors.primary),
            const SizedBox(width: 6),
            Text(
              _periodLabel(analytics),
              style: AppTypography.caption.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down_rounded,
                size: 16, color: AppColors.primary),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Body
  // ---------------------------------------------------------------------------

  Widget _buildBody(AnalyticsProvider analytics) {
    final showChart = analytics.selectedPeriod == 'This Week' ||
        analytics.selectedPeriod == 'This Month';

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSummaryCards(analytics),
          if (showChart) ...[
            const SizedBox(height: 20),
            _buildDailyBarChart(analytics),
          ],
          const SizedBox(height: 20),
          _buildEmployeeLogsSection(analytics),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Enterprise Summary Cards
  // ---------------------------------------------------------------------------

  Widget _buildSummaryCards(AnalyticsProvider analytics) {
    return Row(
      children: [
        Expanded(
          child: _SummaryCard(
            value: analytics.formattedTotalDuration,
            label: 'Hours',
            icon: AppIcons.clock,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SummaryCard(
            value: '${analytics.totalDistance.toInt()}',
            label: 'km',
            icon: AppIcons.routing_2,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SummaryCard(
            value: '${analytics.totalPhotos}',
            label: 'Photos',
            icon: AppIcons.camera,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Daily Bar Chart
  // ---------------------------------------------------------------------------

  Widget _buildDailyBarChart(AnalyticsProvider analytics) {
    final dailyHours = _aggregateDailyHours(analytics);
    if (dailyHours.isEmpty) return const SizedBox.shrink();

    final sortedDates = dailyHours.keys.toList()..sort();
    final maxHours =
        dailyHours.values.fold<double>(0, (a, b) => a > b ? a : b);
    final yMax = maxHours < 1 ? 1.0 : (maxHours * 1.2).ceilToDouble();
    final isWeek = analytics.selectedPeriod == 'This Week';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.12),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Daily Hours',
            style: AppTypography.bodySmall.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 100,
            child: BarChart(
              BarChartData(
                maxY: yMax,
                barTouchData: BarTouchData(enabled: false),
                titlesData: FlTitlesData(
                  show: true,
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (value, meta) {
                        if (value == 0 || value == meta.max) {
                          return Text(
                            '${value.toInt()}h',
                            style: AppTypography.small.copyWith(fontSize: 10),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= sortedDates.length) {
                          return const SizedBox.shrink();
                        }
                        final date = sortedDates[idx];
                        String label;
                        if (isWeek) {
                          const days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
                          label = days[date.weekday - 1];
                        } else {
                          label = '${date.day}';
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            label,
                            style: AppTypography.small.copyWith(fontSize: 10),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                barGroups: List.generate(sortedDates.length, (i) {
                  final hours = dailyHours[sortedDates[i]] ?? 0;
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: hours,
                        color: AppColors.primary,
                        width: isWeek ? 16 : 8,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(4),
                          topRight: Radius.circular(4),
                        ),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Flatten all employee summaries, group by date, sum totalDuration, convert
  /// to fractional hours.
  Map<DateTime, double> _aggregateDailyHours(AnalyticsProvider analytics) {
    final Map<DateTime, int> dailySecs = {};
    for (final summaries in analytics.employeeSummaries.values) {
      for (final s in summaries) {
        final dateKey = DateTime(s.date.year, s.date.month, s.date.day);
        dailySecs[dateKey] = (dailySecs[dateKey] ?? 0) + s.totalDuration;
      }
    }
    return dailySecs.map((date, secs) => MapEntry(date, secs / 3600.0));
  }

  // ---------------------------------------------------------------------------
  // Employee Logs Section
  // ---------------------------------------------------------------------------

  Widget _buildEmployeeLogsSection(AnalyticsProvider analytics) {
    final employees = analytics.employees;

    // Build sorted list with stats
    final employeeStats = employees.map((emp) {
      final stats = analytics.getEmployeeStats(emp.id);
      return (employee: emp, stats: stats);
    }).toList();

    // Sort by duration descending
    employeeStats.sort((a, b) {
      final aDur = (a.stats['durationSecs'] as int?) ?? 0;
      final bDur = (b.stats['durationSecs'] as int?) ?? 0;
      final cmp = bDur.compareTo(aDur);
      if (cmp != 0) return cmp;
      return a.employee.name
          .toLowerCase()
          .compareTo(b.employee.name.toLowerCase());
    });

    // Filter by search query
    final normalizedQuery = _searchQuery.trim().toLowerCase();
    final filtered = normalizedQuery.isEmpty
        ? employeeStats
        : employeeStats.where((e) {
            return e.employee.name.toLowerCase().contains(normalizedQuery);
          }).toList();

    // Top employee duration for progress bar proportion
    final topDurationSecs = employeeStats.isNotEmpty
        ? ((employeeStats.first.stats['durationSecs'] as int?) ?? 1)
            .clamp(1, double.maxFinite.toInt())
        : 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Employee logs',
          style: AppTypography.headline.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        // Search field
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.divider, width: 0.5),
          ),
          child: TextField(
            onChanged: (val) => setState(() => _searchQuery = val),
            style: AppTypography.body,
            decoration: InputDecoration(
              hintText: 'Search employees...',
              hintStyle: AppTypography.inputHint,
              prefixIcon: const Icon(
                AppIcons.search_normal,
                size: 18,
                color: AppColors.textTertiary,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text('No employees found', style: AppTypography.bodySmall),
            ),
          )
        else
          ...filtered.map((entry) {
            return _buildEmployeeCard(
              analytics: analytics,
              emp: entry.employee,
              stats: entry.stats,
              topDurationSecs: topDurationSecs,
            );
          }),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Employee Card
  // ---------------------------------------------------------------------------

  Widget _buildEmployeeCard({
    required AnalyticsProvider analytics,
    required dynamic emp,
    required Map<String, dynamic> stats,
    required int topDurationSecs,
  }) {
    final resolvedProfileImageUrl =
        analytics.getResolvedProfileImageUrl(emp.id);
    final durationSecs = (stats['durationSecs'] as int?) ?? 0;
    final proportion = topDurationSecs > 0
        ? (durationSecs / topDurationSecs).clamp(0.0, 1.0)
        : 0.0;

    return GestureDetector(
      onTap: () => _navigateToEmployeeActivity(analytics, emp),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider, width: 0.5),
        ),
        child: Row(
          children: [
            // Avatar
            _buildAvatar(emp, resolvedProfileImageUrl),
            const SizedBox(width: 12),
            // Name and stats
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    emp.name,
                    style: AppTypography.bodySmall.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _StatChip(
                        icon: AppIcons.clock,
                        value: stats['duration'] as String? ?? '0m',
                      ),
                      const SizedBox(width: 8),
                      _StatChip(
                        icon: AppIcons.routing_2,
                        value:
                            '${analytics.getEmployeeDistance(emp.id).toStringAsFixed(1)} km',
                      ),
                      const SizedBox(width: 8),
                      _StatChip(
                        icon: AppIcons.camera,
                        value: '${(stats['photos'] as int?) ?? 0}',
                      ),
                      const SizedBox(width: 8),
                      _StatChip(
                        icon: AppIcons.calendar_tick,
                        value: '${analytics.getEmployeeLeaveCount(emp.id)} L',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Mini progress bar
            SizedBox(
              width: 60,
              height: 4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: proportion,
                  backgroundColor: AppColors.divider,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(dynamic emp, String? profileImageUrl) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primary.withValues(alpha: 0.1),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.16),
        ),
      ),
      child: profileImageUrl != null && profileImageUrl.isNotEmpty
          ? ClipOval(
              child: Image.network(
                profileImageUrl,
                fit: BoxFit.cover,
                width: 40,
                height: 40,
                errorBuilder: (_, __, ___) => _buildInitials(emp),
              ),
            )
          : _buildInitials(emp),
    );
  }

  Widget _buildInitials(dynamic emp) {
    return Center(
      child: Text(
        emp.initials,
        style: AppTypography.small.copyWith(
          color: AppColors.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------------

  void _navigateToEmployeeActivity(AnalyticsProvider analytics, dynamic emp) {
    final resolvedProfileImageUrl =
        analytics.getResolvedProfileImageUrl(emp.id);
    final stats = analytics.getEmployeeStats(emp.id);
    final liveStats = analytics.activeStatsData[emp.id];
    final filterRange = _resolveFilterRange(analytics);
    final initialDate = filterRange.$1;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EmployeeActivityScreen(
          employeeName: emp.name,
          employeeId: emp.id,
          profileImageUrl: resolvedProfileImageUrl,
          linkedEmployeeIds: [
            emp.id,
            if (emp.migratedFrom != null && emp.migratedFrom!.isNotEmpty)
              emp.migratedFrom!,
          ],
          initialActivities: const [],
          initialDate: initialDate,
          initialLiveStats: liveStats,
          initialAggregateStats: stats,
          selectedPeriod: analytics.selectedPeriod,
          rangeStart: filterRange.$1,
          rangeEnd: filterRange.$2,
        ),
      ),
    );
  }
}

// =============================================================================
// Summary Card Widget
// =============================================================================

class _SummaryCard extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;

  const _SummaryCard({
    required this.value,
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(79, 70, 229, 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.12),
          width: 0.5,
        ),
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: AppTypography.headline.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppTypography.small.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Stat Chip Widget (icon + value inline)
// =============================================================================

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String value;

  const _StatChip({
    required this.icon,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.textTertiary),
        const SizedBox(width: 3),
        Text(
          value,
          style: AppTypography.small.copyWith(fontSize: 11),
        ),
      ],
    );
  }
}
