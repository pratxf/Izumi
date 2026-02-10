import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_shadows.dart';
import '../../core/constants/app_typography.dart';
import '../../models/daily_summary_model.dart';
import '../../models/session_location_model.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/daily_summary_repository.dart';
import '../../repositories/session_repository.dart';
import '../../widgets/glass/gradient_background.dart';
import '../../widgets/navigation/app_header.dart';

/// History Screen - Redesigned per reference
/// Shows monthly summary and daily session logs with timeline
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final DailySummaryRepository _summaryRepo = DailySummaryRepository();
  final SessionRepository _sessionRepo = SessionRepository();

  int _selectedYear = DateTime.now().year;
  int _selectedMonth = DateTime.now().month;
  int? _expandedDay;
  bool _isLoading = true;

  Map<String, dynamic> _monthSummary = {};
  List<DailySummaryModel> _dailySummaries = [];
  // Cache: day index -> session locations
  final Map<int, List<SessionLocationModel>> _locationCache = {};

  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  String get _selectedMonthLabel =>
      '${_monthNames[_selectedMonth - 1]} $_selectedYear';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  Future<void> _loadData() async {
    final auth = context.read<AuthProvider>();
    final userId = auth.currentUser?.id ?? '';
    if (userId.isEmpty) return;

    setState(() => _isLoading = true);
    _locationCache.clear();

    try {
      final startDate = DateTime(_selectedYear, _selectedMonth, 1);
      final endDate = DateTime(_selectedYear, _selectedMonth + 1, 0, 23, 59, 59);

      final results = await Future.wait([
        _summaryRepo.getMonthlySummary(userId, _selectedYear, _selectedMonth),
        _summaryRepo.getDailySummaries(
          userId,
          startDate: startDate,
          endDate: endDate,
        ),
      ]);

      if (!mounted) return;
      setState(() {
        _monthSummary = results[0] as Map<String, dynamic>;
        _dailySummaries = results[1] as List<DailySummaryModel>;
        _isLoading = false;
        // Auto-expand today's card if present
        _expandedDay = _dailySummaries.indexWhere((s) => s.isToday);
        if (_expandedDay == -1) _expandedDay = null;
      });

      // Load locations for today's expanded card
      if (_expandedDay != null) {
        _loadLocationsForDay(_expandedDay!);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      debugPrint('[HistoryScreen] loadData error: $e');
    }
  }

  Future<void> _loadLocationsForDay(int index) async {
    if (_locationCache.containsKey(index)) return;
    final summary = _dailySummaries[index];
    if (summary.sessionIds.isEmpty) return;

    try {
      final allLocations = <SessionLocationModel>[];
      for (final sessionId in summary.sessionIds) {
        final locations = await _sessionRepo.getSessionLocations(sessionId);
        allLocations.addAll(locations);
      }
      // Sort by timestamp
      allLocations.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      if (mounted) {
        setState(() {
          _locationCache[index] = allLocations;
        });
      }
    } catch (e) {
      debugPrint('[HistoryScreen] loadLocations error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const AppHeader(
              title: 'History',
              type: AppHeaderType.primary,
              showAvatar: false,
              showLeading: false,
            ),

            // Month Selector - Centered
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(child: _buildMonthSelector()),
            ),

            // Scrollable Content
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.only(
                        left: 20,
                        right: 20,
                        bottom: 120,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Monthly Summary
                          _buildMonthlySummary(),
                          const SizedBox(height: 24),

                          // Daily Logs Header
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Daily Logs',
                                  style: AppTypography.h3.copyWith(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox.shrink(),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Daily Log Cards
                          if (_dailySummaries.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 32),
                              child: Center(
                                child: Text(
                                  'No activity this month',
                                  style: AppTypography.bodyMedium.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            )
                          else
                            ...List.generate(_dailySummaries.length, (index) {
                              return _buildDayCard(_dailySummaries[index], index);
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

  Widget _buildMonthSelector() {
    return GestureDetector(
      onTap: _showMonthPicker,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.glassPrimary,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.glassBorder),
              boxShadow: AppShadows.glass,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Iconsax.calendar_1,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 10),
                Text(
                  _selectedMonthLabel,
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Iconsax.arrow_down_1,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showMonthPicker() {
    // Build last 6 months
    final now = DateTime.now();
    final months = <Map<String, int>>[];
    for (int i = 0; i < 6; i++) {
      final d = DateTime(now.year, now.month - i, 1);
      months.add({'year': d.year, 'month': d.month});
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.gradientStart.withValues(alpha: 0.7),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppColors.glassNav,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Select Month',
              style: AppTypography.h3.copyWith(color: AppColors.textPrimary),
            ),
            const SizedBox(height: 16),
            ...months.map((m) {
              final label =
                  '${_monthNames[m['month']! - 1]} ${m['year']}';
              final isSelected =
                  m['year'] == _selectedYear && m['month'] == _selectedMonth;
              return ListTile(
                title: Text(
                  label,
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                trailing: isSelected
                    ? Icon(Iconsax.check, color: AppColors.primary)
                    : null,
                onTap: () {
                  setState(() {
                    _selectedYear = m['year']!;
                    _selectedMonth = m['month']!;
                  });
                  Navigator.pop(context);
                  _loadData();
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthlySummary() {
    final distance = (_monthSummary['totalDistance'] as num?)?.toDouble() ?? 0.0;
    final hours = _monthSummary['hours'] ?? 0;
    final minutes = _monthSummary['minutes'] ?? 0;
    final activeDays = _monthSummary['activeDays'] ?? 0;

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
            boxShadow: AppShadows.glass,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(Iconsax.chart, size: 22, color: AppColors.primary),
                  const SizedBox(width: 10),
                  Text(
                    'Monthly Summary',
                    style: AppTypography.headline.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Stats Grid - 3 items
              Row(
                children: [
                  _buildStatCard(
                    icon: Iconsax.location,
                    iconBgColor: AppColors.success.withValues(alpha: 0.2),
                    iconColor: AppColors.success,
                    label: 'Distance',
                    value: distance.toStringAsFixed(1),
                    unit: 'km',
                  ),
                  const SizedBox(width: 12),
                  _buildStatCard(
                    icon: Iconsax.timer_1,
                    iconBgColor: AppColors.warning.withValues(alpha: 0.2),
                    iconColor: AppColors.warning,
                    label: 'Time',
                    value: '${hours}h ${minutes}m',
                    unit: null,
                  ),
                  const SizedBox(width: 12),
                  _buildStatCard(
                    icon: Iconsax.calendar_tick,
                    iconBgColor: AppColors.primary.withValues(alpha: 0.2),
                    iconColor: AppColors.primary,
                    label: 'Active',
                    value: '$activeDays',
                    unit: 'days',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required Color iconBgColor,
    required Color iconColor,
    required String label,
    required String value,
    String? unit,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.glassPrimary,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconBgColor,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, size: 20, color: iconColor),
            ),
            const SizedBox(height: 8),
            Text(
              label.toUpperCase(),
              style: AppTypography.overline.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.bold,
                fontSize: 10,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 4),
            RichText(
              text: TextSpan(
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
                children: [
                  TextSpan(text: value),
                  if (unit != null)
                    TextSpan(
                      text: ' $unit',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.normal,
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

  Widget _buildDayCard(DailySummaryModel summary, int index) {
    final isExpanded = _expandedDay == index;
    final isToday = summary.isToday;
    final isOffDuty = summary.isOffDuty;
    final dayNum = summary.date.day.toString().padLeft(2, '0');
    final locations = _locationCache[index] ?? [];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            decoration: BoxDecoration(
              color: isToday
                  ? AppColors.glassStrong
                  : AppColors.glassPrimary,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isToday
                    ? AppColors.primary.withValues(alpha: 0.5)
                    : AppColors.glassBorder,
              ),
            ),
            child: Column(
              children: [
                // Card Header
                GestureDetector(
                  onTap: isOffDuty
                      ? null
                      : () {
                          setState(
                            () => _expandedDay = isExpanded ? null : index,
                          );
                          if (!isExpanded) {
                            _loadLocationsForDay(index);
                          }
                        },
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: EdgeInsets.all(isExpanded ? 20 : 16),
                    child: Row(
                      children: [
                        // Day Number Box
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: isToday
                                ? AppColors.primary.withValues(alpha: 0.1)
                                : AppColors.glassStrong,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: AppColors.glassBorder,
                            ),
                          ),
                          child: Center(
                            child: isToday
                                ? Icon(
                                    Iconsax.calendar,
                                    size: 24,
                                    color: AppColors.primary,
                                  )
                                : Text(
                                    dayNum,
                                    style: AppTypography.h3.copyWith(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 16),

                        // Day Info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isToday
                                    ? '$dayNum ${_monthNames[summary.date.month - 1].substring(0, 3)}'
                                    : summary.dayName,
                                style: AppTypography.bodyMedium.copyWith(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: isToday ? 18 : 14,
                                ),
                              ),
                              const SizedBox(height: 2),
                              if (isToday)
                                Text(
                                  'Today • Active',
                                  style: AppTypography.caption.copyWith(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.5,
                                  ),
                                )
                              else if (isOffDuty)
                                Text(
                                  'Off Duty',
                                  style: AppTypography.caption.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                )
                              else
                                Row(
                                  children: [
                                    Icon(
                                      Iconsax.timer_1,
                                      size: 14,
                                      color: AppColors.textSecondary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      summary.formattedDuration,
                                      style: AppTypography.caption.copyWith(
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Icon(
                                      Iconsax.location,
                                      size: 14,
                                      color: AppColors.textSecondary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${summary.totalDistance.toStringAsFixed(1)}km',
                                      style: AppTypography.caption.copyWith(
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),

                        // Expand/Collapse Icon
                        if (!isOffDuty)
                          AnimatedRotation(
                            duration: const Duration(milliseconds: 200),
                            turns: isExpanded ? 0.5 : 0,
                            child: Icon(
                              Iconsax.arrow_down_1,
                              color: AppColors.textSecondary,
                              size: 24,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                // Expanded Timeline
                if (isExpanded && !isOffDuty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(
                            color: AppColors.glassBorder,
                            width: 2,
                          ),
                        ),
                      ),
                      margin: const EdgeInsets.only(left: 22),
                      padding: const EdgeInsets.only(left: 28),
                      child: locations.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Text(
                                'Loading timeline...',
                                style: AppTypography.caption.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            )
                          : Column(
                              children: locations.map((loc) {
                                String type;
                                if (loc.isCheckIn) {
                                  type = 'start';
                                } else if (loc.isCheckOut) {
                                  type = 'end';
                                } else {
                                  type = 'visit';
                                }
                                return _buildTimelineItem(
                                  time: loc.formattedTime,
                                  title: loc.title.isNotEmpty
                                      ? loc.title
                                      : loc.address,
                                  subtitle: loc.address,
                                  type: type,
                                );
                              }).toList(),
                            ),
                    ),
                  ),
                  const SizedBox.shrink(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTimelineItem({
    required String time,
    required String title,
    required String subtitle,
    required String type,
  }) {
    Color dotColor;
    switch (type) {
      case 'start':
        dotColor = AppColors.success;
        break;
      case 'end':
        dotColor = AppColors.critical;
        break;
      default:
        dotColor = AppColors.primary;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Dot
          Positioned(
            left: -39,
            top: 4,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.glassBorder, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: dotColor.withValues(alpha: 0.3),
                    blurRadius: 4,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),

          // Content
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.glassPrimary,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.glassPrimary),
                ),
                child: Text(
                  time,
                  style: AppTypography.overline.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
