import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:izumi/core/ui/app_icons.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';
import '../../models/notification_model.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/glass/gradient_background.dart';
import '../../widgets/glass/glass_panel.dart';
import '../../widgets/navigation/app_header.dart';

/// Notifications Screen - Unified Glass Design
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<NotificationModel> _notifications = [];
  bool _isLoading = true;
  StreamSubscription? _subscription;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  void _loadNotifications() {
    final auth = context.read<AuthProvider>();
    final userId = auth.currentUser?.id;
    if (userId == null) {
      setState(() => _isLoading = false);
      return;
    }

    _subscription = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .listen(
      (snapshot) {
        if (!mounted) return;
        setState(() {
          _notifications = snapshot.docs
              .map((doc) => NotificationModel.fromFirestore(doc))
              .toList();
          _isLoading = false;
        });
      },
      onError: (_) {
        if (!mounted) return;
        setState(() => _isLoading = false);
      },
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _clearAll() async {
    final auth = context.read<AuthProvider>();
    final userId = auth.currentUser?.id;
    if (userId == null) return;

    final batch = FirebaseFirestore.instance.batch();
    final docs = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .get();
    for (final doc in docs.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'All notifications cleared',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        backgroundColor: AppColors.glassStrong,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Mark a notification as read in Firestore and navigate based on its action.
  Future<void> _onNotificationTap(NotificationModel item) async {
    final auth = context.read<AuthProvider>();
    final userId = auth.currentUser?.id;

    // Mark as read
    if (userId != null && !item.isRead) {
      FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('notifications')
          .doc(item.id)
          .update({'isRead': true});
    }

    // Navigate based on action
    final action = item.data['action'] as String?;
    if (action == null || !mounted) return;

    final isAdmin = auth.isAdmin;

    switch (action) {
      case 'TASK_ASSIGNED':
      case 'TASK_COMPLETED':
        context.go(isAdmin ? '/admin/tasks' : '/employee/tasks');
        break;
      case 'SESSION_STARTED':
      case 'SESSION_ENDED':
        final sessionId = item.data['sessionId'] as String?;
        if (sessionId != null) {
          await _openSessionLocation(sessionId);
        } else {
          if (mounted) context.go(isAdmin ? '/admin/dashboard' : '/employee/home');
        }
        break;
    }
  }

  /// Fetch the session's check-in location and open it in Google Maps.
  Future<void> _openSessionLocation(String sessionId) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('sessions')
          .doc(sessionId)
          .collection('locations')
          .orderBy('timestamp')
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final data = snapshot.docs.first.data();
        final lat = data['latitude'] as num?;
        final lng = data['longitude'] as num?;
        if (lat != null && lng != null) {
          final uri = Uri.parse(
            'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
          );
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('[NotificationsScreen] Failed to open session location: $e');
    }

    // Fallback: navigate to dashboard/home
    if (mounted) {
      final isAdmin = context.read<AuthProvider>().isAdmin;
      context.go(isAdmin ? '/admin/dashboard' : '/employee/home');
    }
  }

  IconData _iconForNotification(NotificationModel item) {
    // Use the specific action for more granular icons
    final action = item.data['action'] as String?;
    switch (action) {
      case 'TASK_ASSIGNED':
        return AppIcons.task_square;
      case 'TASK_COMPLETED':
        return AppIcons.tick_circle;
      case 'SESSION_STARTED':
        return AppIcons.timer_start;
      case 'SESSION_ENDED':
        return AppIcons.timer_pause;
      default:
        break;
    }
    // Fall back to broad type
    switch (item.type) {
      case 'task':
        return AppIcons.task_square;
      case 'alert':
        return AppIcons.warning_2;
      case 'location':
        return AppIcons.location;
      case 'report':
        return AppIcons.note_2;
      case 'system':
        return AppIcons.refresh_square_2;
      default:
        return AppIcons.notification;
    }
  }

  Color _colorForNotification(NotificationModel item) {
    final action = item.data['action'] as String?;
    switch (action) {
      case 'TASK_ASSIGNED':
        return AppColors.primary;
      case 'TASK_COMPLETED':
        return AppColors.success;
      case 'SESSION_STARTED':
        return AppColors.info;
      case 'SESSION_ENDED':
        return AppColors.warning;
      default:
        break;
    }
    switch (item.type) {
      case 'task':
        return AppColors.primary;
      case 'alert':
        return AppColors.warning;
      case 'location':
        return AppColors.success;
      case 'report':
        return AppColors.textSecondary;
      case 'system':
        return AppColors.info;
      default:
        return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = _notifications.where((n) => n.isToday).toList();
    final earlier = _notifications.where((n) => !n.isToday).toList();
    final hasNotifications = _notifications.isNotEmpty;

    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              AppHeader(
                title: 'Notifications',
                type: AppHeaderType.secondary,
                showAvatar: false,
                actions: [
                  if (hasNotifications) _buildClearAllButton(context),
                ],
              ),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                        ),
                      )
                    : hasNotifications
                        ? ListView(
                            padding:
                                const EdgeInsets.fromLTRB(20, 16, 20, 120),
                            children: [
                              if (today.isNotEmpty) ...[
                                _buildSectionHeader('Today'),
                                const SizedBox(height: 12),
                                ...today.map(_buildNotificationCard),
                              ],
                              if (earlier.isNotEmpty) ...[
                                const SizedBox(height: 24),
                                _buildSectionHeader('Earlier'),
                                const SizedBox(height: 12),
                                ...earlier.map(_buildNotificationCard),
                              ],
                            ],
                          )
                        : _buildEmptyState(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        label.toUpperCase(),
        style: AppTypography.caption.copyWith(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildClearAllButton(BuildContext context) {
    return GestureDetector(
      onTap: _clearAll,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.glassPrimary,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Text(
          'Clear all',
          style: AppTypography.caption.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: GlassCard(
          borderRadius: 24,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                AppIcons.notification_bing,
                size: 36,
                color: AppColors.textSecondary,
              ),
              const SizedBox(height: 12),
              Text(
                "You're all caught up",
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'No new notifications right now.',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationCard(NotificationModel item) {
    final icon = _iconForNotification(item);
    final color = _colorForNotification(item);
    final isMuted = item.isRead;

    return GestureDetector(
      onTap: () => _onNotificationTap(item),
      child: GlassCard(
        margin: const EdgeInsets.only(bottom: 12),
        borderRadius: 22,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 4,
              height: 56,
              decoration: BoxDecoration(
                color: isMuted ? AppColors.glassBorder : color,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: isMuted ? 0.08 : 0.2),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: color.withValues(alpha: 0.3),
                ),
              ),
              child: Icon(
                icon,
                color: isMuted ? AppColors.textTertiary : color,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          style: AppTypography.bodyMedium.copyWith(
                            color: isMuted
                                ? AppColors.textSecondary
                                : AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        item.timeAgo,
                        style: AppTypography.small.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.body,
                    style: AppTypography.caption.copyWith(
                      color: isMuted
                          ? AppColors.textTertiary
                          : AppColors.textSecondary,
                      height: 1.4,
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
}
