import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:izumi/core/ui/app_icons.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';
import '../../models/activity_log_model.dart';
import '../../models/daily_summary_model.dart';
import '../../models/photo_model.dart';
import '../../models/session_model.dart';
import '../../providers/analytics_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/admin_activity_feed_service.dart';
import '../../services/geocoding_cache.dart';
import '../../widgets/glass/gradient_background.dart';
import '../../widgets/glass/glass_panel.dart';
import '../../widgets/navigation/app_header.dart';

class EmployeeActivityScreen extends StatefulWidget {
  final String employeeName;
  final String employeeId;
  final String? profileImageUrl;
  final List<String> linkedEmployeeIds;
  final List<ActivityLogModel> initialActivities;
  final DateTime? initialDate;
  final Map<String, dynamic>? initialLiveStats;
  final Map<String, dynamic>? initialAggregateStats;
  final String selectedPeriod;
  final DateTime? rangeStart;
  final DateTime? rangeEnd;

  const EmployeeActivityScreen({
    super.key,
    required this.employeeName,
    required this.employeeId,
    this.profileImageUrl,
    this.linkedEmployeeIds = const [],
    this.initialActivities = const [],
    this.initialDate,
    this.initialLiveStats,
    this.initialAggregateStats,
    this.selectedPeriod = 'Today',
    this.rangeStart,
    this.rangeEnd,
  });

  @override
  State<EmployeeActivityScreen> createState() => _EmployeeActivityScreenState();
}

class _EmployeeActivityScreenState extends State<EmployeeActivityScreen> {
  final AdminActivityFeedService _feedService = AdminActivityFeedService();

  DateTime _rangeStart = DateTime.now();
  DateTime _rangeEnd = DateTime.now();
  bool _showFullGallery = false;
  bool _isLoading = true;
  int _loadVersion = 0;
  _EmployeeDayActivity? _dayActivity;
  Timer? _liveRefreshTimer;

