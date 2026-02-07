import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';
import '../../widgets/glass/gradient_background.dart';
import '../../widgets/inputs/text_input_field.dart';
import '../../widgets/navigation/app_header.dart';

/// End of Day Summary Screen - Full Screen Design
/// Shown when employee ends work session
class EndOfDayScreen extends StatefulWidget {
  final Duration sessionDuration;
  final double distance;
  final List<String> locations;
  final int photosCount;
  final int tasksCompleted;
  final VoidCallback? onConfirm;

  const EndOfDayScreen({
    super.key,
    required this.sessionDuration,
    required this.distance,
    required this.locations,
    required this.photosCount,
    required this.tasksCompleted,
    this.onConfirm,
  });

  @override
  State<EndOfDayScreen> createState() => _EndOfDayScreenState();
}

class _EndOfDayScreenState extends State<EndOfDayScreen> {
  final _notesController = TextEditingController();

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
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
                                      icon: Iconsax.timer_1,
                                      label: 'Total Time',
                                      value: _formatDuration(
                                        widget.sessionDuration,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _buildStatCard(
                                      icon: Iconsax.location,
                                      label: 'Total Distance',
                                      value:
                                          '${widget.distance.toStringAsFixed(1)} km',
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildStatCard(
                                      icon: Iconsax.building,
                                      label: 'Landmarks',
                                      value: '${widget.locations.length}',
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _buildStatCard(
                                      icon: Iconsax.camera,
                                      label: 'Photos',
                                      value: '${widget.photosCount}',
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),

                              // Notes Section
                              Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: Text(
                                  'NOTES',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              GlassInputField(
                                controller: _notesController,
                                hint: 'Add summary notes...',
                                maxLines: 5,
                                contentPadding: const EdgeInsets.all(16),
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
                                onTap: widget.onConfirm,
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
                                    child: Text(
                                      'Confirm & End Session',
                                      style: AppTypography.bodyMedium.copyWith(
                                        color: AppColors.textPrimary,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              GestureDetector(
                                onTap: () => Navigator.pop(context),
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

