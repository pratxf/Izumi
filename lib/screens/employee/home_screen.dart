import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';
import '../../widgets/glass/gradient_background.dart';
import '../../widgets/navigation/app_header.dart';
import 'end_of_day_screen.dart';

/// Employee Home Screen - Glassmorphism Design
/// Shows IDLE or ACTIVE state based on session status
class HomeScreen extends StatefulWidget {
  final bool isTeamLead;
  final VoidCallback? onAvatarTap;

  const HomeScreen({super.key, this.isTeamLead = false, this.onAvatarTap});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isSessionActive = false;
  DateTime? _sessionStartTime;
  Timer? _timer;
  Duration _sessionDuration = Duration.zero;
  double _distance = 0.0;

  final String _currentLocation = 'Hitech City, Hyderabad';

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startSession() {
    setState(() {
      _isSessionActive = true;
      _sessionStartTime = DateTime.now();
      _sessionDuration = Duration.zero;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_sessionStartTime != null) {
        setState(() {
          _sessionDuration = DateTime.now().difference(_sessionStartTime!);
          _distance = (_sessionDuration.inSeconds / 60) * 0.1;
        });
      }
    });
  }

  void _endSession() {
    _timer?.cancel();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EndOfDayScreen(
          sessionDuration: _sessionDuration,
          distance: _distance,
          locations: ['Rajendra Nagar', 'Gandhi Maidan', 'Patna Station'],
          photosCount: 5,
          tasksCompleted: 2,
          onConfirm: () {
            Navigator.pop(context);
            setState(() {
              _isSessionActive = false;
              _sessionStartTime = null;
              _sessionDuration = Duration.zero;
              _distance = 0.0;
            });
          },
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  String _formatElapsed(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
  }

  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AppHeader(
              title: 'Izumi',
              showNotification: _isSessionActive,
              onAvatarTap: widget.onAvatarTap,
            ),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 120),
                child: Column(
                  children: [
                    // Status Badge
                    _buildStatusBadge(),
                    const SizedBox(height: 20),

                    // Session Card
                    _buildSessionCard(),
                    const SizedBox(height: 16),

                    // Stats Grid
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatCard(
                            icon: Iconsax.location,
                            iconColor: AppColors.success,
                            label: 'Distance',
                            value: _distance.toStringAsFixed(1),
                            unit: 'km',
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildStatCard(
                            icon: Iconsax.timer_1,
                            iconColor: AppColors.warning,
                            label: 'Elapsed',
                            value: _isSessionActive
                                ? _formatElapsed(_sessionDuration)
                                : '0h 00m',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Location Card
                    _buildLocationCard(),
                    const SizedBox(height: 16),

                    // Active Tasks Card
                    _buildTasksCard(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: _isSessionActive
            ? AppColors.primary.withValues(alpha: 0.9)
            : AppColors.glassPrimary,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppColors.glassBorder,
        ),
        boxShadow: _isSessionActive
            ? [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  blurRadius: 12,
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _isSessionActive
                  ? AppColors.textPrimary
                  : AppColors.textDisabled,
              shape: BoxShape.circle,
              boxShadow: _isSessionActive
                  ? [
                      BoxShadow(
                        color: AppColors.textPrimary.withValues(alpha: 0.6),
                        blurRadius: 8,
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: AppColors.textDisabled.withValues(alpha: 0.6),
                        blurRadius: 8,
                      ),
                    ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _isSessionActive ? 'SESSION ACTIVE' : 'SESSION IDLE',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(40),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: AppColors.glassPrimary,
            borderRadius: BorderRadius.circular(40),
            border: Border.all(color: AppColors.glassBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 20,
              ),
            ],
          ),
          child: Stack(
            children: [
              // Decorative blurs
              Positioned(
                top: -40,
                left: -40,
                child: Container(
                  width: 128,
                  height: 128,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              if (_isSessionActive)
                Positioned(
                  bottom: -40,
                  right: -40,
                  child: Container(
                    width: 128,
                    height: 128,
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              // Content
              Column(
                children: [
                  Text(
                    'DURATION',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _formatDuration(_sessionDuration),
                    style: AppTypography.displayLarge.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: _isSessionActive ? 52 : 44,
                      letterSpacing: -2,
                    ),
                  ),
                  const SizedBox(height: 24),
                  GestureDetector(
                    onTap: _isSessionActive ? _endSession : _startSession,
                    child: Container(
                      width: double.infinity,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.3),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _isSessionActive
                                ? Iconsax.stop_circle
                                : Iconsax.play,
                            color: AppColors.textPrimary,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _isSessionActive ? 'END SESSION' : 'START SESSION',
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
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

  Widget _buildStatCard({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    String? unit,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          height: 128,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.glassPrimary,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.glassPrimary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label.toUpperCase(),
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: value,
                          style: AppTypography.h3.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (unit != null)
                          TextSpan(
                            text: ' $unit',
                            style: AppTypography.caption.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                      ],
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

  Widget _buildLocationCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.glassPrimary,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.primary, AppColors.primaryLight],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.4),
                      blurRadius: 12,
                    ),
                  ],
                ),
                child: const Icon(
                  Iconsax.map,
                  color: AppColors.textPrimary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _currentLocation,
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          Iconsax.gps,
                          size: 12,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Updated: Just now',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.glassPrimary,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Iconsax.refresh,
                  color: AppColors.textPrimary,
                  size: 18,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTasksCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.glassPrimary,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Column(
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: 'Active Tasks ',
                          style: AppTypography.bodyMedium.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextSpan(
                          text: '(2)',
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Task Items
              _buildTaskItem(
                title: 'Visit ABC Dist. (Due)',
                subtitle: 'High Priority • 2km away',
                priorityColor: AppColors.critical,
                isHighPriority: true,
              ),
              const SizedBox(height: 10),
              _buildTaskItem(
                title: 'Follow up XYZ Farmer',
                subtitle: 'Medium Priority • Call pending',
                priorityColor: AppColors.warning,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTaskItem({
    required String title,
    required String subtitle,
    required Color priorityColor,
    bool isHighPriority = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.glassPrimary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: priorityColor,
              shape: BoxShape.circle,
              boxShadow: isHighPriority
                  ? [
                      BoxShadow(
                        color: priorityColor.withValues(alpha: 0.6),
                        blurRadius: 8,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle.toUpperCase(),
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right,
            color: AppColors.textTertiary,
            size: 16,
          ),
        ],
      ),
    );
  }
}