  @override
  void initState() {
    super.initState();
    _initializeRange();
    _liveRefreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_isSelectedToday()) return;
      setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadDayData();
    });
  }

  void _initializeRange() {
    final now = DateTime.now();
    final normalizedStart = widget.rangeStart != null
        ? _normalizeDate(widget.rangeStart!)
        : _normalizeDate(widget.initialDate ?? now);
    final normalizedEnd = widget.rangeEnd != null
        ? widget.rangeEnd!
        : DateTime(
            normalizedStart.year,
            normalizedStart.month,
            normalizedStart.day,
            23,
            59,
            59,
          );
    _rangeStart = normalizedStart;
    _rangeEnd = normalizedEnd;
  }

  @override
  void dispose() {
    _liveRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadDayData() async {
    final loadVersion = ++_loadVersion;
    setState(() => _isLoading = true);

    try {
      final authProvider = context.read<AuthProvider>();
      final feed = await _feedService.loadRangeFeed(
        employeeId: widget.employeeId,
        linkedEmployeeIds: _linkedIds(),
        rangeStart: _rangeStart,
        rangeEnd: _rangeEnd,
        enterpriseId: authProvider.enterpriseId,
      );

      final initialActivities = _dedupeActivityLogs(
        widget.initialActivities
            .where((activity) => _isInSelectedRange(activity.timestamp))
            .fold<Map<String, ActivityLogModel>>({}, (acc, activity) {
              acc[activity.id] = activity;
              return acc;
            })
            .values
            .toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp)),
      );

      final effectiveActivities =
          feed.activities.isNotEmpty ? feed.activities : initialActivities;

      if (!mounted || loadVersion != _loadVersion) return;

      setState(() {
        _dayActivity = _EmployeeDayActivity(
          selectedDate: _rangeStart,
          summary: feed.summary ?? _buildFallbackSummary(),
          activities: effectiveActivities,
          photos: feed.photos,
          sessions: feed.sessions,
        );
        _isLoading = false;
      });
    } catch (error, stackTrace) {
      debugPrint('[EmployeeActivityScreen] Failed to load day data: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted || loadVersion != _loadVersion) return;
      setState(() {
        _dayActivity = _fallbackDayActivity();
        _isLoading = false;
      });
    }
  }

  _EmployeeDayActivity _fallbackDayActivity() {
    final initialActivities = _dedupeActivityLogs(
      widget.initialActivities
          .where((activity) => _isInSelectedRange(activity.timestamp))
          .fold<Map<String, ActivityLogModel>>({}, (acc, activity) {
            acc[activity.id] = activity;
            return acc;
          })
          .values
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp)),
    );

    return _EmployeeDayActivity(
      selectedDate: _rangeStart,
      summary: _buildFallbackSummary(),
      activities: initialActivities,
      photos: const [],
      sessions: const [],
    );
  }

  DailySummaryModel? _buildFallbackSummary() {
    final stats = widget.initialAggregateStats;
    if (stats == null) return null;

    final durationText = (stats['duration'] as String?)?.trim() ?? '';
    final duration = _parseDurationFromDetail('Duration: $durationText');
    final photos = (stats['photos'] as num?)?.toInt() ??
        _livePhotosToday(_currentLiveStats());
    final tasks = (stats['tasks'] as num?)?.toInt() ?? 0;
    final distance = (stats['distance'] as num?)?.toDouble() ?? 0.0;

    if ((duration == null || duration == Duration.zero) &&
        photos <= 0 &&
        tasks <= 0 &&
        distance <= 0) {
      return null;
    }

    return DailySummaryModel(
      id: 'fallback_${widget.employeeId}_${_selectedRangeKey()}',
      enterpriseId: '',
      employeeId: widget.employeeId,
      date: _rangeStart,
      totalDuration: duration?.inSeconds ?? 0,
      totalDistance: distance,
      photosCount: photos,
      tasksCompleted: tasks,
      locationsVisited: const [],
      sessionIds: const [],
      isOffDuty: false,
    );
  }

  List<ActivityLogModel> _dedupeActivityLogs(List<ActivityLogModel> logs) {
    final seenKeys = <String>{};
    final deduped = <ActivityLogModel>[];

    for (final log in logs) {
      final key = _activityDedupKey(log);
      if (!seenKeys.add(key)) continue;
      deduped.add(log);
    }
    return deduped;
  }

  String _activityDedupKey(ActivityLogModel log) {
    if (log.type != 'location_update') {
      return 'id:${log.id}';
    }
    final minuteBucket = DateTime(
      log.timestamp.year,
      log.timestamp.month,
      log.timestamp.day,
      log.timestamp.hour,
      log.timestamp.minute,
    );
    final lat =
        (log.metadata?['latitude'] as num?)?.toDouble().toStringAsFixed(5) ??
            '';
    final lng =
        (log.metadata?['longitude'] as num?)?.toDouble().toStringAsFixed(5) ??
            '';
    final detail = log.detail.trim().toLowerCase();
    final sessionId = log.sessionId ?? '';
    return 'location|$sessionId|$minuteBucket|$lat|$lng|$detail';
  }

  List<String> _linkedIds() {
    final analytics = context.read<AnalyticsProvider>();
    return _feedService.resolveLinkedEmployeeIds(
      widget.employeeId,
      analytics.employees,
      additionalIds: widget.linkedEmployeeIds,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final dayActivity = _dayActivity ??
        _EmployeeDayActivity(
          selectedDate: _rangeStart,
          summary: null,
          activities: const [],
          photos: const [],
          sessions: const [],
        );
    final stats = _buildDayStats(dayActivity, _currentLiveStats());

    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              AppHeader(
                title: "${widget.employeeName}'s Activity",
                type: AppHeaderType.secondary,
                showAvatar: false,
              ),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                        ),
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSummaryCard(stats),
                            const SizedBox(height: 20),
                            _buildCapturesSection(dayActivity),
                            const SizedBox(height: 20),
                            _buildTimeline(dayActivity),
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

  // ═══════════════════════════════════════════════════════════════════════════
  // SUMMARY CARD
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSummaryCard(Map<String, String> stats) {
    return GlassPanel(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Column(
        children: [
          _buildSummaryRow(
            icon: AppIcons.timer_1,
            color: AppColors.primary,
            label: 'Duration',
            value: stats['duration']!,
          ),
          _buildSummaryDivider(),
          _buildSummaryRow(
            icon: AppIcons.routing_2,
            color: AppColors.warning,
            label: 'Distance',
            value: stats['distance']!,
          ),
          _buildSummaryDivider(),
          _buildSummaryRow(
            icon: AppIcons.camera,
            color: AppColors.info,
            label: 'Photos',
            value: stats['photos']!,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Text(
            value,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Divider(
        height: 1,
        thickness: 0.5,
        color: AppColors.divider.withValues(alpha: 0.5),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CAPTURES SECTION
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildCapturesSection(_EmployeeDayActivity dayActivity) {
    final photos = dayActivity.photos;

    // Section header
    final header = Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(AppIcons.camera, size: 13, color: AppColors.primary),
              const SizedBox(width: 5),
              Text(
                '${photos.length} capture${photos.length == 1 ? '' : 's'}',
                style: AppTypography.caption.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        if (photos.isNotEmpty)
          GestureDetector(
            onTap: () => setState(() => _showFullGallery = !_showFullGallery),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _showFullGallery ? 'Collapse' : 'See All',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  _showFullGallery
                      ? AppIcons.arrow_up
                      : AppIcons.arrow_right_3,
                  size: 14,
                  color: AppColors.primary,
                ),
              ],
            ),
          ),
      ],
    );

    if (photos.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const SizedBox(height: 20),
          Center(
            child: Column(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    AppIcons.gallery,
                    size: 24,
                    color: AppColors.primary.withValues(alpha: 0.4),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'No captures for this period',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (_showFullGallery) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const SizedBox(height: 14),
          _GallerySection(
            photos: photos,
            employeeName: widget.employeeName,
          ),
        ],
      );
    }

    // Horizontal photo preview strip
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        const SizedBox(height: 12),
        SizedBox(
          height: 100,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: photos.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final photo = photos[index];
              final previewUrl = photo.thumbnailUrl.isNotEmpty
                  ? photo.thumbnailUrl
                  : photo.imageUrl;
              final heroTag = 'capture_preview_${photo.id}';
              return GestureDetector(
                onTap: () {
                  context.push('/employee/image-detail', extra: {
                    'imageUrl': photo.imageUrl,
                    'thumbnailUrl': previewUrl,
                    'location': photo.location,
                    'capturedBy': widget.employeeName,
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
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: 100,
                    height: 100,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Hero(
                          tag: heroTag,
                          child: Image.network(
                            previewUrl,
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, progress) {
                              if (progress == null) return child;
                              return Container(
                                color: AppColors.glassPrimary,
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.primary,
                                  ),
                                ),
                              );
                            },
                            errorBuilder: (_, __, ___) => Container(
                              color: AppColors.glassPrimary,
                              child: Icon(
                                AppIcons.image,
                                color: AppColors.textTertiary,
                                size: 24,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(6, 10, 6, 5),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.6),
                                ],
                              ),
                            ),
                            child: Text(
                              DateFormat('h:mm a').format(photo.timestamp),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        if ((photo.category ?? '').isNotEmpty)
                          Positioned(
                            top: 5,
                            right: 5,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                (photo.category ?? '').length > 6
                                    ? '${(photo.category ?? '').substring(0, 6)}\u2026'
                                    : (photo.category ?? ''),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 8,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTIVITY TIMELINE
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTimeline(_EmployeeDayActivity dayActivity) {
    if (dayActivity.activities.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Activity Timeline',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              _isSelectedToday() && _hasLiveStatsForToday()
                  ? 'Live session activity is in progress'
                  : 'No activity for this period',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      );
    }

    final activities = dayActivity.activities;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Activity Timeline',
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 14),
        ...List.generate(activities.length, (index) {
          return _buildTimelineItem(
            activities[index],
            isLast: index == activities.length - 1,
          );
        }),
      ],
    );
  }

  Widget _buildTimelineItem(ActivityLogModel activity, {bool isLast = false}) {
    final type = activity.type;
    IconData icon;
    Color color;
    switch (type) {
      case 'session_started':
        icon = AppIcons.timer_start;
        color = AppColors.success;
        break;
      case 'session_ended':
      case 'session_auto_ended':
        icon = AppIcons.timer_pause;
        color = AppColors.critical;
        break;
      case 'location_update':
        icon = AppIcons.location;
        color = AppColors.warning;
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
      case 'break':
        icon = AppIcons.coffee;
        color = AppColors.warning;
        break;
      default:
        icon = AppIcons.activity;
        color = AppColors.primary;
    }

    // For location updates, prefer a human-readable address over raw coords.
    final detail = _resolveActivityDetail(activity);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline connector column
          SizedBox(
            width: 24,
            child: Column(
              children: [
                const SizedBox(height: 16),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.3),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1.5,
                      color: AppColors.divider,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Content card
          Expanded(
            child: GlassPanel(
              margin: EdgeInsets.only(bottom: isLast ? 0 : 8),
              padding: const EdgeInsets.all(14),
              onTap: () => _onActivityTap(context, activity),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 18, color: color),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                activity.title,
                                style: AppTypography.bodySmall.copyWith(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              DateFormat('h:mm a').format(activity.timestamp),
                              style: AppTypography.small.copyWith(
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ],
                        ),
                        if (detail.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            detail,
                            style: AppTypography.caption.copyWith(
                              color: AppColors.textSecondary,
                              height: 1.3,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Returns the best display text for an activity's detail.
  /// For location updates: prefers a human-readable address from metadata,
  /// falling back to compact coordinates only if no address is available.
  String _resolveActivityDetail(ActivityLogModel activity) {
    final metadata = activity.metadata;
    final payload = activity.payload;

    if (activity.type == 'location_update') {
      final metaAddress = metadata?['address']?.toString().trim() ?? '';
      final payloadAddress = payload?['address']?.toString().trim() ?? '';
      final rawDetail = activity.detail.trim();

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

    return activity.detail.trim();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STATS CALCULATION
  // ═══════════════════════════════════════════════════════════════════════════

  Map<String, String> _buildDayStats(
    _EmployeeDayActivity dayActivity,
    Map<String, dynamic>? liveStats,
  ) {
    final sessions = dayActivity.sessions
        .where((session) => _sessionOverlapsSelectedRange(session))
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    final sessionStarts = dayActivity.activities
        .where((activity) => activity.type == 'session_started')
        .map((activity) => activity.timestamp)
        .toList()
      ..sort();
    final sessionEnds = dayActivity.activities
        .where((activity) =>
            activity.type == 'session_ended' ||
            activity.type == 'session_auto_ended')
        .map((activity) => activity.timestamp)
        .toList()
      ..sort();

    String formatTime(DateTime? value) {
      if (value == null) return '--';
      return DateFormat('hh:mm a').format(value);
    }

    String formatDuration(Duration value) {
      if (value == Duration.zero) return '--';
      final hours = value.inHours;
      final minutes = value.inMinutes.remainder(60);
      if (hours > 0) return '${hours}h ${minutes}m';
      return '${value.inMinutes}m';
    }

    final fallbackEndLog = sessionEnds.isNotEmpty
        ? dayActivity.activities.firstWhere(
            (activity) =>
                activity.timestamp == sessionEnds.last &&
                (activity.type == 'session_ended' ||
                    activity.type == 'session_auto_ended'),
          )
        : null;
    final durationFromLog = _parseDurationFromDetail(fallbackEndLog?.detail);
    final summaryDuration = dayActivity.summary?.duration ?? Duration.zero;
    final liveDuration = _liveDuration(liveStats);
    final totalDuration = summaryDuration > Duration.zero
        ? summaryDuration
        : (durationFromLog ?? liveDuration);

    final endTime = sessionEnds.isNotEmpty
        ? sessionEnds.last
        : sessions
            .map((session) => session.endTime)
            .whereType<DateTime>()
            .fold<DateTime?>(null, (latest, value) {
            if (latest == null || value.isAfter(latest)) {
              return value;
            }
            return latest;
          });
    final startTime = sessionStarts.isNotEmpty
        ? sessionStarts.first
        : sessions.isNotEmpty
            ? sessions.first.startTime
            : (endTime != null && totalDuration > Duration.zero
                ? endTime.subtract(totalDuration)
                : (_isSelectedToday() && liveDuration > Duration.zero
                    ? DateTime.now().subtract(liveDuration)
                    : null));

    final photoCount = dayActivity.photoCount > 0
        ? dayActivity.photoCount
        : (_isSelectedToday()
            ? (_livePhotosToday(liveStats) > 0
                ? _livePhotosToday(liveStats)
                : dayActivity.photoCount)
            : null);

    final distance = dayActivity.summary?.totalDistance ?? 0.0;

    return {
      'startedAt': formatTime(startTime),
      'endedAt': formatTime(endTime),
      'duration': formatDuration(totalDuration),
      'photos': '${photoCount ?? dayActivity.photoCount}',
      'distance': distance > 0 ? '${distance.toStringAsFixed(1)} km' : '--',
    };
  }

  Duration? _parseDurationFromDetail(String? detail) {
    if (detail == null || detail.isEmpty) return null;
    final hhmmss = RegExp(r'(\d{2}):(\d{2}):(\d{2})').firstMatch(detail);
    if (hhmmss != null) {
      return Duration(
        hours: int.parse(hhmmss.group(1)!),
        minutes: int.parse(hhmmss.group(2)!),
        seconds: int.parse(hhmmss.group(3)!),
      );
    }

    final hrMin = RegExp(r'(\d+)h\s+(\d+)m').firstMatch(detail);
    if (hrMin != null) {
      return Duration(
        hours: int.parse(hrMin.group(1)!),
        minutes: int.parse(hrMin.group(2)!),
      );
    }

    final minOnly = RegExp(r'(\d+)\s*m').firstMatch(detail);
    if (minOnly != null) {
      return Duration(minutes: int.parse(minOnly.group(1)!));
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  DateTime _normalizeDate(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  String _selectedRangeKey() {
    return '${_dayKeyForSelectedDate(_rangeStart)}_${_dayKeyForSelectedDate(_rangeEnd)}';
  }

  String _dayKeyForSelectedDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  bool _isInSelectedRange(DateTime timestamp) {
    final local = timestamp.toLocal();
    return !local.isBefore(_rangeStart) && !local.isAfter(_rangeEnd);
  }

  bool _sessionOverlapsSelectedRange(SessionModel session) {
    final localStart = session.startTime.toLocal();
    final localEnd = (session.endTime ?? session.startTime).toLocal();
    return !localStart.isAfter(_rangeEnd) && !localEnd.isBefore(_rangeStart);
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  bool _isSelectedToday() {
    final today = _normalizeDate(DateTime.now());
    return _isSameDay(_rangeStart, today) &&
        _isSameDay(_normalizeDate(_rangeEnd), today);
  }

  bool _hasLiveStatsForToday() {
    final stats = _currentLiveStats();
    if (stats == null) return false;
    final duration = (stats['sessionDuration'] as num?)?.toInt() ?? 0;
    final photos = (stats['photosToday'] as num?)?.toInt() ?? 0;
    final tasks = (stats['tasksToday'] as num?)?.toInt() ?? 0;
    final distance = (stats['distance'] as num?)?.toDouble() ?? 0.0;
    return duration > 0 || photos > 0 || tasks > 0 || distance > 0;
  }

  Map<String, dynamic>? _currentLiveStats() {
    final analytics = context.read<AnalyticsProvider>();
    final statsByEmployee = analytics.activeStatsData;
    final linkedIds = _linkedIds();
    final merged = <String, dynamic>{
      'sessionDuration': 0,
      'distance': 0.0,
      'photosToday': 0,
      'tasksToday': 0,
    };
    var hasAny = false;
    int? latestStartTimeMs;

    for (final employeeId in linkedIds) {
      final stats = statsByEmployee[employeeId];
      if (stats == null) continue;
      hasAny = true;
      merged['sessionDuration'] = (merged['sessionDuration'] as int) +
          ((stats['sessionDuration'] as num?)?.toInt() ?? 0);
      merged['distance'] = (merged['distance'] as double) +
          ((stats['distance'] as num?)?.toDouble() ?? 0.0);
      merged['photosToday'] = (merged['photosToday'] as int) +
          ((stats['photosToday'] as num?)?.toInt() ?? 0);
      merged['tasksToday'] = (merged['tasksToday'] as int) +
          ((stats['tasksToday'] as num?)?.toInt() ?? 0);

      final startTimeMs = (stats['sessionStartTimeMs'] as num?)?.toInt();
      if (startTimeMs != null &&
          (latestStartTimeMs == null || startTimeMs > latestStartTimeMs)) {
        latestStartTimeMs = startTimeMs;
      }
    }

    if (!hasAny) return widget.initialLiveStats;
    if (latestStartTimeMs != null) {
      merged['sessionStartTimeMs'] = latestStartTimeMs;
    }
    return merged;
  }

  Duration _liveDuration(Map<String, dynamic>? stats) {
    if (stats == null) return Duration.zero;
    final sessionStartTimeMs = (stats['sessionStartTimeMs'] as num?)?.toInt();
    if (sessionStartTimeMs != null) {
      final startedAt =
          DateTime.fromMillisecondsSinceEpoch(sessionStartTimeMs).toLocal();
      final elapsed = DateTime.now().difference(startedAt);
      if (!elapsed.isNegative) {
        return elapsed;
      }
    }
    final seconds = (stats['sessionDuration'] as num?)?.toInt() ?? 0;
    return Duration(seconds: seconds);
  }

  int _livePhotosToday(Map<String, dynamic>? stats) {
    return (stats?['photosToday'] as num?)?.toInt() ?? 0;
  }

  void _onActivityTap(BuildContext context, ActivityLogModel activity) {
    final type = activity.type;
    final metadata = activity.metadata;

    switch (type) {
      case 'location_update':
      case 'location_lost':
      case 'location_recovered':
        final lat = metadata?['latitude'];
        final lng = metadata?['longitude'];
        if (lat != null && lng != null) {
          final uri = Uri.parse(
            'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
          );
          launchUrl(uri, mode: LaunchMode.externalApplication);
        }
        break;
      case 'session_started':
      case 'session_ended':
      case 'session_auto_ended':
      case 'task_started':
      case 'task_completed':
        context.push('/admin/employee/${widget.employeeId}', extra: {
          'name': widget.employeeName,
          'isActive': false,
        });
        break;
      case 'photo_captured':
        setState(() => _showFullGallery = true);
        break;
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// DATA MODEL
// ══════════════════════════════════════════════════════════════════════════════

class _EmployeeDayActivity {
  final DateTime selectedDate;
  final DailySummaryModel? summary;
  final List<ActivityLogModel> activities;
  final List<PhotoModel> photos;
  final List<SessionModel> sessions;

  const _EmployeeDayActivity({
    required this.selectedDate,
    required this.summary,
    required this.activities,
    required this.photos,
    required this.sessions,
  });

  int get photoCount => photos.length;

  bool get isEmpty => summary == null && activities.isEmpty && photos.isEmpty;
}

// ══════════════════════════════════════════════════════════════════════════════
// GALLERY SECTION
// ══════════════════════════════════════════════════════════════════════════════

class _GallerySection extends StatefulWidget {
  final List<PhotoModel> photos;
  final String employeeName;

  const _GallerySection({
    required this.photos,
    required this.employeeName,
  });

  @override
  State<_GallerySection> createState() => _GallerySectionState();
}

class _GallerySectionState extends State<_GallerySection> {
  String _selectedCategory = 'All';

  List<String> get _categories {
    final cats = <String>{'All'};
    for (final photo in widget.photos) {
      final cat = photo.category;
      if (cat != null && cat.isNotEmpty) cats.add(cat);
    }
    return cats.toList();
  }

  List<PhotoModel> get _filtered {
    if (_selectedCategory == 'All') return widget.photos;
    return widget.photos
        .where((p) =>
            (p.category ?? '').toLowerCase() == _selectedCategory.toLowerCase())
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final categories = _categories;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Category filter chips — only show if multiple categories
        if (categories.length > 1) ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: categories.map((cat) {
                final selected = _selectedCategory == cat;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedCategory = cat),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.primary
                            : AppColors.glassPrimary,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: selected
                              ? AppColors.primary
                              : AppColors.glassBorder,
                        ),
                      ),
                      child: Text(
                        cat,
                        style: AppTypography.caption.copyWith(
                          color:
                              selected ? Colors.white : AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 14),
        ],

        // Photo grid
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 8.0;
            final tileSize = (constraints.maxWidth - spacing * 2) / 3;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: filtered
                  .map((photo) => SizedBox(
                        width: tileSize,
                        height: tileSize,
                        child: _GalleryTile(
                          photo: photo,
                          employeeName: widget.employeeName,
                        ),
                      ))
                  .toList(),
            );
          },
        ),
      ],
    );
  }
}

class _GalleryTile extends StatelessWidget {
  final PhotoModel photo;
  final String employeeName;

  const _GalleryTile({
    required this.photo,
    required this.employeeName,
  });

  @override
  Widget build(BuildContext context) {
    final previewUrl =
        photo.thumbnailUrl.isNotEmpty ? photo.thumbnailUrl : photo.imageUrl;
    final heroTag = 'gallery_tile_${photo.id}';

    return GestureDetector(
      onTap: () {
        context.push('/employee/image-detail', extra: {
          'imageUrl': photo.imageUrl,
          'thumbnailUrl': previewUrl,
          'location': photo.location,
          'capturedBy': employeeName,
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Hero(
              tag: heroTag,
              child: Image.network(
                previewUrl,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Container(
                    color: AppColors.glassPrimary,
                    child: Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary.withValues(alpha: 0.5),
                        value: loadingProgress.expectedTotalBytes != null
                            ? loadingProgress.cumulativeBytesLoaded /
                                loadingProgress.expectedTotalBytes!
                            : null,
                      ),
                    ),
                  );
                },
                errorBuilder: (_, __, ___) => Container(
                  color: AppColors.glassPrimary,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(AppIcons.image,
                          color: AppColors.textTertiary, size: 24),
                      const SizedBox(height: 4),
                      Text(
                        'Error',
                        style: AppTypography.small
                            .copyWith(color: AppColors.textTertiary),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(6, 12, 6, 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.6),
                    ],
                  ),
                ),
                child: Text(
                  DateFormat('h:mm a').format(photo.timestamp),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
            if ((photo.category ?? '').isNotEmpty)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    (photo.category ?? '').length > 8
                        ? '${(photo.category ?? '').substring(0, 8)}\u2026'
                        : (photo.category ?? ''),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
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
