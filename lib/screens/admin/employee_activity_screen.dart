import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
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
import '../../providers/enterprise_provider.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/session_repository.dart';
import '../../services/admin_activity_feed_service.dart';
import '../../services/geocoding_cache.dart';
import '../../services/unified_data_layer.dart';
import '../../widgets/glass/gradient_background.dart';


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
  State<EmployeeActivityScreen> createState() =>
      _EmployeeActivityScreenState();
}

class _EmployeeActivityScreenState extends State<EmployeeActivityScreen> {
  final AdminActivityFeedService _feedService = AdminActivityFeedService();
  final SessionRepository _sessionRepository = SessionRepository();

  late String _selectedPeriod;
  DateTime _rangeStart = DateTime.now();
  DateTime _rangeEnd = DateTime.now();
  bool _showFullGallery = false;
  bool _isLoading = true;
  int _loadVersion = 0;
  _EmployeeDayActivity? _dayActivity;
  Timer? _liveRefreshTimer;
  /// Summary-card distance, sourced from UnifiedDataLayer.getDistance for
  /// every day in the selected range. null = not yet resolved (card shows --).
  double? _distanceKm;

  // Route map state
  List<LatLng> _routePoints = [];
  Set<Marker> _markers = {};
  bool _isLoadingRoute = false;

