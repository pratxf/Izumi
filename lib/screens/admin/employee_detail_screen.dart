import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:izumi/core/ui/app_icons.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_shadows.dart';
import '../../core/constants/app_typography.dart';
import '../../models/activity_log_model.dart';
import '../../models/photo_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../services/admin_activity_feed_service.dart';
import '../../services/geocoding_cache.dart';
import '../../widgets/glass/gradient_background.dart';
import '../../widgets/navigation/app_header.dart';

/// Employee Detail Screen
/// Shows real-time employee stats and activity feed
class EmployeeDetailScreen extends StatefulWidget {
  final String name;
  final bool isActive;

  const EmployeeDetailScreen({
    super.key,
    required this.name,
    required this.isActive,
  });

  @override
  State<EmployeeDetailScreen> createState() => _EmployeeDetailScreenState();
}

class _EmployeeDetailScreenState extends State<EmployeeDetailScreen>
    with WidgetsBindingObserver {
  static const int _collapsedPhotoCount = 6;
  static const int _photoPreviewLimit = 24;
  static const Duration _activityWindow = Duration(hours: 24);
  final AdminActivityFeedService _feedService = AdminActivityFeedService();
  List<ActivityLogModel> _activityLogs = [];
  List<PhotoModel> _photos = [];
  StreamSubscription<AdminRecentActivityFeedData>? _feedSubscription;
  Timer? _warmupTimer;
  String? _employeeId;
  bool _activityLoading = true;
  bool _photosLoading = true;
  bool _showAllPhotos = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Extract employee ID from the route
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final id = GoRouterState.of(context).pathParameters['id'];
      if (id != null) {
        _employeeId = id;
        // Always ensure DashboardProvider is initialized before loading feed.
        // The feed depends on the employees list for migration ID resolution.
        final dashboard = context.read<DashboardProvider>();
        final enterpriseId =
            context.read<AuthProvider>().enterpriseId ?? '';
        if (enterpriseId.isNotEmpty && dashboard.employees.isEmpty) {
          dashboard.initDashboard(enterpriseId).then((_) {
            if (mounted) _startRecentFeed(id);
          });
        } else {
          _startRecentFeed(id);
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final employeeId = _employeeId;
      if (employeeId != null) {
        _startRecentFeed(employeeId);
      }
    }
  }

  void _startRecentFeed(String employeeId) {
    _feedSubscription?.cancel();
    _warmupTimer?.cancel();
    if (mounted) {
      setState(() {
        _activityLoading = true;
        _photosLoading = true;
      });
    }

    final linkedIds = _feedService.resolveLinkedEmployeeIds(
      employeeId,
      context.read<DashboardProvider>().employees,
    );

    // Allow up to 3 seconds for all inner streams (employee logs, session
    // logs, photos) to deliver their first snapshot. Without this, the first
    // stream to fire (often with empty data) would immediately dismiss the
    // loading state and flash "No activity" before session-based data arrives.
    _warmupTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _activityLoading) {
        setState(() {
          _activityLoading = false;
          _photosLoading = false;
        });
      }
    });

    _feedSubscription = _feedService
        .streamRecentFeed(
          linkedEmployeeIds: linkedIds,
          window: _activityWindow,
          photoLimit: _photoPreviewLimit,
        )
        .listen((feed) {
      if (!mounted) return;

      // Don't dismiss loading for an initial empty emission — more stream
      // sources (session-based logs, photos) may still be initializing.
      final hasData = feed.activities.isNotEmpty || feed.photos.isNotEmpty;
      final doneLoading = hasData || !_activityLoading;

      setState(() {
        _activityLogs = feed.activities;
        _photos = feed.photos;
        if (doneLoading) {
          _warmupTimer?.cancel();
          _activityLoading = false;
          _photosLoading = false;
        }
        if (_showAllPhotos && _photos.length <= _collapsedPhotoCount) {
          _showAllPhotos = false;
        }
      });
    }, onError: (_) {
      if (!mounted) return;
      _warmupTimer?.cancel();
      setState(() {
        _activityLoading = false;
        _photosLoading = false;
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _warmupTimer?.cancel();
    _feedSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dashboardProvider = context.watch<DashboardProvider>();
    final status = _employeeId != null
        ? dashboardProvider.getEmployeeStatus(_employeeId!)
        : (widget.isActive ? 'active' : 'offline');
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
                      const SizedBox(height: 16),
                      _buildPresenceBanner(status),
                      const SizedBox(height: 32),

                      // Assign Task Button
                      _buildActionButtons(context),
                      const SizedBox(height: 32),

                      // Photos Section
                      _buildPhotosSection(),
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

  Widget _buildPresenceBanner(String status) {
    final isActive = status == 'active';
    final isBreak = status == 'break';
    final isSignalLost = status == 'signal_lost';

    final color = isActive
        ? AppColors.success
        : isBreak || isSignalLost
            ? AppColors.warning
            : AppColors.textTertiary;
    final background = isActive
        ? AppColors.badgeActiveBackground
        : isBreak || isSignalLost
            ? AppColors.badgeWarning
            : AppColors.badgeOfflineBackground;
    final icon = isActive
        ? AppIcons.tick_circle
        : isBreak
            ? AppIcons.coffee
            : isSignalLost
                ? AppIcons.warning_2
                : AppIcons.close_circle;
    final label = isActive
        ? 'Active'
        : isBreak
            ? 'Break'
            : isSignalLost
                ? 'Signal Lost (Reconnecting...)'
                : 'Offline';
    final helper = isSignalLost
        ? 'Elapsed session time keeps running until the backend marks the session auto-ended.'
        : isActive
            ? 'Live tracking is currently connected.'
            : isBreak
                ? 'Employee is still on the clock but temporarily on break.'
                : 'No active connection is currently reported.';

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.glassPrimary,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.glassBorder),
            boxShadow: AppShadows.glass,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: AppTypography.bodyMedium.copyWith(
                        color: color,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      helper,
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
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildActionButton(
            AppIcons.task_square,
            'Assign Task',
            () => context.push('/admin/create-task', extra: {
              'initialAssigneeName': widget.name,
            }),
          ),
          const SizedBox(width: 12),
          _buildActionButton(AppIcons.gallery, 'View Photos', () {
            context.push('/admin/employee-images', extra: {
              'employeeId': _employeeId,
            });
          }),
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

  Widget _buildPhotosSection() {
    final hasOverflow = _photos.length > _collapsedPhotoCount;
    final visiblePhotos =
        _showAllPhotos ? _photos : _photos.take(_collapsedPhotoCount).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Photos',
              style: AppTypography.h3.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (_photos.isNotEmpty)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.glassPrimary,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.glassBorder),
                ),
                child: Text(
                  '${_photos.length}',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (_photosLoading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          )
        else if (_photos.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(AppIcons.image, size: 40, color: AppColors.textTertiary),
                  const SizedBox(height: 12),
                  Text(
                    'No photos yet',
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: AppColors.glassPanelGradient,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.glassBorder),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    const spacing = 10.0;
                    final tileSize = (constraints.maxWidth - (spacing * 2)) / 3;
                    return Wrap(
                      spacing: spacing,
                      runSpacing: spacing,
                      children: [
                        for (final photo in visiblePhotos)
                          SizedBox(
                            width: tileSize,
                            height: tileSize,
                            child: _buildPhotoTile(photo),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        if (!_photosLoading && hasOverflow) ...[
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.center,
            child: TextButton(
              onPressed: () {
                setState(() => _showAllPhotos = !_showAllPhotos);
              },
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                textStyle: AppTypography.bodyMedium.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: Text(_showAllPhotos ? 'Show less' : 'Show more'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPhotoTile(PhotoModel photo) {
    final imageUrl =
        photo.thumbnailUrl.isNotEmpty ? photo.thumbnailUrl : photo.imageUrl;
    final heroTag = 'detail_photo_${photo.id}';

    return GestureDetector(
      onTap: () {
        if (photo.imageUrl.isNotEmpty) {
          precacheImage(NetworkImage(photo.imageUrl), context);
        }
        context.push('/employee/image-detail', extra: {
          'imageUrl': photo.imageUrl,
          'thumbnailUrl': imageUrl,
          'location': photo.location,
          'capturedBy': widget.name,
          'employeeId': photo.employeeId,
          'timestamp': photo.timestamp,
          'latitude': photo.latitude,
          'longitude': photo.longitude,
          'category': photo.category,
          'name': photo.customerName,
          'phone': photo.customerPhone,
          'hasFollowUp': photo.hasFollowUp,
          'heroTag': heroTag,
        });
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: AppColors.glassPrimary,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Hero(
                tag: heroTag,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: AppColors.glassPrimary,
                    child: const Icon(
                      AppIcons.image,
                      color: AppColors.textTertiary,
                      size: 24,
                    ),
                  ),
                ),
              ),
              // Time overlay
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        AppColors.gradientStart.withValues(alpha: 0.6),
                      ],
                    ),
                  ),
                  child: Text(
                    photo.formattedTime,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActivityFeed() {
    if (_activityLoading && _activityLogs.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.only(top: 32),
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }

    if (_activityLogs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 32),
          child: Column(
            children: [
              Icon(
                AppIcons.activity,
                size: 48,
                color: AppColors.textTertiary,
              ),
              const SizedBox(height: 16),
              Text(
                'No activity in the last 24 hours',
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

        // Map log type to icon & color
        IconData icon;
        Color color;
        switch (log.type) {
          case 'location_update':
            icon = AppIcons.location;
            color = AppColors.success;
            break;
          case 'task_started':
            icon = AppIcons.task_square;
            color = AppColors.primary;
            break;
          case 'task_completed':
            icon = AppIcons.tick_circle;
            color = AppColors.success;
            break;
          case 'photo_captured':
            icon = AppIcons.camera;
            color = AppColors.info;
            break;
          case 'session_started':
            icon = AppIcons.timer_start;
            color = AppColors.info;
            break;
          case 'session_ended':
            icon = AppIcons.timer_pause;
            color = AppColors.warning;
            break;
          case 'break':
            icon = AppIcons.coffee;
            color = AppColors.warning;
            break;
          default:
            icon = AppIcons.activity;
            color = AppColors.primary;
        }

        return _buildTimelineItem(
          icon: icon,
          color: color,
          title: log.title,
          time: log.formattedFeedTime,
          description: _resolveActivityDetail(log),
          isLast: isLast,
          isOpacity: isLast,
        );
      }),
    );
  }

  Widget _buildTimelineItem({
    required IconData icon,
    Color color = AppColors.primary,
    required String title,
    required String time,
    required String description,
    required bool isLast,
    bool isOpacity = false,
  }) {
    final showMap = icon == AppIcons.location;
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
                              color: color.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(
                              icon,
                              color: color,
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
                                    Row(
                                      children: [
                                        if (showMap)
                                          GestureDetector(
                                            onTap: () => _openMaps(description),
                                            child: Container(
                                              width: 28,
                                              height: 28,
                                              decoration: BoxDecoration(
                                                color: AppColors.glassPrimary,
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                border: Border.all(
                                                  color: AppColors.glassBorder,
                                                ),
                                              ),
                                              child: const Icon(
                                                AppIcons.map_1,
                                                size: 14,
                                                color: AppColors.primary,
                                              ),
                                            ),
                                          ),
                                        if (showMap) const SizedBox(width: 8),
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

  String _resolveActivityDetail(ActivityLogModel log) {
    final metadata = log.metadata;
    final payload = log.payload;

    if (log.type == 'location_update') {
      final metaAddress = metadata?['address']?.toString().trim() ?? '';
      final payloadAddress = payload?['address']?.toString().trim() ?? '';
      final rawDetail = log.detail.trim();

      for (final candidate in [metaAddress, payloadAddress, rawDetail]) {
        if (candidate.isNotEmpty &&
            !GeocodingCache.isCoordinateString(candidate)) {
          return candidate;
        }
      }

      final lat = (metadata?['latitude'] as num?)?.toDouble();
      final lng = (metadata?['longitude'] as num?)?.toDouble();
      if (lat != null && lng != null) {
        final cached = GeocodingCache.instance.getCached(lat, lng);
        if (cached != null) return cached;
        GeocodingCache.instance.resolve(lat, lng).then((_) {
          if (mounted) setState(() {});
        });
        return '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
      }
      return rawDetail;
    }

    return log.detail.trim();
  }

  Future<void> _openMaps(String query) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(query)}',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
