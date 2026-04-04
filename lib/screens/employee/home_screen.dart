import 'dart:async';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:izumi/core/ui/app_icons.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';
import '../../providers/auth_provider.dart';
import '../../providers/session_provider.dart';
import '../../providers/task_provider.dart';
import '../../models/task_model.dart';
import '../../widgets/glass/gradient_background.dart';
import '../../widgets/navigation/app_header.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/permission_service.dart';
import '../../services/battery_optimization_service.dart';
import '../../offline_queue/offline_queue_manager.dart';
import '../../services/realtime_db_service.dart';

/// Employee Home Screen - Glassmorphism Design
/// Shows IDLE or ACTIVE state based on session status
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  bool _initialized = false;
  bool _hasUnread = false;
  StreamSubscription? _unreadSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initProviders();
      _listenUnread();
      _cleanupOrphanedSession();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Force-retry any stuck uploads when app comes to foreground
      OfflineQueueManager.instance.retryAllNow();
      _cleanupOrphanedSession();
    }
  }

  Future<void> _cleanupOrphanedSession() async {
    if (!mounted) return;
    try {
      final session = context.read<SessionProvider>();
      // If local session thinks we're active, nothing to clean
      if (session.isSessionActive) return;

      final auth = context.read<AuthProvider>();
      final rtdb = RealtimeDbService();
      final userId = auth.currentUser?.id;
      final enterpriseId = auth.enterpriseId ?? auth.currentUser?.enterpriseId;
      if (userId == null || enterpriseId == null) return;

      // Check Firestore for any orphaned active session
      final snap = await FirebaseFirestore.instance
          .collection('sessions')
          .where('employeeId', isEqualTo: userId)
          .where('status', isEqualTo: 'active')
          .limit(1)
          .get();

      if (!mounted) return;

      if (snap.docs.isEmpty) {
        // No orphaned Firestore session — just clean up RTDB in case
        // activeStats was left behind
        await rtdb.clearActiveStats(enterpriseId: enterpriseId, userId: userId);
        return;
      }

      // Orphaned active session found — end it
      final orphanedDoc = snap.docs.first;
      final startTime = orphanedDoc.data()['startTime'] as Timestamp?;
      final totalDuration = startTime != null
          ? DateTime.now().difference(startTime.toDate()).inSeconds
          : 0;

      await orphanedDoc.reference.update({
        'status': 'auto_ended',
        'endTime': FieldValue.serverTimestamp(),
        'totalDuration': totalDuration,
        'autoEndReason': 'orphaned_on_reopen',
        'autoEndSource': 'home_screen_cleanup',
      });

      // Clean up all RTDB nodes
      await Future.wait([
        rtdb.setOffline(enterpriseId: enterpriseId, userId: userId),
        rtdb.clearActiveStats(enterpriseId: enterpriseId, userId: userId),
        rtdb.clearSessionHeartbeat(enterpriseId: enterpriseId, userId: userId),
        rtdb.clearLiveLocation(enterpriseId: enterpriseId, userId: userId),
      ]);

      debugPrint('[HomeScreen] Cleaned up orphaned session: ${orphanedDoc.id}');
    } catch (e) {
      debugPrint('[HomeScreen] Orphan cleanup failed: $e');
    }
  }

  void _listenUnread() {
    final userId = context.read<AuthProvider>().currentUser?.id;
    if (userId == null) return;
    _unreadSub = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .where('isRead', isEqualTo: false)
        .limit(1)
        .snapshots()
        .listen((snap) {
      if (mounted) setState(() => _hasUnread = snap.docs.isNotEmpty);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _unreadSub?.cancel();
    super.dispose();
  }

  void _initProviders() {
    if (_initialized) return;
    _initialized = true;
    final auth = context.read<AuthProvider>();
    final userId = auth.currentUser?.id ?? '';
    if (userId.isEmpty) return;

    context.read<SessionProvider>().loadActiveSession(userId);
    context.read<TaskProvider>().streamTasks(userId);
  }

  final PermissionService _permissionService = PermissionService();

  void _startSession() async {
    final auth = context.read<AuthProvider>();
    final session = context.read<SessionProvider>();
    final userId = auth.currentUser?.id ?? '';
    final enterpriseId =
        auth.enterpriseId ?? auth.currentUser?.enterpriseId ?? '';
    if (userId.isEmpty || enterpriseId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            auth.errorMessage ??
                'Your account is still syncing. Please try again in a moment.',
          ),
          backgroundColor: AppColors.warning,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Check location permission
    final granted = await _permissionService.ensurePermission(
      context: context,
      permission: Permission.location,
      title: 'Location Access',
      message:
          'Izumi needs your location to track your field session and geotag activities.',
    );
    if (!granted || !mounted) return;

    // Check location services (GPS) are enabled
    final locationOn = await _permissionService.ensureLocationEnabled(context);
    if (!locationOn || !mounted) return;

    final backgroundLocationGranted =
        await _permissionService.ensureBackgroundLocationAccess(
      context: context,
      title: 'Background Location',
      message:
          'Izumi needs background location access to continue employee session tracking while the app is in the background.',
    );
    if (!backgroundLocationGranted || !mounted) return;

    final batteryOptimizationGranted =
        await _permissionService.ensureBatteryOptimizationExemption(
      context: context,
      title: 'Background Tracking',
      message:
          'To keep tracking alive on aggressive Android devices like Samsung and Xiaomi, allow Izumi to ignore battery optimizations on this device.',
    );
    if (!batteryOptimizationGranted || !mounted) return;

    // OEM-specific battery settings (Xiaomi autostart, Huawei protected apps, etc.)
    // Only prompt once — after that, don't block session start.
    final oemPrompted = await BatteryOptimizationService.hasPromptedBefore();
    if (!oemPrompted && mounted) {
      final shouldOpen = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.4),
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.glassStrong,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Text(
            'Keep tracking alive',
            style: AppTypography.h3.copyWith(color: AppColors.textPrimary),
          ),
          content: Text(
            'Some devices stop background apps aggressively. '
            'To prevent your session from stopping when you lock your phone, '
            'please allow Izumi to autostart and run unrestricted.\n\n'
            'On the next screen, look for "Autostart" or "Battery" and enable it for Izumi.',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'Skip',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                'Open Settings',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );
      await BatteryOptimizationService.markAsPrompted();
      if (shouldOpen == true && mounted) {
        await BatteryOptimizationService.openOemBatterySettings();
        // Give user time to return from settings
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      if (!mounted) return;
    }

    await session.startSession(
      employeeId: userId,
      enterpriseId: enterpriseId,
      employeeName: auth.currentUser?.name ?? '',
    );
  }

  void _endSession() {
    final session = context.read<SessionProvider>();
    final taskProvider = context.read<TaskProvider>();

    context.push('/employee/end-of-day', extra: {
      'sessionDuration': session.sessionDuration,
      'distance': session.distance,
      'locations': session.currentLocation.isNotEmpty
          ? [session.currentLocation]
          : <String>[],
      'photosCount': session.activeSession?.photosCount ?? 0,
      'tasksCompleted': taskProvider.completedCount,
    });
  }

  String _formatElapsed(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
  }

  Stream<DateTime> _sessionClock() {
    return Stream<DateTime>.periodic(
      const Duration(seconds: 1),
      (_) => DateTime.now(),
    ).asBroadcastStream();
  }

  Duration _activeDuration(SessionProvider session, DateTime now) {
    final activeSession = session.activeSession;
    if (activeSession == null) {
      return Duration.zero;
    }
    return now.difference(activeSession.startTime);
  }

  Widget _buildLiveDurationText(SessionProvider session, bool isActive) {
    if (!isActive || session.activeSession == null) {
      return Text(
        session.formattedDuration,
        style: AppTypography.displayLarge.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.bold,
          fontSize: 44,
          letterSpacing: -2,
        ),
      );
    }

    return StreamBuilder<DateTime>(
      stream: _sessionClock(),
      initialData: DateTime.now(),
      builder: (context, snapshot) {
        final now = snapshot.data ?? DateTime.now();
        final duration = _activeDuration(session, now);
        final hours = duration.inHours;
        final minutes = duration.inMinutes.remainder(60);
        final seconds = duration.inSeconds.remainder(60);
        final formatted =
            '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

        return Text(
          formatted,
          style: AppTypography.displayLarge.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 52,
            letterSpacing: -2,
          ),
        );
      },
    );
  }

  Widget _buildLiveElapsedValue(SessionProvider session, bool isActive) {
    if (!isActive || session.activeSession == null) {
      return Text(
        '0h 00m',
        style: AppTypography.h3.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.bold,
        ),
      );
    }

    return StreamBuilder<DateTime>(
      stream: _sessionClock(),
      initialData: DateTime.now(),
      builder: (context, snapshot) {
        final now = snapshot.data ?? DateTime.now();
        return Text(
          _formatElapsed(_activeDuration(session, now)),
          style: AppTypography.h3.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final taskProvider = context.watch<TaskProvider>();
    final auth = context.watch<AuthProvider>();
    final isActive = session.isSessionActive;

    return GradientBackground(
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AppHeader(
              title: 'Izumi Biosciences',
              showLeading: false,
              showNotification: true,
              hasUnread: _hasUnread,
              avatarUrl: auth.currentUser?.profileImageUrl,
              onNotificationTap: () {
                context.push('/employee/notifications');
              },
              onAvatarTap: () => context.push('/employee/profile'),
            ),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 120),
                child: Column(
                  children: [
                    // Status Badge
                    _buildStatusBadge(isActive,
                        isLocationLost: session.isLocationLost),
                    const SizedBox(height: 20),

                    // Location Lost Warning Banner
                    if (session.isLocationLost)
                      _buildLocationLostBanner(session),

                    // Session Card
                    _buildSessionCard(session, isActive),
                    const SizedBox(height: 16),

                    // Stats Grid
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatCard(
                            icon: AppIcons.location,
                            iconColor: AppColors.success,
                            label: 'Distance',
                            value: session.distance.toStringAsFixed(1),
                            unit: 'km',
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildStatCard(
                            icon: AppIcons.timer_1,
                            iconColor: AppColors.warning,
                            label: 'Elapsed',
                            valueWidget: _buildLiveElapsedValue(
                              session,
                              isActive,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Location Card
                    _buildLocationCard(session),
                    const SizedBox(height: 16),

                    // Active Tasks Card
                    _buildTasksCard(taskProvider.activeTasks),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(bool isActive, {bool isLocationLost = false}) {
    final Color badgeColor = isLocationLost
        ? AppColors.warning
        : isActive
            ? AppColors.primary
            : AppColors.glassPrimary;
    final String label = isLocationLost
        ? 'LOCATION LOST'
        : isActive
            ? 'SESSION ACTIVE'
            : 'SESSION IDLE';
    final Color dotColor = isLocationLost
        ? AppColors.warning
        : isActive
            ? AppColors.textPrimary
            : AppColors.textDisabled;
    final Color labelColor = isActive ? Colors.white : AppColors.textPrimary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isLocationLost
            ? badgeColor.withValues(alpha: 0.9)
            : isActive
                ? badgeColor.withValues(alpha: 0.9)
                : badgeColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppColors.glassBorder,
        ),
        boxShadow: (isActive || isLocationLost)
            ? [
                BoxShadow(
                  color: badgeColor.withValues(alpha: 0.3),
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
              color: dotColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: dotColor.withValues(alpha: 0.6),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: labelColor,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationLostBanner(SessionProvider session) {
    final remaining = session.gracePeriodRemaining;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.critical.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.critical.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Icon(
            AppIcons.warning_2,
            color: AppColors.critical,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Location Lost',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.critical,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  session.error ?? 'Please re-enable location services',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
                if (remaining != null)
                  Text(
                    'Session ends in ${remaining ~/ 60}m ${(remaining % 60).toString().padLeft(2, '0')}s',
                    style: TextStyle(
                      color: AppColors.warning,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _openLocationSettings(session),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.critical.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Fix',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.critical,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openLocationSettings(SessionProvider session) async {
    final reason = session.locationLostReason;
    if (reason == 'service_disabled') {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
  }

  Widget _buildSessionCard(SessionProvider session, bool isActive) {
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
                  _buildLiveDurationText(session, isActive),
                  const SizedBox(height: 24),
                  GestureDetector(
                    onTap: session.isLoading
                        ? null
                        : (isActive ? _endSession : _startSession),
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
                      child: session.isLoading
                          ? const Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  isActive ? AppIcons.stop_circle : AppIcons.play,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  isActive ? 'END SESSION' : 'START SESSION',
                                  style: const TextStyle(
                                    color: Colors.white,
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
    String? value,
    Widget? valueWidget,
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
                  if (valueWidget != null)
                    valueWidget
                  else
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

  Widget _buildLocationCard(SessionProvider session) {
    final location = session.currentLocation.isNotEmpty
        ? session.currentLocation
        : 'Fetching location...';

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
                  AppIcons.map,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      location,
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          AppIcons.gps,
                          size: 12,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          session.lastLocationUpdateText,
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
              GestureDetector(
                onTap: () {
                  context
                      .read<SessionProvider>()
                      .initializeLocation(force: true);
                },
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.glassPrimary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    AppIcons.refresh,
                    color: AppColors.textPrimary,
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTasksCard(List<TaskModel> tasks) {
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
              GestureDetector(
                onTap: () => context.go('/employee/tasks'),
                child: Row(
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
                            text: '(${tasks.length})',
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      AppIcons.arrow_right_2,
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Task Items
              if (tasks.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'No active tasks',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                )
              else
                ...tasks.take(3).map((task) {
                  Color priorityColor;
                  switch (task.priority) {
                    case 'high':
                      priorityColor = AppColors.critical;
                      break;
                    case 'medium':
                      priorityColor = AppColors.warning;
                      break;
                    default:
                      priorityColor = AppColors.success;
                  }
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _buildTaskItem(
                      title: task.title,
                      subtitle: '${task.priority.toUpperCase()} Priority',
                      priorityColor: priorityColor,
                      isHighPriority: task.isHighPriority,
                    ),
                  );
                }),
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
    return GestureDetector(
      onTap: () => context.go('/employee/tasks'),
      child: Container(
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
              AppIcons.arrow_right_2,
              color: AppColors.textTertiary,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}
