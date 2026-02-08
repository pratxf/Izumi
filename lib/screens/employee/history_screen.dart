import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_shadows.dart';
import '../../core/constants/app_typography.dart';
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
  String _selectedMonth = 'February 2026';
  int? _expandedDay;

  final List<String> _months = [
    'February 2026',
    'January 2026',
    'December 2025',
  ];

  // Mock data - Monthly summary
  final Map<String, dynamic> _monthSummary = {
    'distance': 245.8,
    'hours': 98,
    'minutes': 30,
    'activeDays': 18,
  };

  // Mock data - Daily logs
  final List<Map<String, dynamic>> _dailyLogs = [
    {
      'day': '04',
      'dayName': 'Today',
      'isToday': true,
      'isActive': true,
      'duration': null,
      'distance': null,
      'locations': [
        {
          'time': '09:30',
          'title': 'Session Started',
          'subtitle': 'Automated check-in',
          'type': 'start',
        },
        {
          'time': '11:00',
          'title': 'Rajendra Nagar',
          'subtitle': 'Client Visit: Site 4B',
          'type': 'visit',
        },
        {
          'time': '13:30',
          'title': 'MG Road',
          'subtitle': 'Delivery Drop-off',
          'type': 'visit',
        },
      ],
    },
    {
      'day': '03',
      'dayName': 'Monday',
      'isToday': false,
      'isActive': false,
      'duration': '8h 15m',
      'distance': '12km',
      'locations': [
        {
          'time': '09:00',
          'title': 'Session Started',
          'subtitle': 'Automated check-in',
          'type': 'start',
        },
        {
          'time': '10:30',
          'title': 'Kankarbagh',
          'subtitle': 'Site Inspection',
          'type': 'visit',
        },
        {
          'time': '17:15',
          'title': 'Session Ended',
          'subtitle': 'Day complete',
          'type': 'end',
        },
      ],
    },
    {
      'day': '02',
      'dayName': 'Sunday',
      'isToday': false,
      'isActive': false,
      'duration': null,
      'distance': null,
      'isOffDuty': true,
      'locations': [],
    },
    {
      'day': '01',
      'dayName': 'Saturday',
      'isToday': false,
      'isActive': false,
      'duration': '6h 30m',
      'distance': '9km',
      'locations': [
        {
          'time': '09:30',
          'title': 'Session Started',
          'subtitle': 'Automated check-in',
          'type': 'start',
        },
        {
          'time': '16:00',
          'title': 'Session Ended',
          'subtitle': 'Day complete',
          'type': 'end',
        },
      ],
    },
  ];

  @override
  void initState() {
    super.initState();
    // Auto-expand today's card
    _expandedDay = 0;
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
              child: SingleChildScrollView(
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
                    ...List.generate(_dailyLogs.length, (index) {
                      return _buildDayCard(_dailyLogs[index], index);
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

  Widget _buildGlassButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.glassPrimary,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Icon(icon, color: AppColors.textPrimary, size: 20),
          ),
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
                  _selectedMonth,
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.keyboard_arrow_down,
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
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppColors.glassStrong,
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
            ..._months.map(
              (month) => ListTile(
                title: Text(
                  month,
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                trailing: _selectedMonth == month
                    ? Icon(Icons.check, color: AppColors.primary)
                    : null,
                onTap: () {
                  setState(() => _selectedMonth = month);
                  Navigator.pop(context);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthlySummary() {
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
                    value: '${_monthSummary['distance']}',
                    unit: 'km',
                  ),
                  const SizedBox(width: 12),
                  _buildStatCard(
                    icon: Iconsax.timer_1,
                    iconBgColor: AppColors.warning.withValues(alpha: 0.2),
                    iconColor: AppColors.warning,
                    label: 'Time',
                    value:
                        '${_monthSummary['hours']}h ${_monthSummary['minutes']}m',
                    unit: null,
                  ),
                  const SizedBox(width: 12),
                  _buildStatCard(
                    icon: Iconsax.calendar_tick,
                    iconBgColor: AppColors.primary.withValues(alpha: 0.2),
                    iconColor: AppColors.primary,
                    label: 'Active',
                    value: '${_monthSummary['activeDays']}',
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

  Widget _buildDayCard(Map<String, dynamic> day, int index) {
    final isExpanded = _expandedDay == index;
    final isToday = day['isToday'] ?? false;
    final isOffDuty = day['isOffDuty'] ?? false;

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
                      : () => setState(
                          () => _expandedDay = isExpanded ? null : index,
                        ),
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
                                    day['day'],
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
                                isToday ? '${day['day']} Feb' : day['dayName'],
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
                                      day['duration'] ?? '',
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
                                      day['distance'] ?? '',
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
                              Icons.keyboard_arrow_down,
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
                  // Timeline Content
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
                      child: Column(
                        children: List.generate(
                          (day['locations'] as List).length,
                          (locIndex) {
                            final loc = (day['locations'] as List)[locIndex];
                            return _buildTimelineItem(
                              time: loc['time'],
                              title: loc['title'],
                              subtitle: loc['subtitle'],
                              type: loc['type'],
                            );
                          },
                        ),
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

