import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:izumi/core/ui/app_icons.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_shadows.dart';
import '../../core/constants/app_typography.dart';
import '../../models/activity_log_model.dart';
import '../../models/photo_model.dart';
import '../../models/task_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/enterprise_provider.dart';
import '../../providers/team_provider.dart';
import '../../services/admin_activity_feed_service.dart';
import '../../services/unified_data_layer.dart';
import '../../widgets/glass/glass_panel.dart';
import '../../widgets/glass/gradient_background.dart';
import '../../widgets/navigation/app_header.dart';

/// Team Lead Employee Detail Screen — Enhanced with summary, photos, feed
class TeamLeadEmployeeDetailScreen extends StatefulWidget {
  final String name;
  final String initials;
  final bool isOnline;
  final String? employeeId;

  const TeamLeadEmployeeDetailScreen({
    super.key,
    required this.name,
    required this.initials,
    this.isOnline = true,
    this.employeeId,
  });

  @override
  State<TeamLeadEmployeeDetailScreen> createState() =>
      _TeamLeadEmployeeDetailScreenState();
}

class _TeamLeadEmployeeDetailScreenState
    extends State<TeamLeadEmployeeDetailScreen> {
  static const int _previewPhotoCount = 3;

  final AdminActivityFeedService _feedService = AdminActivityFeedService();
  StreamSubscription? _feedSubscription;
  StreamSubscription<double>? _distanceSubscription;

  List<ActivityLogModel> _activities = [];
  List<PhotoModel> _photos = [];
  bool _feedLoading = true;

  // Distance sourced from UnifiedDataLayer so this screen shows the same
  // number as admin dashboard, analytics, and the employee's own history.
  double _distanceKm = 0.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startFeed();
      _subscribeDistance();
    });
  }

  @override
  void dispose() {
    _feedSubscription?.cancel();
    _distanceSubscription?.cancel();
    super.dispose();
  }

  void _subscribeDistance() {
    final employeeId = widget.employeeId;
    if (employeeId == null) return;
    final enterpriseId = context.read<AuthProvider>().enterpriseId;
    if (enterpriseId == null) return;
    _distanceSubscription?.cancel();
    _distanceSubscription = UnifiedDataLayer.I
        .streamDistance(
          employeeId: employeeId,
          enterpriseId: enterpriseId,
          date: DateTime.now(),
        )
        .listen((km) {
      if (!mounted) return;
      setState(() => _distanceKm = km);
    });
  }

  void _startFeed() {
    if (widget.employeeId == null) return;

    // Resolve migration IDs upfront so we open the Firestore stream ONCE
    // with the full ID set. Splitting this into "start with [currentUid] →
    // then restart with full list" causes the first subscription's first
    // emission to be cancelled before it can propagate, leaving the user
    // staring at an empty state during the cold-start window.
    List<String> linkedIds;
    try {
      linkedIds = context
          .read<EnterpriseProvider>()
          .resolveLinkedIds(widget.employeeId!);
    } catch (_) {
      linkedIds = [widget.employeeId!];
    }

    _feedSubscription?.cancel();
    _feedSubscription = _feedService
        .streamRecentFeed(
          linkedEmployeeIds: linkedIds,
          window: const Duration(hours: 24),
          photoLimit: 20,
        )
        .listen((feed) {
      if (!mounted) return;
      // Stream-driven loading: first emission — empty or not — ends the
      // spinner. No warmup timer. Firestore snapshot streams auto-retry
      // so a cold connection resolves itself without a synthetic timeout.
      setState(() {
        _activities = feed.activities;
        _photos = feed.photos;
        _feedLoading = false;
      });
    }, onError: (_) {
      if (!mounted) return;
      setState(() => _feedLoading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final teamProvider = context.watch<TeamProvider>();
    final dashboardProvider = context.watch<DashboardProvider>();

    final employeeTasks = widget.employeeId != null
        ? teamProvider.teamTasks
            .where((t) => t.assignedTo == widget.employeeId)
            .toList()
        : <TaskModel>[];

    final tasks = employeeTasks.where((t) => t.isTask).toList();
    final followUps = employeeTasks.where((t) => t.isFollowup).toList();
    final completedTaskCount = tasks.where((t) => t.isCompleted).length;
    final completedFollowUpCount =
        followUps.where((t) => t.isCompleted).length;
    final pendingTasks = tasks.length - completedTaskCount;
    final pendingFollowUps = followUps.length - completedFollowUpCount;

    // Live stats from dashboard
    final stats = widget.employeeId != null
        ? dashboardProvider.getEmployeeStats(widget.employeeId!)
        : null;
    final status = widget.employeeId != null
        ? dashboardProvider.getEmployeeStatus(widget.employeeId!)
        : 'offline';
    final location = widget.employeeId != null
        ? dashboardProvider.getEmployeeLocation(widget.employeeId!)
        : null;

    final durationSec = (stats?['sessionDuration'] as int?) ?? 0;
    final distanceKm = _distanceKm;
    final photosToday = (stats?['photosToday'] as num?)?.toInt() ?? 0;
    final tasksToday = (stats?['tasksToday'] as num?)?.toInt() ?? 0;
    final address = location?['address'] as String? ?? 'Unknown';

    final isActive = status == 'active' || status == 'break';

    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              AppHeader(
                title: widget.name,
                type: AppHeaderType.secondary,
                showAvatar: false,
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
                  children: [
                    // 1. Header with status
                    _buildHeader(status, address, isActive),
                    const SizedBox(height: 16),

                    // 2. Today's summary
                    _buildTodaySummary(
                        durationSec, distanceKm, photosToday, tasksToday),
                    const SizedBox(height: 20),

                    // 3. Tasks & Follow-ups
                    _buildSectionTitle('Tasks'),
                    const SizedBox(height: 8),
                    _buildSummaryCard(
                      title: 'Tasks',
                      completed: completedTaskCount,
                      total: tasks.length,
                      pendingLabel: '$pendingTasks Pending',
                    ),
                    const SizedBox(height: 8),
                    _buildTaskList(tasks),
                    const SizedBox(height: 16),
                    _buildSummaryCard(
                      title: 'Follow-ups',
                      completed: completedFollowUpCount,
                      total: followUps.length,
                      pendingLabel: '$pendingFollowUps Pending',
                    ),
                    const SizedBox(height: 8),
                    _buildTaskList(followUps),
                    const SizedBox(height: 20),

                    // 4. Photos
                    if (_photos.isNotEmpty) ...[
                      _buildSectionTitle('Photos (${_photos.length})'),
                      const SizedBox(height: 8),
                      _buildPhotoGrid(),
                      if (_photos.length > _previewPhotoCount) ...[
                        const SizedBox(height: 12),
                        _buildViewMorePhotosButton(),
                      ],
                      const SizedBox(height: 20),
                    ],

                    // 5. Activity feed
                    _buildSectionTitle('Activity Feed'),
                    const SizedBox(height: 8),
                    _buildActivityFeed(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header ──

  Widget _buildHeader(String status, String address, bool isActive) {
    Color statusColor;
    String statusLabel;
    switch (status) {
      case 'active':
        statusColor = AppColors.success;
        statusLabel = 'Active';
      case 'break':
        statusColor = AppColors.warning;
        statusLabel = 'On Break';
      default:
        statusColor = AppColors.textTertiary;
        statusLabel = 'Offline';
    }

    return Container(
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
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.glassHover,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: statusColor, width: 2),
            ),
            child: Center(
              child: Text(
                widget.initials,
                style: AppTypography.bodyMedium.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.name,
                    style: AppTypography.h3
                        .copyWith(color: AppColors.textPrimary)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                          color: statusColor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Text(statusLabel,
                        style: AppTypography.caption.copyWith(
                            color: statusColor, fontWeight: FontWeight.w600)),
                  ],
                ),
                if (isActive) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(AppIcons.location,
                          size: 12, color: AppColors.textTertiary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(address,
                            style: AppTypography.caption
                                .copyWith(color: AppColors.textSecondary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Today's Summary ──

  Widget _buildTodaySummary(
      int durationSec, double distanceKm, int photos, int tasks) {
    final h = durationSec ~/ 3600;
    final m = (durationSec % 3600) ~/ 60;
    final durationStr = h > 0 ? '${h}h ${m}m' : '${m}m';

    return Row(
      children: [
        _buildMiniStat(AppIcons.clock, durationStr, 'Duration'),
        const SizedBox(width: 8),
        _buildMiniStat(
            AppIcons.location, '${distanceKm.toStringAsFixed(1)} km', 'Distance'),
        const SizedBox(width: 8),
        _buildMiniStat(AppIcons.camera, '$photos', 'Photos'),
        const SizedBox(width: 8),
        _buildMiniStat(AppIcons.task_square, '$tasks', 'Tasks'),
      ],
    );
  }

  Widget _buildMiniStat(IconData icon, String value, String label) {
    return Expanded(
      child: GlassPanel(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        child: Column(
          children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(height: 6),
            Text(value,
                style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(label,
                style: AppTypography.caption
                    .copyWith(color: AppColors.textSecondary, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  // ── Photos ──

  Widget _buildPhotoGrid() {
    final visible = _photos.take(_previewPhotoCount).toList();
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: visible.length,
      itemBuilder: (context, index) => _buildPhotoTile(visible[index]),
    );
  }

  Widget _buildPhotoTile(PhotoModel photo) {
    final isLocal = photo.imageUrl.startsWith('/');
    final displayUrl = (photo.thumbnailUrl?.isNotEmpty == true)
        ? photo.thumbnailUrl!
        : (photo.imageUrl.isNotEmpty ? photo.imageUrl : null);

    Widget image;
    if (isLocal) {
      image = const ColoredBox(
        color: AppColors.glassPrimary,
        child: Center(
          child: Icon(AppIcons.camera, color: AppColors.textTertiary),
        ),
      );
    } else if (displayUrl == null) {
      image = Container(
        color: Colors.grey[300],
        child: Center(
          child: Icon(Icons.image_not_supported, color: Colors.grey[500]),
        ),
      );
    } else {
      image = CachedNetworkImage(
        imageUrl: displayUrl,
        cacheKey: photo.id,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(color: Colors.grey[200]),
        errorWidget: (context, url, error) => Container(
          color: Colors.grey[300],
          child: Center(
            child: Icon(Icons.broken_image, color: Colors.grey[500]),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: isLocal ? null : () => _openPhoto(photo),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: image,
      ),
    );
  }

  void _openPhoto(PhotoModel photo) {
    final thumbUrl = photo.thumbnailUrl?.isNotEmpty == true
        ? photo.thumbnailUrl!
        : photo.imageUrl;
    final fullUrl = photo.imageUrl;
    if (fullUrl.isNotEmpty) {
      precacheImage(CachedNetworkImageProvider(fullUrl), context);
    }
    context.push('/employee/image-detail', extra: {
      'imageUrl': fullUrl,
      'thumbnailUrl': thumbUrl,
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
      'heroTag': 'team_lead_photo_${photo.id}',
    });
  }

  Widget _buildViewMorePhotosButton() {
    return Align(
      alignment: Alignment.center,
      child: TextButton(
        onPressed: () {
          if (widget.employeeId == null) return;
          context.push('/admin/employee-images',
              extra: {'employeeId': widget.employeeId});
        },
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: AppTypography.bodyMedium.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        child: Text('View all ${_photos.length} photos'),
      ),
    );
  }

  // ── Activity Feed ──

  Widget _buildActivityFeed() {
    if (_feedLoading) {
      // Shimmer skeleton while stream is connecting
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: List.generate(5, (_) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.glassPrimary,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.glassBorder),
              ),
            ),
          )),
        ),
      );
    }

    if (_activities.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.timeline_outlined,
                  color: AppColors.textTertiary.withValues(alpha: 0.4),
                  size: 48),
              const SizedBox(height: 12),
              Text('No activity in the last 24 hours',
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textTertiary)),
            ],
          ),
        ),
      );
    }

    return Column(
      children: _activities.take(20).map((log) {
        final time = DateFormat('h:mm a').format(log.timestamp);
        IconData icon;
        Color color;
        switch (log.type) {
          case 'session_start':
          case 'session_started':
            icon = AppIcons.play;
            color = AppColors.success;
          case 'session_end':
          case 'session_ended':
          case 'session_auto_ended':
            icon = AppIcons.stop_circle;
            color = AppColors.critical;
          case 'photo_captured':
            icon = AppIcons.camera;
            color = AppColors.primary;
          case 'task_completed':
            icon = AppIcons.tick_circle;
            color = AppColors.success;
          case 'location_update':
            icon = AppIcons.location;
            color = AppColors.textSecondary;
          default:
            icon = AppIcons.note;
            color = AppColors.textSecondary;
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GlassPanel(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, size: 16, color: color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(log.title,
                          style: AppTypography.bodySmall.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600)),
                      if (log.detail.isNotEmpty)
                        Text(log.detail,
                            style: AppTypography.caption
                                .copyWith(color: AppColors.textSecondary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                Text(time,
                    style: AppTypography.caption
                        .copyWith(color: AppColors.textTertiary, fontSize: 11)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Tasks ──

  Widget _buildSectionTitle(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(label,
          style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required int completed,
    required int total,
    required String pendingLabel,
  }) {
    final progress = total == 0 ? 0.0 : completed / total;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.glassPrimary,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title,
                  style:
                      AppTypography.h3.copyWith(color: AppColors.textPrimary)),
              Text(pendingLabel,
                  style: AppTypography.caption
                      .copyWith(color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('$completed',
                  style: AppTypography.displayLarge
                      .copyWith(color: AppColors.textPrimary)),
              const SizedBox(width: 6),
              Text('/ $total',
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: progress,
              backgroundColor: AppColors.glassBorder,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskList(List<TaskModel> tasks) {
    if (tasks.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Text('No items',
              style: AppTypography.caption
                  .copyWith(color: AppColors.textTertiary)),
        ),
      );
    }

    final timeFormat = DateFormat('h:mm a');
    return Column(
      children: tasks.map((task) {
        final completed = task.isCompleted;
        String subtitle;
        if (completed && task.completedAt != null) {
          subtitle = 'Completed at ${timeFormat.format(task.completedAt!)}';
        } else if (task.isDueToday) {
          subtitle = 'Due ${timeFormat.format(task.dueDate)}';
        } else {
          subtitle =
              'Due ${DateFormat('MMM d, h:mm a').format(task.dueDate)}';
        }

        IconData icon;
        Color accent;
        String statusLabel;
        if (completed) {
          icon = AppIcons.tick_circle;
          accent = AppColors.success;
          statusLabel = 'Done';
        } else if (task.isHighPriority) {
          icon = AppIcons.warning_2;
          accent = AppColors.error;
          statusLabel = 'High';
        } else {
          icon = task.isFollowup ? AppIcons.call : AppIcons.task_square;
          accent = AppColors.primary;
          statusLabel = 'Pending';
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
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
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, size: 14, color: accent),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(task.title,
                          style: AppTypography.bodySmall.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      Text(subtitle,
                          style: AppTypography.caption
                              .copyWith(color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(statusLabel,
                      style: AppTypography.caption.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w600,
                          fontSize: 10)),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
