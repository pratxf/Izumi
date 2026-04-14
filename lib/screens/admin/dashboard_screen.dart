import 'dart:async';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';
import '../../core/ui/app_icons.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../services/geocoding_cache.dart';
import '../../widgets/navigation/app_header.dart';

/// Dashboard Screen - Enterprise Admin
/// Full-screen Google Map with floating header, search bar, and draggable
/// bottom sheet listing all employees with live status, location, and stats.
class DashboardScreen extends StatefulWidget {
  final VoidCallback? onAvatarTap;

  const DashboardScreen({super.key, this.onAvatarTap});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  // Controllers
  GoogleMapController? _mapController;
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _employeeScrollController = ScrollController();

  // State
  String _searchQuery = '';
  String _statusFilter = 'all';
  String? _highlightedEmployeeId;
  bool _hasUnread = false;
  bool _initialCameraDone = false;
  String? _lastLoadedEnterpriseId;

  // Subscriptions
  StreamSubscription? _unreadSub;

  // Marker cache: "initials_colorValue" -> BitmapDescriptor
  final Map<String, BitmapDescriptor> _markerCache = {};
  Set<Marker> _markers = {};

  // Keep track of last data hash to avoid redundant marker rebuilds
  int _lastMarkerDataHash = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDashboard();
      _listenUnread();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadDashboard();
    }
  }

  void _loadDashboard() {
    final authProvider = context.read<AuthProvider>();
    final enterpriseId = authProvider.enterpriseId;
    if (enterpriseId != null && enterpriseId != _lastLoadedEnterpriseId) {
      _lastLoadedEnterpriseId = enterpriseId;
      context.read<DashboardProvider>().initDashboard(enterpriseId);
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
    _mapController?.dispose();
    _sheetController.dispose();
    _searchController.dispose();
    _employeeScrollController.dispose();
    _unreadSub?.cancel();
    super.dispose();
  }

  // ===========================================================================
  // Marker generation
  // ===========================================================================

  Future<BitmapDescriptor> _createMarker(String initials, Color color) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const size = 48.0;
    // White border ring
    canvas.drawCircle(
      const Offset(size / 2, size / 2),
      size / 2,
      Paint()..color = Colors.white,
    );
    // Colored circle
    canvas.drawCircle(
      const Offset(size / 2, size / 2),
      size / 2 - 2,
      Paint()..color = color,
    );
    // Initials text
    final textPainter = TextPainter(
      text: TextSpan(
        text: initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      Offset(
        (size - textPainter.width) / 2,
        (size - textPainter.height) / 2,
      ),
    );
    final picture = recorder.endRecording();
    final img = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
  }

  Future<void> _buildMarkers(DashboardProvider dp) async {
    // Quick hash to skip redundant rebuilds
    final hash = Object.hashAll([
      dp.employees.length,
      dp.liveLocationData.hashCode,
      dp.presenceData.hashCode,
    ]);
    if (hash == _lastMarkerDataHash) return;
    _lastMarkerDataHash = hash;

    final newMarkers = <Marker>{};
    final boundsPoints = <LatLng>[];

    for (final employee in dp.employees) {
      final status = dp.getEmployeeStatus(employee.id);
      if (status == 'offline') continue;

      final loc = dp.getEmployeeLocation(employee.id);
      final lat = (loc?['latitude'] as num?)?.toDouble();
      final lng = (loc?['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;

      final color = status == 'active'
          ? const Color(0xFF4F46E5) // indigo
          : const Color(0xFFD97706); // amber

      final cacheKey = '${employee.initials}_${color.toARGB32()}';
      if (!_markerCache.containsKey(cacheKey)) {
        _markerCache[cacheKey] = await _createMarker(employee.initials, color);
      }

      final position = LatLng(lat, lng);
      boundsPoints.add(position);

      newMarkers.add(
        Marker(
          markerId: MarkerId(employee.id),
          position: position,
          icon: _markerCache[cacheKey]!,
          onTap: () => _onMarkerTapped(employee),
        ),
      );
    }

    if (!mounted) return;
    setState(() => _markers = newMarkers);

    // Fit camera to bounds on first load only — after stream data arrives
    if (!_initialCameraDone &&
        boundsPoints.isNotEmpty &&
        _mapController != null) {
      _initialCameraDone = true;
      _fitMapToMarkers(boundsPoints);
    }
  }

  void _fitMapToMarkers(List<LatLng> positions) {
    if (positions.isEmpty || _mapController == null) return;
    try {
      if (positions.length == 1) {
        _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(positions.first, 14),
        );
        return;
      }
      double minLat = positions.first.latitude;
      double maxLat = positions.first.latitude;
      double minLng = positions.first.longitude;
      double maxLng = positions.first.longitude;
      for (final p in positions) {
        if (p.latitude < minLat) minLat = p.latitude;
        if (p.latitude > maxLat) maxLat = p.latitude;
        if (p.longitude < minLng) minLng = p.longitude;
        if (p.longitude > maxLng) maxLng = p.longitude;
      }
      final bounds = LatLngBounds(
        southwest: LatLng(minLat, minLng),
        northeast: LatLng(maxLat, maxLng),
      );
      _mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 60),
      );
    } catch (e) {
      debugPrint('[DashboardScreen] map bounds error: $e');
    }
  }

  void _onMarkerTapped(UserModel employee) {
    final dp = context.read<DashboardProvider>();
    final loc = dp.getEmployeeLocation(employee.id);
    final lat = (loc?['latitude'] as num?)?.toDouble();
    final lng = (loc?['longitude'] as num?)?.toDouble();

    if (lat != null && lng != null) {
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(lat, lng), 16),
      );
    }

    setState(() => _highlightedEmployeeId = employee.id);

    _sheetController.animateTo(
      0.92,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
    );
  }

  // ===========================================================================
  // Address resolution
  // ===========================================================================

  String _resolveAddress(
      String rawAddress, Map<String, dynamic>? locationData) {
    if (!GeocodingCache.isCoordinateString(rawAddress)) return rawAddress;
    final lat = (locationData?['latitude'] as num?)?.toDouble();
    final lng = (locationData?['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null) return rawAddress;
    final cached = GeocodingCache.instance.getCached(lat, lng);
    if (cached != null) return cached;
    GeocodingCache.instance.resolve(lat, lng).then((_) {
      if (mounted) setState(() {});
    });
    return '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
  }

  // ===========================================================================
  // Filtering & sorting
  // ===========================================================================

  List<UserModel> _filteredEmployees(DashboardProvider dp) {
    List<UserModel> list = _searchQuery.isEmpty
        ? List<UserModel>.from(dp.employees)
        : dp.searchEmployees(_searchQuery);

    if (_statusFilter != 'all') {
      list = list
          .where((e) => dp.getEmployeeStatus(e.id) == _statusFilter)
          .toList();
    }

    list.sort((a, b) {
      const order = {
        'active': 0,
        'break': 1,
        'offline': 2,
      };
      final sa = order[dp.getEmployeeStatus(a.id)] ?? 2;
      final sb = order[dp.getEmployeeStatus(b.id)] ?? 2;
      return sa.compareTo(sb);
    });

    return list;
  }

  // ===========================================================================
  // Status helpers
  // ===========================================================================

  Color _statusDotColor(String status) {
    switch (status) {
      case 'active':
        return AppColors.success;
      default:
        return AppColors.textDisabled;
    }
  }

  Color _statusBadgeColor(String status) {
    switch (status) {
      case 'active':
        return AppColors.success;
      default:
        return AppColors.textTertiary;
    }
  }

  Color _statusBadgeBg(String status) {
    switch (status) {
      case 'active':
        return AppColors.badgeActiveBackground;
      default:
        return AppColors.badgeOfflineBackground;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'active':
        return 'Active';
      default:
        return 'Offline';
    }
  }

  // ===========================================================================
  // Build
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    final dp = context.watch<DashboardProvider>();
    final authProvider = context.watch<AuthProvider>();
    final topPadding = MediaQuery.of(context).padding.top;

    // Rebuild markers after frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _buildMarkers(dp);
    });

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // ---- Google Map (full screen base layer) ----
          GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: LatLng(20.5937, 78.9629), // India center fallback
              zoom: 5,
            ),
            markers: _markers,
            mapType: MapType.normal,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            onMapCreated: (controller) {
              _mapController = controller;
            },
          ),

          // ---- Floating AppHeader ----
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AppHeader(
              title: 'Dashboard',
              showLeading: false,
              showNotification: true,
              hasUnread: _hasUnread,
              onNotificationTap: () =>
                  context.push('/employee/notifications'),
              showAvatar: true,
              avatarUrl: authProvider.currentUser?.profileImageUrl,
              onAvatarTap: widget.onAvatarTap ??
                  () => context.push('/admin/profile'),
            ),
          ),

          // ---- Floating search bar ----
          Positioned(
            top: topPadding + 64,
            left: 16,
            right: 16,
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _searchQuery = v.trim()),
                style: AppTypography.bodyMedium,
                decoration: InputDecoration(
                  hintText: 'Search employees...',
                  hintStyle: AppTypography.bodySmall.copyWith(
                    color: AppColors.textDisabled,
                  ),
                  prefixIcon: const Icon(
                    AppIcons.search_normal,
                    size: 20,
                    color: AppColors.textTertiary,
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? GestureDetector(
                          onTap: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                          child: const Icon(
                            AppIcons.close_circle,
                            size: 18,
                            color: AppColors.textDisabled,
                          ),
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 13,
                  ),
                ),
              ),
            ),
          ),

          // ---- Draggable bottom sheet ----
          DraggableScrollableSheet(
            controller: _sheetController,
            initialChildSize: 0.38,
            minChildSize: 0.12,
            maxChildSize: 0.92,
            snap: true,
            snapSizes: const [0.12, 0.38, 0.92],
            builder: (context, scrollController) {
              final employees = _filteredEmployees(dp);
              return Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(20)),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x1A000000),
                      blurRadius: 16,
                      offset: Offset(0, -4),
                    ),
                  ],
                ),
                child: ListView(
                  controller: scrollController,
                  padding: EdgeInsets.zero,
                  children: [
                    // Drag handle
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(top: 10, bottom: 8),
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color:
                              AppColors.textDisabled.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),

                    // Status overview pills
                    _buildStatusPills(dp),
                    const SizedBox(height: 8),

                    const SizedBox(height: 4),

                    // Employee list
                    if (dp.isLoading)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: AppColors.primary,
                            strokeWidth: 2,
                          ),
                        ),
                      )
                    else if (employees.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Center(
                          child: Text(
                            'No employees found',
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ),
                      )
                    else
                      ...employees
                          .map((e) => _buildEmployeeCard(dp, e)),

                    // Bottom safe area
                    SizedBox(
                      height:
                          MediaQuery.of(context).padding.bottom + 16,
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // Status pills row
  // ===========================================================================

  Widget _buildStatusPills(DashboardProvider dp) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _statusPill(
            label: 'Active',
            count: dp.activeCount,
            color: AppColors.primary,
            bgColor: AppColors.primary.withValues(alpha: 0.12),
            filterValue: 'active',
          ),
          const SizedBox(width: 8),
          _statusPill(
            label: 'Offline',
            count: dp.offlineCount,
            color: AppColors.textTertiary,
            bgColor: AppColors.surfaceMuted,
            filterValue: 'offline',
          ),
        ],
      ),
    );
  }

  Widget _statusPill({
    required String label,
    required int count,
    required Color color,
    required Color bgColor,
    required String filterValue,
  }) {
    final isSelected = _statusFilter == filterValue;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _statusFilter = isSelected ? 'all' : filterValue;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.18) : bgColor,
            borderRadius: BorderRadius.circular(12),
            border: isSelected
                ? Border.all(color: color.withValues(alpha: 0.4))
                : null,
          ),
          child: Column(
            children: [
              Text(
                '$count',
                style: AppTypography.h3.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: AppTypography.small.copyWith(
                  color: color,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // Filter chips
  // ===========================================================================

  // ===========================================================================
  // Employee card
  // ===========================================================================

  Widget _buildEmployeeCard(DashboardProvider dp, UserModel employee) {
    final status = dp.getEmployeeStatus(employee.id);
    final isOnClock = dp.isEmployeeOnClock(employee.id);
    final location = dp.getEmployeeLocation(employee.id);
    final rawAddress = location?['address']?.toString() ?? '';
    final address = rawAddress.isNotEmpty
        ? _resolveAddress(rawAddress, location)
        : 'No location data';

    final isHighlighted = _highlightedEmployeeId == employee.id;

    return GestureDetector(
      onTap: () {
        context.push(
          '/admin/employee/${employee.id}',
          extra: {
            'name': employee.name,
            'isActive': isOnClock,
            'avatarUrl': employee.profileImageUrl ??
                'https://i.pravatar.cc/150?img=11',
          },
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isHighlighted
                ? AppColors.primary
                : const Color(0xFFE5E7EB),
            width: isHighlighted ? 1.5 : 0.5,
          ),
          boxShadow: isHighlighted
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            // Avatar with status dot
            SizedBox(
              width: 44,
              height: 44,
              child: Stack(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        employee.initials,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: _statusDotColor(status),
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),

            // Name and address
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    employee.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    address,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Status badge
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 5,
              ),
              decoration: BoxDecoration(
                color: _statusBadgeBg(status),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _statusLabel(status),
                style: AppTypography.small.copyWith(
                  color: _statusBadgeColor(status),
                  fontWeight: FontWeight.w500,
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
