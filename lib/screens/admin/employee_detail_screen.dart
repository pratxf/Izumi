import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_shadows.dart';
import '../../core/constants/app_typography.dart';
import '../../models/activity_log_model.dart';
import '../../providers/dashboard_provider.dart';
import '../../repositories/activity_log_repository.dart';
import '../../widgets/glass/gradient_background.dart';
import '../../widgets/navigation/app_header.dart';

/// Employee Detail Screen
/// Shows real-time employee stats and activity feed
class EmployeeDetailScreen extends StatefulWidget {
  final String name;
  final bool isActive;
  final String avatarUrl;

  const EmployeeDetailScreen({
    super.key,
    required this.name,
    required this.isActive,
    this.avatarUrl = 'https://i.pravatar.cc/150?img=11',
  });

  @override
  State<EmployeeDetailScreen> createState() => _EmployeeDetailScreenState();
}

class _EmployeeDetailScreenState extends State<EmployeeDetailScreen> {
  final ActivityLogRepository _logRepo = ActivityLogRepository();
  List<ActivityLogModel> _activityLogs = [];
  StreamSubscription? _logSubscription;
  String? _employeeId;

  @override
  void initState() {
    super.initState();
    // Extract employee ID from the route
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final id = GoRouterState.of(context).pathParameters['id'];
      if (id != null) {
        _employeeId = id;
        _streamActivityLogs(id);
      }
    });
  }

  void _streamActivityLogs(String employeeId) {
    _logSubscription?.cancel();
    _logSubscription =
        _logRepo.streamLogsByEmployee(employeeId).listen((logs) {
      if (mounted) {
        setState(() => _activityLogs = logs);
      }
    });
  }

  @override
  void dispose() {
    _logSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dashboardProvider = context.watch<DashboardProvider>();
    final stats = _employeeId != null
        ? dashboardProvider.getEmployeeStats(_employeeId!)
        : null;
    // Format session time from stats
    final sessionSeconds = stats?['sessionDuration'] as int? ?? 0;
    final hours = (sessionSeconds ~/ 3600).toString().padLeft(2, '0');
    final minutes = ((sessionSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final seconds = (sessionSeconds % 60).toString().padLeft(2, '0');
    final sessionTimeDisplay = '$hours:$minutes:$seconds';

    // Format distance
    final distanceKm = (stats?['distance'] as num?)?.toDouble() ?? 0.0;
    final distanceDisplay = '${distanceKm.toStringAsFixed(1)} km';

    return Scaffold(
      body: GradientBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              AppHeader(
                title: "${widget.name}'s History",
                type: AppHeaderType.secondary,
                showAvatar: false,
              ),

              // Scrollable Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 120),
                  child: Column(
                    children: [
                      // Stats Row
                      _buildStatsRow(sessionTimeDisplay, distanceDisplay),
                      const SizedBox(height: 32),

                      // Action Buttons (Horizontal Scroll)
                      _buildActionButtons(context),
                      const SizedBox(height: 32),

                      // Live Activity Feed Title
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Live Activity Feed',
                          style: AppTypography.h3.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Activity Feed
                      _buildActivityFeed(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsRow(String sessionTime, String distance) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.glassPrimary,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.glassBorder),
            boxShadow: AppShadows.glass,
          ),
          child: IntrinsicHeight(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Session Time
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SESSION TIME',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary.withValues(alpha: 0.7),
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      sessionTime,
                      style: AppTypography.h2.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                // Divider
                Container(width: 1, color: AppColors.glassBorder),
                // Total Distance
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'TOTAL DISTANCE',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary.withValues(alpha: 0.7),
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      distance,
                      style: AppTypography.h2.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
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

  Widget _buildActionButtons(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildActionButton(
            Iconsax.task_square,
            'Assign Task',
            () => context.push('/admin/create-task'),
          ),
          const SizedBox(width: 12),
          _buildActionButton(Iconsax.gallery, 'View Photos', () {
            // Navigate to admin images screen (filtered by employee)
            context.push('/admin/images');
          }),
          const SizedBox(width: 12),
          _buildActionButton(
            Iconsax.map,
            'View Route',
            () {}, // Route view not yet implemented
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.glassPrimary,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.glassBorder),
              boxShadow: AppShadows.glass,
            ),
            child: Row(
              children: [
                Icon(icon, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActivityFeed() {
    if (_activityLogs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 32),
          child: Column(
            children: [
              Icon(
                Iconsax.activity,
                size: 48,
                color: AppColors.textTertiary,
              ),
              const SizedBox(height: 16),
              Text(
                'No activity yet',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: List.generate(_activityLogs.length, (index) {
        final log = _activityLogs[index];
        final isLast = index == _activityLogs.length - 1;

        // Map log type to icon
        IconData icon;
        switch (log.type) {
          case 'location_update':
            icon = Iconsax.location;
            break;
          case 'task_started':
          case 'task_completed':
            icon = Iconsax.box;
            break;
          case 'photo_captured':
            icon = Iconsax.camera;
            break;
          case 'session_started':
          case 'session_ended':
            icon = Iconsax.timer_start;
            break;
          case 'break':
            icon = Iconsax.coffee;
            break;
          default:
            icon = Iconsax.activity;
        }

        return _buildTimelineItem(
          icon: icon,
          title: log.title,
          time: log.timeAgo.toUpperCase(),
          description: log.detail,
          isLast: isLast,
          isOpacity: isLast,
        );
      }),
    );
  }

  Widget _buildTimelineItem({
    required IconData icon,
    required String title,
    required String time,
    required String description,
    required bool isLast,
    bool isOpacity = false,
  }) {
    return Opacity(
      opacity: isOpacity ? 0.8 : 1.0,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Timeline Line & Icon Placeholder space
            SizedBox(
              width: 24,
              child: Stack(
                alignment: Alignment.topCenter,
                children: [
                  if (!isLast)
                    Positioned(
                      top: 40,
                      bottom: 0,
                      child: Container(
                        width: 2,
                        color: AppColors.glassBorder,
                      ),
                    ),
                ],
              ),
            ),
            // Card Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.glassPrimary,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: AppColors.glassBorder),
                        boxShadow: AppShadows.glass,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(
                              icon,
                              color: AppColors.primary,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      title,
                                      style: AppTypography.bodyMedium.copyWith(
                                        color: AppColors.textPrimary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      time,
                                      style: AppTypography.caption.copyWith(
                                        color: AppColors.textSecondary
                                            .withValues(alpha: 0.6),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  description,
                                  style: AppTypography.bodySmall.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
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
}
