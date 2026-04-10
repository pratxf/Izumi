import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:izumi/core/ui/app_icons.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';
import '../../models/activity_log_model.dart';
import '../../models/photo_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../repositories/session_repository.dart';
import '../../services/admin_activity_feed_service.dart';
import '../../services/geocoding_cache.dart';
import '../../services/realtime_db_service.dart';
import '../../widgets/glass/gradient_background.dart';
import '../../widgets/navigation/app_header.dart';

/// Employee Detail Screen — Live View
/// Shows real-time employee location on map, stats, activity feed, and photos.
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
  // ── Constants ──
  static const int _collapsedPhotoCount = 6;
  static const int _photoPreviewLimit = 24;
  static const Duration _activityWindow = Duration(hours: 24);

  // ── Services ──
  final AdminActivityFeedService _feedService = AdminActivityFeedService();
  final SessionRepository _sessionRepository = SessionRepository();
  final RealtimeDbService _realtimeDbService = RealtimeDbService();

  // ── State ──
  String? _employeeId;
  List<ActivityLogModel> _activityLogs = [];
  List<PhotoModel> _photos = [];
  List<String> _activeSessionIds = [];
  bool _activityLoading = true;
  bool _photosLoading = true;
  bool _showAllPhotos = false;

  // ── Map state ──
  GoogleMapController? _mapController;
  Set<Polyline> _polylines = {};
  Set<Marker> _markers = {};
  List<LatLng> _routePoints = [];
  LatLng? _liveLatLng;

  // ── Subscriptions & timers ──
  StreamSubscription<AdminRecentActivityFeedData>? _feedSubscription;
  StreamSubscription<dynamic>? _liveLocationSubscription;
  Timer? _warmupTimer;
  Timer? _liveDurationTimer;

  // ── Live duration ──
  String _liveDurationDisplay = '--:--:--';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Ensure DashboardProvider is initialized so the stats row
      // (distance/duration/photos) has RTDB streams running, regardless
      // of whether the user visited the dashboard tab first.
      final dashboardProvider = context.read<DashboardProvider>();
      final enterpriseId = context.read<AuthProvider>().enterpriseId;
      if (!dashboardProvider.isInitialized && enterpriseId != null) {
        dashboardProvider.initDashboard(enterpriseId);
      }

      final id = GoRouterState.of(context).pathParameters['id'];
      if (id != null) {
        _employeeId = id;
        _startRecentFeed(id);
        _startLiveLocationStream(id);
        _startLiveDurationTimer();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Firestore streams auto-deliver on resume; no restart needed.
  }

  // ── Feed ──

  void _startRecentFeed(String employeeId) {
    _feedSubscription?.cancel();
    _warmupTimer?.cancel();
    if (mounted) {
      setState(() {
        _activityLoading = true;
        _photosLoading = true;
      });
    }

    final employees = context.read<DashboardProvider>().employees;
    final linkedIds = employees.isEmpty
        ? [employeeId]
        : _feedService.resolveLinkedEmployeeIds(employeeId, employees);
    final queryIds = linkedIds.isEmpty ? [employeeId] : linkedIds;

    _warmupTimer = Timer(const Duration(seconds: 6), () {
      if (mounted && _activityLoading) {
        setState(() {
          _activityLoading = false;
          _photosLoading = false;
        });
      }
    });

    _feedSubscription = _feedService
        .streamRecentFeed(
          linkedEmployeeIds: queryIds,
          window: _activityWindow,
          photoLimit: _photoPreviewLimit,
        )
        .listen((feed) {
      if (!mounted) return;

      final hasData = feed.activities.isNotEmpty || feed.photos.isNotEmpty;
      final doneLoading = hasData || !_activityLoading;

      final newSessionIds = feed.activeSessionIds;
      final sessionIdsChanged =
          newSessionIds.join(',') != _activeSessionIds.join(',');

      setState(() {
        _activityLogs = feed.activities;
        _photos = feed.photos;
        _activeSessionIds = newSessionIds;
        if (doneLoading) {
          _warmupTimer?.cancel();
          _activityLoading = false;
          _photosLoading = false;
        }
        if (_showAllPhotos && _photos.length <= _collapsedPhotoCount) {
          _showAllPhotos = false;
        }
      });

      if (sessionIdsChanged) {
        _loadRouteFromSessions(newSessionIds);
      }

      // Fallback: if no RTDB live location and no route, use last
      // location_update from the activity feed for the map marker
      if (_liveLatLng == null && _routePoints.isEmpty) {
        _applyFeedLocationFallback(feed.activities);
      }
    }, onError: (_) {
      if (!mounted) return;
      _warmupTimer?.cancel();
      setState(() {
        _activityLoading = false;
        _photosLoading = false;
      });
    });
  }

  // ── Map: Route polyline from session locations ──

  Future<void> _loadRouteFromSessions(List<String> sessionIds) async {
    if (sessionIds.isEmpty) {
      if (mounted) {
        setState(() {
          _routePoints = [];
          _polylines = {};
          _markers = {};
        });
        _fitMapToLiveLocation();
      }
      return;
    }

    try {
      final allPoints = <LatLng>[];
      for (final sessionId in sessionIds) {
        final locations =
            await _sessionRepository.getSessionLocations(sessionId);
        locations.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        for (final loc in locations) {
          if (loc.latitude != 0.0 || loc.longitude != 0.0) {
            allPoints.add(LatLng(loc.latitude, loc.longitude));
          }
        }
      }

      if (!mounted) return;

      final markers = <Marker>{};
      if (allPoints.isNotEmpty) {
        markers.add(Marker(
          markerId: const MarkerId('session_start'),
          position: allPoints.first,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: const InfoWindow(title: 'Session Start'),
        ));
      }
      if (_liveLatLng != null) {
        markers.add(Marker(
          markerId: const MarkerId('live_location'),
          position: _liveLatLng!,
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
          infoWindow: const InfoWindow(title: 'Current Location'),
        ));
      }

      final polylines = <Polyline>{};
      final polylinePoints = [...allPoints];
      if (_liveLatLng != null) {
        polylinePoints.add(_liveLatLng!);
      }
      if (polylinePoints.length >= 2) {
        polylines.add(Polyline(
          polylineId: const PolylineId('route'),
          points: polylinePoints,
          color: AppColors.primary,
          width: 4,
        ));
      }

      setState(() {
        _routePoints = allPoints;
        _polylines = polylines;
        _markers = markers;
      });

      _fitMapBounds();
    } catch (_) {
      if (mounted) {
        setState(() {});
      }
    }
  }

  void _fitMapBounds() {
    if (_mapController == null) return;

    final allPoints = [..._routePoints];
    if (_liveLatLng != null) allPoints.add(_liveLatLng!);

    if (allPoints.length < 2) {
      _fitMapToLiveLocation();
      return;
    }

    double minLat = allPoints.first.latitude;
    double maxLat = allPoints.first.latitude;
    double minLng = allPoints.first.longitude;
    double maxLng = allPoints.first.longitude;
    for (final p in allPoints) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        40,
      ),
    );
  }

  void _fitMapToLiveLocation() {
    if (_mapController == null) return;
    final target = _liveLatLng ?? const LatLng(20.5937, 78.9629);
    _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: target, zoom: 14),
      ),
    );
  }

  // ── Fallback: last location from activity feed ──

  void _applyFeedLocationFallback(List<ActivityLogModel> activities) {
    // Find the most recent location_update in the feed
    for (final log in activities) {
      if (log.type != 'location_update') continue;
      final lat = (log.metadata?['latitude'] as num?)?.toDouble();
      final lng = (log.metadata?['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null || (lat == 0 && lng == 0)) continue;

      final fallback = LatLng(lat, lng);
      setState(() {
        _liveLatLng = fallback;
        _markers = <Marker>{
          ..._markers.where((m) => m.markerId.value != 'last_known'),
          Marker(
            markerId: const MarkerId('last_known'),
            position: fallback,
            icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueAzure),
            infoWindow: const InfoWindow(title: 'Last Known Location'),
          ),
        };
      });
      _fitMapToLiveLocation();
      return;
    }
  }

  // ── RTDB live location stream ──

  void _startLiveLocationStream(String employeeId) {
    final enterpriseId =
        context.read<AuthProvider>().enterpriseId ?? '';
    if (enterpriseId.isEmpty) return;

    _liveLocationSubscription?.cancel();
    _liveLocationSubscription = _realtimeDbService
        .streamUserLiveLocation(enterpriseId, employeeId)
        .listen((event) {
      final data = event.snapshot.value;
      if (data == null || data is! Map) return;
      final lat = (data['latitude'] as num?)?.toDouble();
      final lng = (data['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) return;

      final newLive = LatLng(lat, lng);
      if (!mounted) return;

      setState(() {
        _liveLatLng = newLive;

        // Replace markers with a new Set so GoogleMap detects the change
        final updatedMarkers = <Marker>{
          ..._markers.where((m) => m.markerId.value != 'live_location'),
          Marker(
            markerId: const MarkerId('live_location'),
            position: newLive,
            icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueViolet),
            infoWindow: const InfoWindow(title: 'Current Location'),
          ),
        };
        _markers = updatedMarkers;

        // Replace polylines with a new Set so GoogleMap detects the change
        if (_routePoints.isNotEmpty) {
          final polylinePoints = [..._routePoints, newLive];
          _polylines = {
            Polyline(
              polylineId: const PolylineId('route'),
              points: polylinePoints,
              color: AppColors.primary,
              width: 4,
            ),
          };
        }
      });

      // Move the camera to follow the updated location
      if (_routePoints.isNotEmpty) {
        _fitMapBounds();
      } else {
        _fitMapToLiveLocation();
      }
    });
  }

  // ── Live duration timer ──

  void _startLiveDurationTimer() {
    _liveDurationTimer?.cancel();
    _liveDurationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _employeeId == null) return;
      final stats =
          context.read<DashboardProvider>().getEmployeeStats(_employeeId!);
      final startMs = (stats?['sessionStartTimeMs'] as num?)?.toInt();
      if (startMs == null || startMs == 0) {
        if (_liveDurationDisplay != '--:--:--') {
          setState(() => _liveDurationDisplay = '--:--:--');
        }
        return;
      }
      final elapsed = DateTime.now()
          .difference(DateTime.fromMillisecondsSinceEpoch(startMs));
      // Ghost session guard: if sessionStartTimeMs is > 16h old,
      // it's stale RTDB data from a dead session — fall back to
      // the pre-computed sessionDuration from the tracking handler.
      const maxSessionSecs = 16 * 3600; // 16 hours
      int totalSecs;
      if (elapsed.inSeconds >= maxSessionSecs) {
        // Use the sessionDuration field written by the tracking handler
        totalSecs = (stats?['sessionDuration'] as num?)?.toInt() ?? 0;
        if (totalSecs == 0) {
          if (_liveDurationDisplay != '--:--:--') {
            setState(() => _liveDurationDisplay = '--:--:--');
          }
          return;
        }
      } else {
        totalSecs = elapsed.inSeconds.clamp(0, maxSessionSecs);
      }
      final h = (totalSecs ~/ 3600).toString().padLeft(2, '0');
      final m = ((totalSecs % 3600) ~/ 60).toString().padLeft(2, '0');
      final s = (totalSecs % 60).toString().padLeft(2, '0');
      final display = '$h:$m:$s';
      if (display != _liveDurationDisplay) {
        setState(() => _liveDurationDisplay = display);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _warmupTimer?.cancel();
    _feedSubscription?.cancel();
    _liveLocationSubscription?.cancel();
    _liveDurationTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final dashboardProvider = context.watch<DashboardProvider>();
    final status = _employeeId != null
        ? dashboardProvider.getEmployeeStatus(_employeeId!)
        : (widget.isActive ? 'active' : 'offline');
    final stats = _employeeId != null
        ? dashboardProvider.getEmployeeStats(_employeeId!)
        : null;

    final distanceKm = (stats?['distance'] as num?)?.toDouble() ?? 0.0;
    final distanceDisplay = '${distanceKm.toStringAsFixed(1)} km';
    final photoCount = _photos.length;

    return Scaffold(
      body: GradientBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // ── Header with status badge ──
              _buildHeader(context, status),

              // ── Scrollable content ──
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Mini route map
                      _buildMiniMap(),
                      const SizedBox(height: 16),

                      // Live stats row
                      _buildLiveStatsRow(
                        distanceDisplay,
                        photoCount,
                      ),
                      const SizedBox(height: 16),

                      // Action buttons
                      _buildActionButtons(context),
                      const SizedBox(height: 28),

                      // Live activity feed
                      Text(
                        'Live activity feed',
                        style: AppTypography.h3.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildActivityFeed(),
                      const SizedBox(height: 28),

                      // Photos section
                      _buildPhotosSection(),
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
  //  HEADER with status pill
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHeader(BuildContext context, String status) {
    return AppHeader(
      title: widget.name,
      type: AppHeaderType.secondary,
      showAvatar: false,
      actions: [_buildStatusPill(status)],
    );
  }

  Widget _buildStatusPill(String status) {
    Color bgColor;
    Color textColor;
    String label;

    switch (status) {
      case 'active':
        bgColor = AppColors.badgeActiveBackground;
        textColor = AppColors.success;
        label = 'Active';
        break;
      case 'signal_lost':
        bgColor = AppColors.badgeWarning;
        textColor = AppColors.warning;
        label = 'Signal Lost';
        break;
      default:
        bgColor = AppColors.badgeOfflineBackground;
        textColor = AppColors.textTertiary;
        label = 'Offline';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: AppTypography.caption.copyWith(
          color: textColor,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  MINI ROUTE MAP
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMiniMap() {
    final initialTarget = _liveLatLng ?? const LatLng(20.5937, 78.9629);

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: 200,
        width: double.infinity,
        child: GoogleMap(
          initialCameraPosition: CameraPosition(
            target: initialTarget,
            zoom: 14,
          ),
          onMapCreated: (controller) {
            _mapController = controller;
            // Fit once map is ready
            if (_routePoints.isNotEmpty) {
              _fitMapBounds();
            } else if (_liveLatLng != null) {
              _fitMapToLiveLocation();
            }
          },
          polylines: _polylines,
          markers: _markers,
          myLocationEnabled: false,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          compassEnabled: false,
          rotateGesturesEnabled: false,
          scrollGesturesEnabled: false,
          tiltGesturesEnabled: false,
          zoomGesturesEnabled: false,
          liteModeEnabled: false,
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  LIVE STATS ROW (3 cards)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildLiveStatsRow(String distance, int photoCount) {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            value: _liveDurationDisplay,
            label: 'Duration',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildStatCard(
            value: distance,
            label: 'Distance',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildStatCard(
            value: '$photoCount',
            label: 'Photos',
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({required String value, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.glassBorder,
          width: 0.5,
        ),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  ACTION BUTTONS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildActionButtons(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _buildActionButton(
            icon: AppIcons.task_square,
            label: 'Assign task',
            onTap: () => context.push('/admin/create-task', extra: {
              'initialAssigneeName': widget.name,
            }),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildActionButton(
            icon: AppIcons.gallery,
            label: 'View photos',
            onTap: () => context.push('/admin/employee-images', extra: {
              'employeeId': _employeeId,
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.primary),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppColors.primary, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  ACTIVITY FEED
  // ═══════════════════════════════════════════════════════════════════════════

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
              Icon(AppIcons.activity, size: 48, color: AppColors.textTertiary),
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

    // Sort descending (newest first)
    final sorted = List<ActivityLogModel>.from(_activityLogs)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return Column(
      children: List.generate(sorted.length, (index) {
        final log = sorted[index];
        final isLast = index == sorted.length - 1;

        IconData icon;
        Color color;
        switch (log.type) {
          case 'session_start':
          case 'session_started':
            icon = AppIcons.clock;
            color = AppColors.success;
            break;
          case 'session_end':
          case 'session_ended':
          case 'session_auto_ended':
            icon = AppIcons.close_circle;
            color = AppColors.critical;
            break;
          case 'location_update':
            icon = AppIcons.location;
            color = AppColors.primary;
            break;
          case 'photo_captured':
            icon = AppIcons.camera;
            color = AppColors.primary;
            break;
          case 'task_started':
          case 'task_completed':
            icon = AppIcons.tick_circle;
            color = const Color(0xFF7C3AED); // purple
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
          log: log,
        );
      }),
    );
  }

  Widget _buildTimelineItem({
    required IconData icon,
    required Color color,
    required String title,
    required String time,
    required String description,
    required bool isLast,
    required ActivityLogModel log,
  }) {
    final showMap = log.type == 'location_update';

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline column: icon + connecting line
          SizedBox(
            width: 36,
            child: Column(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 16),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: AppColors.glassBorder,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: AppTypography.bodyMedium.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (showMap)
                        GestureDetector(
                          onTap: () => _openMaps(description),
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: AppColors.glassPrimary,
                              borderRadius: BorderRadius.circular(8),
                              border:
                                  Border.all(color: AppColors.glassBorder),
                            ),
                            child: const Icon(
                              AppIcons.map_1,
                              size: 13,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      if (showMap) const SizedBox(width: 6),
                      Text(
                        time,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textTertiary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  PHOTOS SECTION
  // ═══════════════════════════════════════════════════════════════════════════

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
                  style: const TextStyle(
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
          LayoutBuilder(
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
    final displayUrl = (photo.thumbnailUrl?.isNotEmpty == true)
        ? photo.thumbnailUrl!
        : (photo.imageUrl.isNotEmpty)
            ? photo.imageUrl
            : null;
    final heroTag = 'detail_photo_${photo.id}';

    return GestureDetector(
      onTap: () {
        if (photo.imageUrl.isNotEmpty) {
          precacheImage(NetworkImage(photo.imageUrl), context);
        }
        context.push('/employee/image-detail', extra: {
          'imageUrl': photo.imageUrl,
          'thumbnailUrl': displayUrl ?? '',
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
                child: displayUrl == null
                    ? Container(
                        color: Colors.grey[300],
                        child: Icon(Icons.image_not_supported,
                            color: Colors.grey[500]),
                      )
                    : CachedNetworkImage(
                        imageUrl: displayUrl,
                        cacheKey: photo.id,
                        fit: BoxFit.cover,
                        placeholder: (context, url) =>
                            Container(color: Colors.grey[200]),
                        errorWidget: (context, url, error) => Container(
                          color: Colors.grey[300],
                          child: Icon(Icons.broken_image,
                              color: Colors.grey[500]),
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

  // ═══════════════════════════════════════════════════════════════════════════
  //  HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  String _resolveActivityDetail(ActivityLogModel log) {
    if (log.type == 'location_update') {
      final metadata = log.metadata;
      final payload = log.payload;
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
