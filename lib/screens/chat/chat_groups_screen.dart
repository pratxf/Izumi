import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:izumi/core/ui/app_icons.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_typography.dart';
import '../../models/chat_group_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../widgets/inputs/alphabet_filter.dart';
import '../../widgets/navigation/app_header.dart';

class ChatGroupsScreen extends StatefulWidget {
  const ChatGroupsScreen({super.key});

  @override
  State<ChatGroupsScreen> createState() => _ChatGroupsScreenState();
}

class _ChatGroupsScreenState extends State<ChatGroupsScreen> {
  bool _sortAscending = true;
  DateTime? _lastNavTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initStream();
    });
  }

  void _initStream() {
    final authProvider = context.read<AuthProvider>();
    final chatProvider = context.read<ChatProvider>();
    final enterpriseId = authProvider.enterpriseId ?? '';
    final userId = authProvider.currentUser?.id ?? '';
    if (enterpriseId.isNotEmpty && userId.isNotEmpty) {
      chatProvider.streamChatGroups(enterpriseId, userId,
          isAdmin: authProvider.isAdmin);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final chatProvider = context.watch<ChatProvider>();
    final isAdmin = authProvider.isAdmin;
    final userId = authProvider.currentUser?.id ?? '';

    final sortedGroups = List<ChatGroupModel>.of(chatProvider.chatGroups)
      ..sort((a, b) => _sortAscending
          ? a.name.toLowerCase().compareTo(b.name.toLowerCase())
          : b.name.toLowerCase().compareTo(a.name.toLowerCase()));

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppHeader(
        title: 'Chat',
        showAvatar: false,
        showLeading: false,
      ),
      body: sortedGroups.isEmpty
          ? _buildEmptyState(isAdmin)
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                  child: AlphabetFilter(
                    isAscending: _sortAscending,
                    onToggle: (val) => setState(() => _sortAscending = val),
                  ),
                ),
                Expanded(
                  child: sortedGroups.isEmpty
                      ? Center(
                          child: Text(
                            'No chat groups found',
                            style: AppTypography.bodyMedium.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 0,
                            vertical: 8,
                          ),
                          itemCount: sortedGroups.length,
                          itemBuilder: (context, index) {
                            final group = sortedGroups[index];
                            return _ChatGroupTile(
                              group: group,
                              userId: userId,
                              isAdmin: isAdmin,
                              isLast: index == sortedGroups.length - 1,
                              onTap: () {
                                final now = DateTime.now();
                                if (_lastNavTime != null &&
                                    now.difference(_lastNavTime!) <
                                        const Duration(milliseconds: 800)) {
                                  return;
                                }
                                _lastNavTime = now;
                                chatProvider.markAsRead(group.id, userId);
                                context.push('/chat/conversation', extra: {
                                  'groupId': group.id,
                                  'groupName': group.name,
                                });
                              },
                              onLongPress: isAdmin
                                  ? () => _showGroupOptions(
                                      context, group, chatProvider)
                                  : null,
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: isAdmin
          ? Padding(
              padding: const EdgeInsets.only(
                  bottom: AppSpacing.navBarHeight + AppSpacing.xxl),
              child: FloatingActionButton(
                onPressed: () => context.push('/admin/create-chat-group'),
                backgroundColor: AppColors.primary,
                child: const Icon(AppIcons.add, color: Colors.white),
              ),
            )
          : null,
    );
  }

  void _showGroupOptions(
      BuildContext context, ChatGroupModel group, ChatProvider chatProvider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: AppColors.glassStrong,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              ListTile(
                leading: const Icon(AppIcons.edit_2, color: AppColors.primary),
                title: Text(
                  'Edit Group',
                  style: AppTypography.bodyMedium
                      .copyWith(color: AppColors.textPrimary),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  context.push('/admin/edit-chat-group', extra: group);
                },
              ),
              ListTile(
                leading: const Icon(AppIcons.trash, color: AppColors.critical),
                title: Text(
                  'Delete Group',
                  style: AppTypography.bodyMedium
                      .copyWith(color: AppColors.critical),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDelete(context, group, chatProvider);
                },
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete(
      BuildContext context, ChatGroupModel group, ChatProvider chatProvider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.glassStrong,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Delete Group',
          style: AppTypography.h3.copyWith(color: AppColors.textPrimary),
        ),
        content: Text(
          'Are you sure you want to delete "${group.name}"? This action cannot be undone.',
          style:
              AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final success = await chatProvider.deleteChatGroup(group.id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(success
                        ? 'Group deleted'
                        : chatProvider.error ?? 'Failed to delete group'),
                    backgroundColor:
                        success ? AppColors.success : AppColors.critical,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                );
              }
            },
            child: Text(
              'Delete',
              style:
                  AppTypography.bodySmall.copyWith(color: AppColors.critical),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isAdmin) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              AppIcons.message,
              size: 64,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'No Chats Yet',
              style: AppTypography.h3.copyWith(color: AppColors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              isAdmin
                  ? 'Create a chat group to start messaging your team.'
                  : 'You haven\'t been added to any chat groups yet.',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatGroupTile extends StatelessWidget {
  final ChatGroupModel group;
  final String userId;
  final bool isAdmin;
  final bool isLast;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _ChatGroupTile({
    required this.group,
    required this.userId,
    this.isAdmin = false,
    this.isLast = false,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final hasUnread = group.unreadCount(userId) > 0;

    return Padding(
      padding: EdgeInsets.zero,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
              bottom: BorderSide(
                color: isLast
                    ? Colors.transparent
                    : AppColors.glassBorder.withValues(alpha: 0.55),
              ),
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                child: Text(
                  group.name.isNotEmpty ? group.name[0].toUpperCase() : 'C',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            group.name,
                            style: AppTypography.bodyMedium.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight:
                                  hasUnread ? FontWeight.w700 : FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (group.isBroadcast)
                          const Padding(
                            padding: EdgeInsets.only(left: 6),
                            child: Icon(
                              AppIcons.volume_high,
                              size: 14,
                              color: AppColors.textTertiary,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      group.lastMessage != null
                          ? '${group.lastMessageSenderName}: ${group.lastMessagePreview}'
                          : 'No messages yet',
                      style: AppTypography.bodySmall.copyWith(
                        color: hasUnread
                            ? AppColors.textSecondary
                            : AppColors.textTertiary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (group.lastMessageAt != null)
                    Text(
                      _formatTimestamp(group.lastMessageAt!),
                      style: AppTypography.small.copyWith(
                        color: hasUnread
                            ? AppColors.primary
                            : AppColors.textTertiary,
                      ),
                    ),
                  if (hasUnread) ...[
                    const SizedBox(height: 6),
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDate = DateTime(dateTime.year, dateTime.month, dateTime.day);

    if (msgDate == today) {
      return DateFormat.jm().format(dateTime);
    } else if (msgDate == today.subtract(const Duration(days: 1))) {
      return 'Yesterday';
    } else {
      return DateFormat('dd/MM').format(dateTime);
    }
  }
}
