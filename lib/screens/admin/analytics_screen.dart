import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_shadows.dart';
import '../../core/constants/app_typography.dart';
import '../../widgets/glass/gradient_background.dart';
import '../../widgets/navigation/app_header.dart';

/// Analytics Screen - Glassmorphism Design
/// Enterprise activity overview
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  String _selectedPeriod = 'This Week';
  final Set<int> _expandedEmployees = {};

  final List<String> _periods = ['Today', 'This Week', 'This Month', 'Custom'];
  final List<Map<String, dynamic>> _employees = [
    {
      'name': 'Rahul Kumar',
      'hours': 32,
      'distance': 45.2,
      'photos': 28,
      'isTop': true,
      'logs': [
        {
          'title': 'Location Update',
          'time': '2 min ago',
          'detail': 'Checked in at Sector 45, Gurgaon',
        },
        {
          'title': 'Task Started',
          'time': '15 min ago',
          'detail': 'Inventory Check - Warehouse A',
        },
      ],
    },
    {
      'name': 'Priya Singh',
      'hours': 38,
      'distance': 52.1,
      'photos': 34,
      'isTop': false,
      'logs': [
        {
          'title': 'Photo Captured',
          'time': '45 min ago',
          'detail': 'Site Frontage - Evidence uploaded',
        },
      ],
    },
    {
      'name': 'Amit Sharma',
      'hours': 35,
      'distance': 48.5,
      'photos': 31,
      'isTop': false,
      'logs': [
        {
          'title': 'Commute Started',
          'time': '1h ago',
          'detail': 'Traveling to Sector 45',
        },
      ],
    },
    {
      'name': 'Neha Verma',
      'hours': 28,
      'distance': 41.3,
      'photos': 25,
      'isTop': false,
      'logs': [
        {
          'title': 'Task Completed',
          'time': '2h ago',
          'detail': 'Store Audit - West Region',
        },
      ],
    },
    {
      'name': 'Suresh Patel',
      'hours': 23,
      'distance': 38.0,
      'photos': 18,
      'isTop': false,
      'logs': [
        {
          'title': 'Break',
          'time': '3h ago',
          'detail': 'Paused for lunch',
        },
      ],
    },
  ];

  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AppHeader(
              title: 'Analytics',
              type: AppHeaderType.primary,
              showAvatar: false,
              actions: [_buildPeriodSelector()],
            ),
            const SizedBox(height: 16),

            // Summary Stats
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _buildSummaryCard(),
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
                  boxShadow: AppShadows.glass, // Soft glass shadow
                ),
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(32),
                  ),
                  child: SingleChildScrollView(
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
                              'Employee Breakdown',
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

                        // Employee Performance Cards (expandable logs)
                        ..._employees.asMap().entries.map((entry) {
                          final index = entry.key;
                          final emp = entry.value;
                          final isExpanded = _expandedEmployees.contains(index);
                          return _buildEmployeeCard(
                            name: emp['name'],
                            hours: emp['hours'],
                            distance: emp['distance'],
                            photos: emp['photos'],
                            isTop: emp['isTop'] == true,
                            logs: List<Map<String, String>>.from(emp['logs']),
                            isExpanded: isExpanded,
                            onToggle: () {
                              setState(() {
                                if (isExpanded) {
                                  _expandedEmployees.remove(index);
                                } else {
                                  _expandedEmployees.add(index);
                                }
                              });
                            },
                          );
                        }),

                        const SizedBox(height: 24),

                        // Export Button
                        GestureDetector(
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text(
                                  'Export feature coming soon!',
                                ),
                                backgroundColor: AppColors.primary,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: AppColors.primary.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Iconsax.export,
                                  size: 20,
                                  color: AppColors.primary,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'Export Report',
                                  style: AppTypography.bodyMedium.copyWith(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
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

  Widget _buildPeriodSelector() {
    return GestureDetector(
      onTap: () => _showPeriodPicker(),
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
              _selectedPeriod,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textOnGradient,
                fontWeight: FontWeight.w600,
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down,
              size: 18,
              color: AppColors.textPrimary,
            ),
          ],
        ),
      ),
    );
  }

  void _showPeriodPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surface, // glassStrong
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
                trailing: _selectedPeriod == period
                    ? Icon(Icons.check, color: AppColors.primary)
                    : null,
                onTap: () {
                  setState(() => _selectedPeriod = period);
                  Navigator.pop(context);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
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
                    value: '5',
                    label: 'Active',
                    color: AppColors.iconBlue,
                  ),
                  _buildSummaryItem(
                    icon: Iconsax.timer_1,
                    value: '156h',
                    label: 'Hours',
                    color: AppColors.iconOrange,
                  ),
                  _buildSummaryItem(
                    icon: Iconsax.routing_2,
                    value: '234',
                    label: 'km',
                    color: AppColors.iconTeal,
                  ),
                  _buildSummaryItem(
                    icon: Iconsax.gallery,
                    value: '156',
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
    required List<Map<String, String>> logs,
    required bool isExpanded,
    required VoidCallback onToggle,
    bool isTop = false,
  }) {
    final initials = name.split(' ').take(2).map((e) => e[0]).join('');

    return GestureDetector(
      onTap: onToggle,
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
        child: Column(
          children: [
            Row(
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
                        color: isTop
                            ? AppColors.primary
                            : AppColors.textSecondary,
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
            if (isExpanded) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.glassStrong,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.glassBorder),
                ),
                child: Column(
                  children: logs
                      .map(
                        (log) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                margin: const EdgeInsets.only(top: 6),
                                decoration: const BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          log['title'] ?? '',
                                          style: AppTypography.bodySmall
                                              .copyWith(
                                            color: AppColors.textPrimary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Text(
                                          log['time'] ?? '',
                                          style: AppTypography.caption.copyWith(
                                            color: AppColors.textTertiary,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      log['detail'] ?? '',
                                      style: AppTypography.caption.copyWith(
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
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