  @override
  void initState() {
    super.initState();
    _selectedPeriod = widget.selectedPeriod;
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
    setState(() {
      _isLoading = true;
      _distanceKm = null;
    });

    try {
      final authProvider = context.read<AuthProvider>();
      final feed = await _feedService.loadRangeFeed(
        employeeId: widget.employeeId,
        linkedEmployeeIds: _linkedIds(),
        rangeStart: _rangeStart,
        rangeEnd: _rangeEnd,
        enterpriseId: authProvider.enterpriseId ?? '',
      );

      if (!mounted || loadVersion != _loadVersion) return;

      setState(() {
        _dayActivity = _EmployeeDayActivity(
          selectedDate: _rangeStart,
          summary: feed.summary ?? _buildFallbackSummary(),
          activities: feed.activities,
          photos: feed.photos,
          sessions: feed.sessions,
        );
        _isLoading = false;
      });
      _loadRouteData(feed.sessions);
      _loadDistanceFromUdl(loadVersion, authProvider.enterpriseId);
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

  /// Distance for the summary card comes from UnifiedDataLayer. Iterates
  /// every day in the selected range and sums UDL.getDistance — UDL handles
  /// the dailySummary read and the live-RTDB top-up internally.
  Future<void> _loadDistanceFromUdl(int loadVersion, String? enterpriseId) async {
    if (enterpriseId == null || enterpriseId.isEmpty) return;
    double total = 0.0;
    var cursor =
        DateTime(_rangeStart.year, _rangeStart.month, _rangeStart.day);
    final endDay = DateTime(_rangeEnd.year, _rangeEnd.month, _rangeEnd.day);
    while (!cursor.isAfter(endDay)) {
      try {
        total += await UnifiedDataLayer.I.getDistance(
          employeeId: widget.employeeId,
          enterpriseId: enterpriseId,
          date: cursor,
        );
      } catch (_) {}
      cursor = cursor.add(const Duration(days: 1));
      if (!mounted || loadVersion != _loadVersion) return;
    }
    if (!mounted || loadVersion != _loadVersion) return;
    setState(() => _distanceKm = total);
  }

  Future<void> _loadRouteData(List<SessionModel> sessions) async {
    if (sessions.isEmpty) {
      setState(() {
        _routePoints = [];
        _markers = {};
        _isLoadingRoute = false;
      });
      return;
    }

    setState(() => _isLoadingRoute = true);

    try {
      final allPoints = <LatLng>[];
      final sessionBoundaries = <LatLng>[];

      // Sort sessions by start time
      final sortedSessions = List<SessionModel>.from(sessions)
        ..sort((a, b) => a.startTime.compareTo(b.startTime));

      for (final session in sortedSessions) {
        try {
          final locations =
              await _sessionRepository.getSessionLocations(session.id);
          if (locations.isEmpty) continue;

          final sessionStart =
              LatLng(locations.first.latitude, locations.first.longitude);
          final sessionEnd =
              LatLng(locations.last.latitude, locations.last.longitude);

          sessionBoundaries.add(sessionStart);
          sessionBoundaries.add(sessionEnd);

          for (final loc in locations) {
            allPoints.add(LatLng(loc.latitude, loc.longitude));
          }
        } catch (_) {
          // Skip sessions whose locations fail to load
        }
      }

      if (!mounted) return;

      final markers = <Marker>{};
      if (allPoints.isNotEmpty) {
        // Green marker at first point
        markers.add(Marker(
          markerId: const MarkerId('route_start'),
          position: allPoints.first,
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: const InfoWindow(title: 'Start'),
        ));

        // Red marker at last point
        markers.add(Marker(
          markerId: const MarkerId('route_end'),
          position: allPoints.last,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(title: 'End'),
        ));

        // Intermediate session boundary markers (indigo/violet)
        // Skip the very first start and very last end since they are already marked
        for (var i = 0; i < sessionBoundaries.length; i++) {
          final isVeryFirst = i == 0;
          final isVeryLast = i == sessionBoundaries.length - 1;
          if (isVeryFirst || isVeryLast) continue;

          markers.add(Marker(
            markerId: MarkerId('boundary_$i'),
            position: sessionBoundaries[i],
            icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueViolet),
            infoWindow: InfoWindow(
                title: i.isEven ? 'Session start' : 'Session end'),
          ));
        }
      }

      setState(() {
        _routePoints = allPoints;
        _markers = markers;
        _isLoadingRoute = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _routePoints = [];
        _markers = {};
        _isLoadingRoute = false;
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
    // Distance is no longer inherited from the parent screen — it's loaded
    // independently via UnifiedDataLayer in _loadDistanceFromUdl. This
    // fallback exists only to keep duration/photos/tasks visible during the
    // first frame before loadRangeFeed returns.

    if ((duration == null || duration == Duration.zero) &&
        photos <= 0 &&
        tasks <= 0) {
      return null;
    }

    return DailySummaryModel(
      id: 'fallback_${widget.employeeId}_${_selectedRangeKey()}',
      enterpriseId: '',
      employeeId: widget.employeeId,
      date: _rangeStart,
      totalDuration: duration?.inSeconds ?? 0,
      totalDistance: 0.0,
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
    // EnterpriseProvider is the single source of truth for the employee list
    // and migration chain index (O(1) lookup, guaranteed populated by the
    // splash-gated bootstrap).
    return context.read<EnterpriseProvider>().resolveLinkedIds(
          widget.employeeId,
          additionalIds: widget.linkedEmployeeIds,
        );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PERIOD PICKER
  // ═══════════════════════════════════════════════════════════════════════════

  void _showPeriodPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text(
                  'Select Period',
                  style: AppTypography.headline.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                for (final period in [
                  'Today',
                  'Yesterday',
                  'This Month',
                  'Custom Range'
                ])
                  ListTile(
                    title: Text(
                      period,
                      style: AppTypography.body.copyWith(
                        color: _selectedPeriod == period
                            ? AppColors.primary
                            : AppColors.textPrimary,
                        fontWeight: _selectedPeriod == period
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                    trailing: _selectedPeriod == period
                        ? const Icon(Icons.check, color: AppColors.primary)
                        : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      _onPeriodSelected(period);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _onPeriodSelected(String period) {
    final now = DateTime.now();
    final today = _normalizeDate(now);

    DateTime newStart;
    DateTime newEnd;

    switch (period) {
      case 'Today':
        newStart = today;
        newEnd = DateTime(today.year, today.month, today.day, 23, 59, 59);
        break;
      case 'Yesterday':
        final yesterday = today.subtract(const Duration(days: 1));
        newStart = yesterday;
        newEnd = DateTime(
            yesterday.year, yesterday.month, yesterday.day, 23, 59, 59);
        break;
      case 'This Week':
        final weekday = today.weekday;
        newStart = today.subtract(Duration(days: weekday - 1));
        newEnd = DateTime(today.year, today.month, today.day, 23, 59, 59);
        break;
      case 'This Month':
        newStart = DateTime(today.year, today.month, 1);
        newEnd = DateTime(today.year, today.month, today.day, 23, 59, 59);
        break;
      case 'Custom Range':
        _showCustomRangePicker();
        return;
      default:
        return;
    }

    setState(() {
      _selectedPeriod = period;
      _rangeStart = newStart;
      _rangeEnd = newEnd;
      _routePoints = [];
      _markers = {};
    });
    _loadDayData();
  }

  Future<void> _showCustomRangePicker() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _rangeStart, end: _rangeEnd),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && mounted) {
      setState(() {
        _selectedPeriod = 'Custom Range';
        _rangeStart = _normalizeDate(picked.start);
        _rangeEnd = DateTime(
          picked.end.year,
          picked.end.month,
          picked.end.day,
          23,
          59,
          59,
        );
        _routePoints = [];
        _markers = {};
      });
      _loadDayData();
    }
  }

  String get _periodLabel {
    if (_selectedPeriod == 'Custom Range') {
      final startStr = DateFormat('MMM d').format(_rangeStart);
      final endStr = DateFormat('MMM d').format(_rangeEnd);
      return '$startStr - $endStr';
    }
    return _selectedPeriod;
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
              _buildHeader(),
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
                            _buildRouteMap(),
                            _buildStatCards(stats),
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
  // HEADER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHeader() {
    final initials = widget.employeeName
        .split(' ')
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();

    return Container(
      padding: EdgeInsets.only(
        top: 4,
        left: 8,
        right: 16,
        bottom: 8,
      ),
      child: Row(
        children: [
          // Back button
          IconButton(
            onPressed: () => context.pop(),
            icon: const Icon(Icons.arrow_back_ios_new, size: 20),
            color: AppColors.textPrimary,
          ),
          const SizedBox(width: 4),
          // Avatar
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withValues(alpha: 0.12),
            ),
            child: widget.profileImageUrl != null &&
                    widget.profileImageUrl!.isNotEmpty
                ? ClipOval(
                    child: CachedNetworkImage(
                      imageUrl: widget.profileImageUrl!,
                      width: 32,
                      height: 32,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Center(
                        child: Text(
                          initials,
                          style: AppTypography.caption.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  )
                : Center(
                    child: Text(
                      initials,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          // Employee name
          Expanded(
            child: Text(
              widget.employeeName,
              style: AppTypography.headline.copyWith(
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Period selector button
          GestureDetector(
            onTap: _showPeriodPicker,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(AppIcons.calendar, size: 14, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Text(
                    _periodLabel,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(AppIcons.arrow_down, size: 12, color: AppColors.primary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ROUTE MAP
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildRouteMap() {
    if (_isLoadingRoute && _routePoints.isEmpty) {
      return Container(
        height: 190,
        decoration: BoxDecoration(
          color: AppColors.glassPrimary,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.primary,
          ),
        ),
      );
    }

    // FIX 9: skip the route card entirely when there's nothing meaningful
    // to draw (need at least 2 points to render a route). Better than an
    // "empty state" placeholder that just adds noise.
    if (_routePoints.length < 2) {
      return const SizedBox.shrink();
    }

    // Compute bounds
    double minLat = _routePoints.first.latitude;
    double maxLat = _routePoints.first.latitude;
    double minLng = _routePoints.first.longitude;
    double maxLng = _routePoints.first.longitude;
    for (final point in _routePoints) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: 190,
        child: GoogleMap(
          initialCameraPosition: CameraPosition(
            target: LatLng(
              (minLat + maxLat) / 2,
              (minLng + maxLng) / 2,
            ),
            zoom: 14,
          ),
          polylines: {
            Polyline(
              polylineId: const PolylineId('route'),
              points: _routePoints,
              color: AppColors.primary,
              width: 3,
            ),
          },
          markers: _markers,
          onMapCreated: (controller) {
            // Fit camera to bounds after map is created
            Future.delayed(const Duration(milliseconds: 300), () {
              controller.animateCamera(
                CameraUpdate.newLatLngBounds(bounds, 50),
              );
            });
          },
          zoomControlsEnabled: false,
          myLocationButtonEnabled: false,
          myLocationEnabled: false,
          scrollGesturesEnabled: false,
          zoomGesturesEnabled: false,
          tiltGesturesEnabled: false,
          rotateGesturesEnabled: false,
          mapToolbarEnabled: false,
          liteModeEnabled: true,
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STAT CARDS (floating below map)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStatCards(Map<String, String> stats) {
    return Transform.translate(
      offset: const Offset(0, -16),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(blurRadius: 6, color: Colors.black12),
          ],
        ),
        child: Row(
          children: [
            _buildStatItem(
              icon: AppIcons.timer_1,
              color: AppColors.primary,
              label: 'Duration',
              value: stats['duration']!,
            ),
            _statDivider(),
            _buildStatItem(
              icon: AppIcons.routing_2,
              color: AppColors.warning,
              label: 'Distance',
              value: stats['distance']!,
            ),
            _statDivider(),
            _buildStatItem(
              icon: AppIcons.camera,
              color: AppColors.info,
              label: 'Photos',
              value: stats['photos']!,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
  }) {
    return Expanded(
      child: Column(
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
          const SizedBox(height: 6),
          Text(
            value,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppTypography.small.copyWith(
              color: AppColors.textTertiary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _statDivider() {
    return Container(
      width: 1,
      height: 40,
      color: AppColors.divider.withValues(alpha: 0.5),
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
              final previewUrl = (photo.thumbnailUrl?.isNotEmpty == true)
                  ? photo.thumbnailUrl!
                  : (photo.imageUrl.isNotEmpty)
                      ? photo.imageUrl
                      : null;
              final heroTag = 'capture_preview_${photo.id}';
              return GestureDetector(
                onTap: () {
                  context.push('/employee/image-detail', extra: {
                    'imageUrl': photo.imageUrl,
                    'thumbnailUrl': previewUrl ?? '',
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
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 100,
                    height: 100,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Hero(
                          tag: heroTag,
                          child: previewUrl == null
                              ? Container(
                                  color: Colors.grey[300],
                                  child: Icon(Icons.image_not_supported,
                                      color: Colors.grey[500]),
                                )
                              : CachedNetworkImage(
                                  imageUrl: previewUrl,
                                  cacheKey: photo.id,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => Container(
                                    color: AppColors.glassPrimary,
                                    child: const Center(
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ),
                                  errorWidget: (context, url, error) =>
                                      Container(
                                    color: Colors.grey[300],
                                    child: Icon(Icons.broken_image,
                                        color: Colors.grey[500]),
                                  ),
                                ),
                        ),
                        // Time bottom right
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
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                // Category tag bottom left
                                if ((photo.category ?? '').isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 4, vertical: 1),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.black.withValues(alpha: 0.4),
                                      borderRadius: BorderRadius.circular(4),
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
                                Text(
                                  DateFormat('h:mm a')
                                      .format(photo.timestamp),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
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
              );
            },
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTIVITY TIMELINE (SESSION GROUPED)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTimeline(_EmployeeDayActivity dayActivity) {
    final activities = List<ActivityLogModel>.from(dayActivity.activities)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp)); // ascending

    if (activities.isEmpty) {
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
            child: Column(
              children: [
                Icon(
                  AppIcons.activity,
                  size: 36,
                  color: AppColors.textTertiary.withValues(alpha: 0.4),
                ),
                const SizedBox(height: 10),
                Text(
                  'No activity for this period',
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

    // Group activities by session
    final sessions = List<SessionModel>.from(dayActivity.sessions)
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    // If we have sessions, group activities by session
    if (sessions.isNotEmpty) {
      return _buildSessionGroupedTimeline(sessions, activities);
    }

    // Fallback: ungrouped timeline
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

  Widget _buildSessionGroupedTimeline(
    List<SessionModel> sessions,
    List<ActivityLogModel> allActivities,
  ) {
    final widgets = <Widget>[
      Text(
        'Activity Timeline',
        style: AppTypography.bodyMedium.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 14),
    ];

    // Build a map of sessionId -> activities
    final activityBySession = <String?, List<ActivityLogModel>>{};
    for (final activity in allActivities) {
      activityBySession.putIfAbsent(activity.sessionId, () => []);
      activityBySession[activity.sessionId]!.add(activity);
    }

    for (var i = 0; i < sessions.length; i++) {
      final session = sessions[i];
      final sessionNum = i + 1;

      // Session divider label
      final startTimeStr = DateFormat('h:mm a').format(session.startTime);
      final dateStr = DateFormat('MMM d').format(session.startTime);
      String endTimeStr;
      if (session.isAutoEnded) {
        endTimeStr = 'auto-ended';
      } else if (session.endTime != null) {
        endTimeStr = DateFormat('h:mm a').format(session.endTime!);
      } else if (session.isActive) {
        endTimeStr = 'in progress';
      } else {
        endTimeStr = '--';
      }

      widgets.add(
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          margin: EdgeInsets.only(top: i == 0 ? 0 : 12, bottom: 8),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.12),
            ),
          ),
          child: Text(
            'Session $sessionNum \u00B7 $dateStr \u00B7 $startTimeStr \u2192 $endTimeStr',
            style: AppTypography.caption.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ),
      );

      // Activities for this session
      final sessionActivities = activityBySession[session.id] ?? [];
      sessionActivities.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      // FIX 8: warn when a session has no tracking data between start and end.
      // Sessions that show only lifecycle events (start, auto_end, etc.)
      // mean the foreground service was killed before it collected anything,
      // typically due to OEM battery optimization.
      const lifecycleEventTypes = {
        'session_started',
        'session_ended',
        'session_auto_ended',
        'session_resume',
      };
      final hasTrackingData = sessionActivities
          .any((a) => !lifecycleEventTypes.contains(a.type));
      final isCompleted = !session.isActive;
      if (isCompleted && !hasTrackingData) {
        widgets.add(
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppColors.warning.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  AppIcons.warning_2,
                  size: 18,
                  color: AppColors.warning,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'No tracking data for this session. The tracking service '
                    'may have been stopped by the device. Ask the employee '
                    'to check battery optimization settings.',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.warning,
                      fontSize: 11.5,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }

      for (var j = 0; j < sessionActivities.length; j++) {
        final isLastInSession = j == sessionActivities.length - 1;
        final isLastOverall =
            i == sessions.length - 1 && isLastInSession;
        widgets.add(_buildTimelineItem(
          sessionActivities[j],
          isLast: isLastOverall,
        ));
      }
    }

    // Activities not assigned to any session
    final orphanActivities = activityBySession[null] ?? [];
    if (orphanActivities.isNotEmpty) {
      for (var j = 0; j < orphanActivities.length; j++) {
        widgets.add(_buildTimelineItem(
          orphanActivities[j],
          isLast: j == orphanActivities.length - 1,
        ));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
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
        icon = AppIcons.timer_pause;
        color = AppColors.critical;
        break;
      case 'session_auto_ended':
        icon = AppIcons.timer_pause;
        color = AppColors.warning;
        break;
      case 'session_resume':
        icon = AppIcons.refresh_circle;
        // Blue — matches the offline_tracking presence status color.
        color = AppColors.info;
        break;
      case 'location_update':
        icon = AppIcons.location;
        color = AppColors.primary;
        break;
      case 'task_started':
        icon = AppIcons.task_square;
        color = AppColors.primary;
        break;
      case 'task_completed':
        icon = AppIcons.tick_circle;
        color = Color(0xFF7C3AED); // purple
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

    // Resolve display title based on type
    String displayTitle;
    switch (type) {
      case 'session_started':
        displayTitle = 'Session started';
        break;
      case 'session_ended':
        displayTitle = 'Session ended';
        break;
      case 'session_auto_ended':
        displayTitle = 'Session auto-ended';
        break;
      case 'session_resume':
        displayTitle = 'Session resumed';
        break;
      case 'location_update':
        displayTitle = 'Tracked location';
        break;
      case 'photo_captured':
        displayTitle = 'Photo captured';
        break;
      case 'task_completed':
        displayTitle = 'Task completed';
        break;
      default:
        displayTitle = activity.title;
    }

    // Resolve detail text
    final detail = _resolveActivityDetail(activity);

    // Build badge for certain types
    Widget? badge;
    if (type == 'session_auto_ended') {
      badge = Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          'Auto-ended',
          style: AppTypography.small.copyWith(
            color: AppColors.warning,
            fontWeight: FontWeight.w600,
            fontSize: 10,
          ),
        ),
      );
    } else if (type == 'photo_captured') {
      final category = activity.metadata?['category']?.toString() ??
          activity.payload?['category']?.toString();
      if (category != null && category.isNotEmpty) {
        badge = Container(
          margin: const EdgeInsets.only(top: 4),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.info.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            category,
            style: AppTypography.small.copyWith(
              color: AppColors.info,
              fontWeight: FontWeight.w600,
              fontSize: 10,
            ),
          ),
        );
      }
    }

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
            child: GestureDetector(
              onTap: () => _onActivityTap(context, activity),
              child: Container(
                margin: EdgeInsets.only(bottom: isLast ? 0 : 8),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.divider.withValues(alpha: 0.5),
                  ),
                ),
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
                                  displayTitle,
                                  style: AppTypography.bodySmall.copyWith(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                DateFormat('h:mm a')
                                    .format(activity.timestamp),
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
                          if (badge != null) badge,
                        ],
                      ),
                    ),
                  ],
                ),
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
        if (cached != null && !GeocodingCache.isCoordinateString(cached)) {
          return cached;
        }
        // Only trigger geocoding if we haven't already attempted for this
        // coordinate (getCached returns null for never-attempted, returns
        // the coordinate fallback string for failed attempts).
        if (cached == null) {
          GeocodingCache.instance.resolve(lat, lng).then((_) {
            if (mounted) setState(() {});
          });
        }
        return GeocodingCache.formatCoordinates(lat, lng);
      }
      return rawDetail;
    }

    // For task_completed, show the task title from metadata if available
    if (activity.type == 'task_completed') {
      final taskTitle = metadata?['taskTitle']?.toString().trim() ??
          payload?['taskTitle']?.toString().trim() ??
          '';
      if (taskTitle.isNotEmpty) return taskTitle;
    }

    // For session_ended, show duration+distance summary from detail
    if (activity.type == 'session_ended') {
      final raw = activity.detail.trim();
      if (raw.isNotEmpty) return raw;
    }

    // For session_auto_ended, show the reason
    if (activity.type == 'session_auto_ended') {
      final reason = metadata?['reason']?.toString().trim() ??
          payload?['reason']?.toString().trim() ??
          activity.detail.trim();
      if (reason.isNotEmpty) return reason;
    }

    // For session_resume, prefer the structured gap from the payload so the
    // subtitle renders consistently ("Resumed after 23 min gap") regardless
    // of how the log's `detail` was written.
    if (activity.type == 'session_resume') {
      final gapMinutes = (payload?['gapMinutes'] as num?)?.toInt() ??
          (metadata?['gapMinutes'] as num?)?.toInt();
      if (gapMinutes != null && gapMinutes > 0) {
        return 'Resumed after $gapMinutes min gap';
      }
      final raw = activity.detail.trim();
      if (raw.isNotEmpty) return raw;
      return 'Tracking resumed after service was killed';
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
    final sessionEnds = dayActivity.activities
        .where((activity) =>
            activity.type == 'session_ended' ||
            activity.type == 'session_auto_ended')
        .map((activity) => activity.timestamp)
        .toList()
      ..sort();

    String formatDuration(Duration value) {
      if (value == Duration.zero) return '--';
      // Ghost session guard: > 24 hours is suspicious
      if (value.inHours > 24) return '--';
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
            orElse: () => dayActivity.activities.first,
          )
        : null;
    final durationFromLog = _parseDurationFromDetail(fallbackEndLog?.detail);
    final summaryDuration = dayActivity.summary?.duration ?? Duration.zero;
    final liveDuration = _liveDuration(liveStats);

    // Ghost session guard for live duration
    final safeLiveDuration =
        liveDuration.inHours > 24 ? Duration.zero : liveDuration;

    final totalDuration = summaryDuration > Duration.zero
        ? summaryDuration
        : (durationFromLog ?? safeLiveDuration);

    final photoCount = dayActivity.photoCount > 0
        ? dayActivity.photoCount
        : (_isSelectedToday()
            ? (_livePhotosToday(liveStats) > 0
                ? _livePhotosToday(liveStats)
                : dayActivity.photoCount)
            : null);

    // Distance comes from UnifiedDataLayer.getDistance (summed across the
    // selected range in _loadDistanceFromUdl). While that future resolves,
    // show -- instead of a stale inherited value.
    final distanceKm = _distanceKm;
    final distanceLabel = distanceKm == null
        ? '--'
        : (distanceKm > 0 ? '${distanceKm.toStringAsFixed(1)} km' : '--');

    return {
      'duration': formatDuration(totalDuration),
      'photos': '${photoCount ?? dayActivity.photoCount}',
      'distance': distanceLabel,
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

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  bool _isSelectedToday() {
    final today = _normalizeDate(DateTime.now());
    return _isSameDay(_rangeStart, today) &&
        _isSameDay(_normalizeDate(_rangeEnd), today);
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
        // Category filter chips - only show if multiple categories
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
    final previewUrl = (photo.thumbnailUrl?.isNotEmpty == true)
        ? photo.thumbnailUrl!
        : (photo.imageUrl.isNotEmpty)
            ? photo.imageUrl
            : null;
    final heroTag = 'gallery_tile_${photo.id}';

    return GestureDetector(
      onTap: () {
        context.push('/employee/image-detail', extra: {
          'imageUrl': photo.imageUrl,
          'thumbnailUrl': previewUrl ?? '',
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
              child: previewUrl == null
                  ? Container(
                      color: Colors.grey[300],
                      child: Icon(Icons.image_not_supported,
                          color: Colors.grey[500]),
                    )
                  : CachedNetworkImage(
                      imageUrl: previewUrl,
                      cacheKey: photo.id,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        color: AppColors.glassPrimary,
                        child: Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                      errorWidget: (context, url, error) => Container(
                        color: Colors.grey[300],
                        child: Icon(Icons.broken_image,
                            color: Colors.grey[500]),
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
