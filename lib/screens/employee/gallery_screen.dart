import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:izumi/core/ui/app_icons.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';
import '../../models/photo_model.dart';
import '../../models/upload_status.dart';
import '../../providers/auth_provider.dart';
import '../../providers/photo_provider.dart';
import '../../providers/team_provider.dart';
import '../../offline_queue/offline_job.dart';
import '../../offline_queue/offline_queue_manager.dart';
import '../../widgets/glass/gradient_background.dart';
import '../../widgets/navigation/app_header.dart';
import '../../widgets/inputs/text_input_field.dart';
import '../../widgets/photo_tile_image.dart';

/// Employee Gallery Screen - Photo gallery with glassmorphism design
class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  final _searchController = TextEditingController();
  bool _initialized = false;
  String _searchQuery = '';
  DateTime? _selectedDate; // null = all dates
  bool _isTeamLead = false;
  StreamSubscription<OfflineQueueJobEvent>? _queueEventsSub;
  AuthProvider? _authListenerTarget;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initProvider();
      // Subscribe to auth changes so a late background claims refresh
      // (fast-path boot read stale claims, then _backgroundRefresh bumped
      // roles to team_lead) flips us into team mode without requiring the
      // user to back out and re-enter the screen.
      if (!mounted) return;
      final auth = context.read<AuthProvider>();
      _authListenerTarget = auth;
      auth.addListener(_onAuthRolesChanged);
    });
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
      });
    });
    // Listen for upload errors to show in UI
    _queueEventsSub =
        OfflineQueueManager.instance.events.listen((event) {
      if (event.type == OfflineJobType.photo &&
          event.status == UploadStatus.error &&
          mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: ${event.error}'),
            duration: const Duration(seconds: 5),
            backgroundColor: AppColors.critical,
          ),
        );
      }
    });
  }

  /// When claims drift-corrects in the background, re-run init so the
  /// screen switches from personal → team mode (or back) automatically.
  void _onAuthRolesChanged() {
    if (!mounted) return;
    final auth = _authListenerTarget;
    if (auth == null) return;
    if (auth.isTeamLead != _isTeamLead) {
      _initialized = false;
      _initProvider();
    }
  }

  void _initProvider() async {
    if (_initialized) return;
    _initialized = true;
    final auth = context.read<AuthProvider>();
    final userId =
        auth.currentUser?.id ?? FirebaseAuth.instance.currentUser?.uid ?? '';
    debugPrint('[GalleryScreen] _initProvider: userId=$userId');
    if (userId.isEmpty) {
      debugPrint('[GalleryScreen] ERROR: userId is empty, cannot load photos');
      return;
    }

    final isTeamLead = auth.isTeamLead;
    setState(() => _isTeamLead = isTeamLead);

    final teamProvider = context.read<TeamProvider>();
    final photoProvider = context.read<PhotoProvider>();

    // Retry any stuck uploads when gallery is opened
    OfflineQueueManager.instance.retryAllNow();

    if (isTeamLead) {
      // Ensure team data is loaded
      if (teamProvider.group == null) {
        final enterpriseId = auth.enterpriseId ?? '';
        if (enterpriseId.isNotEmpty) {
          await teamProvider.initTeam(enterpriseId, userId);
        }
      }
      if (!mounted) return;
      final memberIds = teamProvider.group?.memberIds ?? [];
      if (memberIds.isNotEmpty) {
        // Include the team lead's own ID
        final allIds =
            memberIds.contains(userId) ? memberIds : [...memberIds, userId];
        photoProvider.streamTeamPhotos(
          allIds,
          enterpriseId: auth.enterpriseId ?? '',
        );
      } else {
        // Fallback: show only own photos
        photoProvider.streamPhotos(
          userId,
          enterpriseId: auth.enterpriseId ?? '',
        );
      }
    } else {
      photoProvider.streamPhotos(
        userId,
        enterpriseId: auth.enterpriseId ?? '',
      );
    }
  }

  @override
  void dispose() {
    _authListenerTarget?.removeListener(_onAuthRolesChanged);
    _queueEventsSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// Resolve the employee name for a photo (team lead sees member names)
  String _resolveCapturedBy(PhotoModel photo, AuthProvider auth) {
    if (!_isTeamLead) return auth.currentUser?.name ?? 'You';
    if (photo.employeeId == (auth.currentUser?.id ?? '')) {
      return auth.currentUser?.name ?? 'You';
    }
    final teamProvider = context.read<TeamProvider>();
    final member = teamProvider.teamMembers
        .where((m) => m.id == photo.employeeId)
        .firstOrNull;
    return member?.name ?? 'Team Member';
  }

  /// Filter photos by selected date (client-side)
  List<PhotoModel> _applyDateFilter(List<PhotoModel> photos) {
    if (_selectedDate == null) return photos;
    final start =
        DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day);
    final end = start.add(const Duration(days: 1));
    return photos
        .where((p) =>
            p.timestamp
                .isAfter(start.subtract(const Duration(milliseconds: 1))) &&
            p.timestamp.isBefore(end))
        .toList();
  }

  /// Group photos by date (same logic as PhotoProvider)
  Map<String, List<PhotoModel>> _groupByDate(List<PhotoModel> photos) {
    final Map<String, List<PhotoModel>> grouped = {};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    for (final photo in photos) {
      final photoDate = DateTime(
          photo.timestamp.year, photo.timestamp.month, photo.timestamp.day);
      String dateKey;
      if (photoDate == today) {
        dateKey = 'Today';
      } else if (photoDate == yesterday) {
        dateKey = 'Yesterday';
      } else {
        dateKey = DateFormat('dd MMM yyyy').format(photo.timestamp);
      }
      grouped.putIfAbsent(dateKey, () => []).add(photo);
    }
    return grouped;
  }

  void _selectDate(DateTime? date) {
    setState(() => _selectedDate = date);
  }

  Future<void> _pickCustomDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
      initialDate: _selectedDate ?? DateTime.now(),
    );
    if (picked != null) {
      _selectDate(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final photoProvider = context.watch<PhotoProvider>();
    final auth = context.read<AuthProvider>();

    // Apply date filter then search
    final dateFiltered = _applyDateFilter(photoProvider.photos);
    final Map<String, List<PhotoModel>> photoGroups;
    if (_searchQuery.isNotEmpty) {
      final lowerQuery = _searchQuery.toLowerCase();
      final filtered = dateFiltered
          .where((p) =>
              p.location.toLowerCase().contains(lowerQuery) ||
              (p.customerName?.toLowerCase().contains(lowerQuery) ?? false) ||
              (p.category?.toLowerCase().contains(lowerQuery) ?? false))
          .toList();
      photoGroups = filtered.isNotEmpty ? {'Results': filtered} : {};
    } else {
      photoGroups = _groupByDate(dateFiltered);
    }

    final groupKeys = photoGroups.keys.toList();

    return GradientBackground(
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AppHeader(
              title: _isTeamLead ? 'Team Gallery' : 'Gallery',
              type: AppHeaderType.secondary,
              showAvatar: false,
              showLeading: false,
            ),

            // Search Bar
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              color: AppColors.glassHeader,
              child: GlassInputField(
                controller: _searchController,
                hint: _isTeamLead
                    ? 'Search photos, names, tags...'
                    : 'Search photos, tags...',
                prefixIcon: AppIcons.search_normal,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),

            // Date Filter Chips
            _buildDateFilterChips(),

            // Content
            Expanded(
              child: Stack(
                children: [
                  if (photoProvider.isLoading && photoProvider.photos.isEmpty)
                    const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    )
                  else if (groupKeys.isEmpty)
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            AppIcons.image,
                            size: 48,
                            color: AppColors.textTertiary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _searchQuery.isNotEmpty || _selectedDate != null
                                ? 'No photos found'
                                : 'No photos yet',
                            style: AppTypography.bodyMedium.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                      itemCount: groupKeys.length,
                      itemBuilder: (context, index) {
                        final key = groupKeys[index];
                        final photos = photoGroups[key]!;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: _buildPhotoGroup(key, photos, auth),
                        );
                      },
                    ),

                  // Camera FAB
                  Positioned(
                    right: 24,
                    bottom: 120,
                    child: GestureDetector(
                      onTap: () => context.push('/employee/camera'),
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.glassBorder,
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.3),
                              blurRadius: 16,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: const Icon(
                          AppIcons.camera,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Date Filter Chips ──────────────────────────────────────────

  Widget _buildDateFilterChips() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    final isAll = _selectedDate == null;
    final isToday = _selectedDate != null &&
        DateTime(_selectedDate!.year, _selectedDate!.month,
                _selectedDate!.day) ==
            today;
    final isYesterday = _selectedDate != null &&
        DateTime(_selectedDate!.year, _selectedDate!.month,
                _selectedDate!.day) ==
            yesterday;
    final isCustom = _selectedDate != null && !isToday && !isYesterday;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      color: AppColors.glassHeader,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildChip('All', isAll, () => _selectDate(null)),
            const SizedBox(width: 8),
            _buildChip('Today', isToday, () => _selectDate(today)),
            const SizedBox(width: 8),
            _buildChip('Yesterday', isYesterday, () => _selectDate(yesterday)),
            const SizedBox(width: 8),
            _buildChip(
              isCustom
                  ? DateFormat('dd MMM').format(_selectedDate!)
                  : 'Pick Date',
              isCustom,
              _pickCustomDate,
              icon: AppIcons.calendar_1,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChip(String label, bool isSelected, VoidCallback onTap,
      {IconData? icon}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.glassPrimary,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.glassBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 14,
                color: isSelected ? Colors.white : AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Photo Group ────────────────────────────────────────────────

  Widget _buildPhotoGroup(
    String title,
    List<PhotoModel> photos,
    AuthProvider auth,
  ) {
    const spacing = 12.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTypography.h3.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${photos.length} photos',
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final tileSize = (constraints.maxWidth - (spacing * 2)) / 3;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final photo in photos)
                  SizedBox(
                    width: tileSize,
                    height: tileSize,
                    child: _buildPhotoTile(photo, auth),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildPhotoTile(PhotoModel photo, AuthProvider auth) {
    final thumbUrl = photo.thumbnailUrl?.isNotEmpty == true
        ? photo.thumbnailUrl!
        : photo.imageUrl;
    final fullUrl = photo.imageUrl;
    final heroTag = 'photo_${photo.id}';
    final capturedBy = _resolveCapturedBy(photo, auth);

    // For team leads, resolve the employee name for the tile
    final bool showEmployeeName =
        _isTeamLead && photo.employeeId != (auth.currentUser?.id ?? '');

    return GestureDetector(
      onTap: () {
        if (photo.uploadStatus == UploadStatus.pending) {
          return;
        }
        if (photo.uploadStatus == UploadStatus.error &&
            photo.clientRequestId != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Retrying upload...'),
              duration: Duration(seconds: 2),
            ),
          );
          context.read<PhotoProvider>().retryUpload(photo.clientRequestId!);
          return;
        }
        // Precache full image so detail screen shows it faster
        if (photo.uploadStatus == UploadStatus.success && fullUrl.isNotEmpty) {
          precacheImage(CachedNetworkImageProvider(fullUrl), context);
        }
        context.push('/employee/image-detail', extra: {
          'imageUrl': fullUrl,
          'thumbnailUrl': thumbUrl,
          'location': photo.location,
          'capturedBy': capturedBy,
          'employeeId': photo.employeeId,
          'timestamp': photo.timestamp,
          'latitude': photo.latitude,
          'longitude': photo.longitude,
          'category': photo.category,
          'name': photo.customerName,
          'phone': photo.customerPhone,
          'customerType': photo.customerType,
          'notes': photo.notes,
          'hasFollowUp': photo.hasFollowUp,
          'heroTag': heroTag,
        });
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: AppColors.glassPrimary,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Hero(
                tag: heroTag,
                child: photo.localFilePath != null &&
                        photo.uploadStatus != UploadStatus.success
                    ? Image.file(
                        File(photo.localFilePath!),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: AppColors.glassPrimary,
                          child: const Icon(
                            AppIcons.image,
                            color: AppColors.textTertiary,
                            size: 24,
                          ),
                        ),
                      )
                    : PhotoTileImage(thumbUrl: thumbUrl, fullUrl: fullUrl),
              ),
              if (photo.uploadStatus == UploadStatus.pending)
                Container(
                  color: Colors.black.withValues(alpha: 0.28),
                  child: const Center(
                    child: SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              if (photo.uploadStatus == UploadStatus.error)
                Container(
                  color: Colors.black.withValues(alpha: 0.22),
                  child: Center(
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(seconds: 2),
                      builder: (context, value, child) => Transform.rotate(
                        angle: value * 2 * 3.14159,
                        child: child,
                      ),
                      child: const Icon(
                        AppIcons.refresh_circle,
                        color: AppColors.critical,
                        size: 30,
                      ),
                    ),
                  ),
                ),
              // Bottom Overlay (time + optional employee name)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(8),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (showEmployeeName)
                        Text(
                          capturedBy,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      Text(
                        photo.formattedTime,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
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
  }
}
