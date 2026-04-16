import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:izumi/core/ui/app_icons.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';
import '../../providers/auth_provider.dart';
import '../../providers/session_provider.dart';
import '../../widgets/glass/gradient_background.dart';
import '../../widgets/navigation/app_header.dart';

/// End of Day Summary Screen - Full Screen Design
/// Shown when employee ends work session
class EndOfDayScreen extends StatefulWidget {
  final Duration sessionDuration;
  final double distance;
  final List<String> locations;
  final int photosCount;
  final int tasksCompleted;

  const EndOfDayScreen({
    super.key,
    required this.sessionDuration,
    required this.distance,
    required this.locations,
    required this.photosCount,
    required this.tasksCompleted,
  });

  @override
  State<EndOfDayScreen> createState() => _EndOfDayScreenState();
}

class _EndOfDayScreenState extends State<EndOfDayScreen> {
  bool _isEnding = false;

  /// Defensive conversion for legacy sessions that stored meters in a field
  /// labeled km. Mirrors the helper used in AnalyticsProvider /
  /// DashboardProvider so the end-of-day summary never shows a wildly
  /// inflated number when the client accumulator is off.
  static double _sanitizeDistance(double rawKm) {
    if (rawKm > 500) return rawKm / 1000.0;
    return rawKm;
  }

  Future<void> _confirmEndSession() async {
    setState(() => _isEnding = true);

    final authProvider = context.read<AuthProvider>();
    final sessionProvider = context.read<SessionProvider>();
    final userId = authProvider.currentUser?.id ?? '';
    final enterpriseId = authProvider.enterpriseId ?? '';

    final result = await sessionProvider.endSession(
      enterpriseId: enterpriseId,
      employeeId: userId,
    );

    if (!mounted) return;

    if (result != null) {
      // Show local notification with session summary
      final duration = result['sessionDuration'] as Duration;
      final dist = _sanitizeDistance(result['distance'] as double);
      final hours = duration.inHours;
      final minutes = duration.inMinutes % 60;
      final durationText = hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';

      authProvider.notificationService.showLocal(
        title: 'Session Ended',
        body: 'Total distance: ${dist.toStringAsFixed(1)} km | Duration: $durationText',
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Session ended successfully'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      context.go('/employee/home');
    } else {
      setState(() => _isEnding = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(sessionProvider.error ?? 'Failed to end session'),
          backgroundColor: AppColors.critical,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GradientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const AppHeader(
                  title: 'End of Day',
                  type: AppHeaderType.secondary,
                  showAvatar: false,
                ),
                const SizedBox(height: 24),
                // Modal Container
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                      child: Container(
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: AppColors.glassPrimary,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: AppColors.glassPrimary),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Title
                              Text(
                                'End Session Summary',
                                style: AppTypography.h2.copyWith(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 24),

                              // Session Overview Label
                              Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: Text(
                                  'SESSION OVERVIEW',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),

                              // Stats Grid
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildStatCard(
                                      icon: AppIcons.timer_1,
                                      label: 'Total Time',
                                      value: _formatDuration(
                                        widget.sessionDuration,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _buildStatCard(
                                      icon: AppIcons.location,
                                      label: 'Total Distance',
                                      value:
                                          '${_sanitizeDistance(widget.distance).toStringAsFixed(1)} km',
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildStatCard(
                                      icon: AppIcons.building,
                                      label: 'Landmarks',
                                      value: '${widget.locations.length}',
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _buildStatCard(
                                      icon: AppIcons.camera,
                                      label: 'Photos',
                                      value: '${widget.photosCount}',
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 32),

                              // Confirmation Text
                              Text(
                                'Are you sure you want to end your work session?',
                                style: AppTypography.bodySmall.copyWith(
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 24),

                              // Buttons
                              GestureDetector(
                                onTap: _isEnding ? null : _confirmEndSession,
                                child: Container(
                                  height: 56,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary,
                                    borderRadius: BorderRadius.circular(28),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.primary.withValues(
                                          alpha: 0.3,
                                        ),
                                        blurRadius: 16,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: _isEnding
                                        ? const SizedBox(
                                            width: 24,
                                            height: 24,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : Text(
                                            'Confirm & End Session',
                                            style: AppTypography.bodyMedium
                                                .copyWith(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              GestureDetector(
                                onTap: () => context.pop(),
                                child: Container(
                                  height: 56,
                                  decoration: BoxDecoration(
                                    color: AppColors.glassPrimary,
                                    borderRadius: BorderRadius.circular(28),
                                    border: Border.all(
                                      color: AppColors.primary,
                                      width: 2,
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      'Continue Working',
                                      style: AppTypography.bodyMedium.copyWith(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.glassPrimary,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: AppColors.primary, size: 22),
              const SizedBox(height: 8),
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
