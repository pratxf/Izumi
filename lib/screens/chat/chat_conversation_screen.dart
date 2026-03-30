import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:izumi/core/ui/app_icons.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/chat_message_model.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_typography.dart';
import '../../repositories/group_repository.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../services/permission_service.dart';
import '../../widgets/navigation/app_header.dart';
import 'chat_image_send_screen.dart';
import 'widgets/chat_image_group_bubble.dart';
import 'widgets/chat_message_bubble.dart';

class ChatConversationScreen extends StatefulWidget {
  final String groupId;
  final String groupName;

  const ChatConversationScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  State<ChatConversationScreen> createState() => _ChatConversationScreenState();
}

class _ChatConversationScreenState extends State<ChatConversationScreen> {
  final GroupRepository _groupRepo = GroupRepository();
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _imagePicker = ImagePicker();
  late final ChatProvider _chatProvider;
  int? _resolvedMemberCount;
  bool _isResolvingMemberCount = false;

  @override
  void initState() {
    super.initState();
    _chatProvider = context.read<ChatProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userId = context.read<AuthProvider>().currentUser?.id ?? '';
      _chatProvider.openChat(widget.groupId);
      _chatProvider.markAsRead(widget.groupId, userId);
    });
    _scrollController.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveMemberCount();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 100) {
      context.read<ChatProvider>().loadMoreMessages();
    }
  }

  Future<void> _resolveMemberCount() async {
    final group = context.read<ChatProvider>().activeChatGroup;
    if (group == null) return;
    if (_isResolvingMemberCount) return;

    _isResolvingMemberCount = true;
    String? linkedGroupId = group.linkedGroupId;
    if (linkedGroupId == null || linkedGroupId.trim().isEmpty) {
      final enterpriseId = context.read<AuthProvider>().enterpriseId ?? '';
      if (enterpriseId.isNotEmpty && group.name.trim().isNotEmpty) {
        try {
          final groups = await _groupRepo.getGroupsByEnterprise(enterpriseId);
          final matchedGroup = groups
              .where((candidate) => candidate.name.trim() == group.name.trim())
              .firstOrNull;
          linkedGroupId = matchedGroup?.id;
        } catch (_) {
          // Best-effort header hint only.
        }
      }
    }

    if (linkedGroupId == null || linkedGroupId.trim().isEmpty) {
      if (!mounted) return;
      setState(() => _resolvedMemberCount = group.memberCount);
      _isResolvingMemberCount = false;
      return;
    }

    try {
      final linkedGroup = await _groupRepo.getGroup(linkedGroupId);
      if (!mounted) return;
      setState(() {
        _resolvedMemberCount =
            linkedGroup?.memberIds.length ?? group.memberCount;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _resolvedMemberCount = group.memberCount);
    } finally {
      _isResolvingMemberCount = false;
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _chatProvider.closeChat();
    super.dispose();
  }

  void _sendText() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    final authProvider = context.read<AuthProvider>();
    final chatProvider = context.read<ChatProvider>();
    final userId = authProvider.currentUser?.id ?? '';
    final userName = authProvider.currentUser?.name ?? '';

    _textController.clear();

    chatProvider.sendTextMessage(
      groupId: widget.groupId,
      text: text,
      senderId: userId,
      senderName: userName,
    );
  }

  Future<void> _pickAndSendImage() async {
    final granted = await PermissionService().ensurePhotoLibraryPermission(
      context: context,
      title: 'Photo Library Access',
      message: 'Izumi needs photo library access to send gallery images.',
    );
    if (!granted) return;

    final picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 70,
    );
    if (picked == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatImageSendScreen(
          groupId: widget.groupId,
          imagePath: picked.path,
          title: 'Add Caption',
        ),
      ),
    );
  }

  void _openChatCamera() {
    context.push('/chat/camera', extra: {
      'groupId': widget.groupId,
      'groupName': widget.groupName,
    });
  }

  void _onReply(ChatMessageModel message) {
    context.read<ChatProvider>().setReplyTo(message);
  }

  Future<void> _onDelete(ChatMessageModel message) async {
    final success = await context
        .read<ChatProvider>()
        .deleteMessage(widget.groupId, message.id);
    if (!mounted || success) return;

    final error = context.read<ChatProvider>().error;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error == null || error.isEmpty
            ? 'Unable to delete message.'
            : error),
      ),
    );
  }

  bool _canSend() {
    final authProvider = context.read<AuthProvider>();
    final chatProvider = context.read<ChatProvider>();
    final group = chatProvider.activeChatGroup;
    if (group == null) return true;
    if (!group.isBroadcast) return true;
    // In broadcast mode, only admin or team lead can send
    return authProvider.isAdmin || authProvider.isTeamLead;
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final chatProvider = context.watch<ChatProvider>();
    final userId = authProvider.currentUser?.id ?? '';
    final messages = chatProvider.messages;
    final group = chatProvider.activeChatGroup;
    final canSend = _canSend();
    final memberCount = _resolvedMemberCount;

    if (group != null && _resolvedMemberCount == null) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _resolveMemberCount());
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppHeader(
        title: widget.groupName,
        type: AppHeaderType.secondary,
        showAvatar: false,
        actions: [
          if (memberCount != null)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: Text(
                '$memberCount members',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Broadcast banner
          if (group?.isBroadcast == true && !canSend)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              color: AppColors.primary.withValues(alpha: 0.1),
              child: Row(
                children: [
                  Icon(AppIcons.volume_high,
                      size: 16, color: AppColors.primaryLight),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'Broadcast channel — only admins can send',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.primaryLight,
                    ),
                  ),
                ],
              ),
            ),

          // Messages list
          Expanded(
            child: chatProvider.error != null && messages.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xxxl),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(AppIcons.warning_2,
                              size: 48, color: AppColors.textTertiary),
                          const SizedBox(height: AppSpacing.lg),
                          Text(
                            'Unable to load messages',
                            style: AppTypography.body.copyWith(
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            'You may not have access to this group.',
                            style: AppTypography.caption.copyWith(
                              color: AppColors.textTertiary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                : messages.isEmpty
                    ? Center(
                        child: Text(
                          'No messages yet.\nSend the first message!',
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.textTertiary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        reverse: true,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.screenPadding,
                          vertical: AppSpacing.md,
                        ),
                        itemCount:
                            messages.length + (chatProvider.isLoading ? 1 : 0),
                        itemBuilder: (context, index) {
                          // Loading indicator at the end (top of chat)
                          if (index == messages.length) {
                            return const Padding(
                              padding: EdgeInsets.all(AppSpacing.lg),
                              child: Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.textTertiary,
                                  ),
                                ),
                              ),
                            );
                          }

                          final message = messages[index];
                          final isMe = message.isMe(userId);

                          // Image grouping: skip messages consumed by a group leader
                          if (message.isImage &&
                              !_isImageGroupLeader(messages, index)) {
                            return const SizedBox.shrink();
                          }

                          // Image grouping: render grouped bubble
                          if (message.isImage &&
                              _isImageGroupLeader(messages, index)) {
                            final groupIndices =
                                _getImageGroup(messages, index);
                            if (groupIndices.length > 1) {
                              final groupMessages =
                                  groupIndices.map((i) => messages[i]).toList();
                              final oldestIndex = groupIndices.last;

                              Widget? dateSeparator;
                              if (oldestIndex == messages.length - 1 ||
                                  !_isSameDay(messages[oldestIndex].createdAt,
                                      messages[oldestIndex + 1].createdAt)) {
                                dateSeparator = _buildDateSeparator(
                                    messages[oldestIndex].createdAt);
                              }

                              final showName = !isMe &&
                                  (oldestIndex == messages.length - 1 ||
                                      messages[oldestIndex + 1].senderId !=
                                          message.senderId);

                              return Column(
                                children: [
                                  if (dateSeparator != null) dateSeparator,
                                  ChatImageGroupBubble(
                                    messages: groupMessages,
                                    isMe: isMe,
                                    showSenderName: showName,
                                    onReply: _onReply,
                                    onDelete: _onDelete,
                                  ),
                                ],
                              );
                            }
                          }

                          // Date separator
                          Widget? dateSeparator;
                          if (index == messages.length - 1 ||
                              !_isSameDay(message.createdAt,
                                  messages[index + 1].createdAt)) {
                            dateSeparator =
                                _buildDateSeparator(message.createdAt);
                          }

                          // Show sender name only for first message in a
                          // consecutive group from the same sender
                          final showName = !isMe &&
                              (index == messages.length - 1 ||
                                  messages[index + 1].senderId !=
                                      message.senderId);

                          return Column(
                            children: [
                              if (dateSeparator != null) dateSeparator,
                              ChatMessageBubble(
                                message: message,
                                isMe: isMe,
                                showSenderName: showName,
                                onReply: _onReply,
                                onDelete: _onDelete,
                                onRetry: message.clientRequestId == null
                                    ? null
                                    : () => context
                                        .read<ChatProvider>()
                                        .retryTextMessage(
                                          widget.groupId,
                                          message.clientRequestId!,
                                        ),
                              ),
                            ],
                          );
                        },
                      ),
          ),

          // Reply bar + Input bar
          if (canSend) ...[
            if (chatProvider.replyingTo != null) _buildReplyBar(chatProvider),
            _buildInputBar(chatProvider),
          ],
        ],
      ),
    );
  }

  Widget _buildReplyBar(ChatProvider chatProvider) {
    final reply = chatProvider.replyingTo!;
    final isReplyImage = reply.isImage;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.glassHeader,
        border: Border(
          top: BorderSide(color: AppColors.glassBorder, width: 1),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          if (isReplyImage && reply.imageUrl != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.network(
                reply.imageUrl!,
                width: 40,
                height: 40,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  reply.senderName,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.primaryLight,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  isReplyImage ? 'Photo' : (reply.text ?? ''),
                  style: AppTypography.small.copyWith(
                    color: AppColors.textTertiary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: chatProvider.clearReply,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xs),
              child: Icon(
                AppIcons.close_circle,
                size: 20,
                color: AppColors.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar(ChatProvider chatProvider) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: EdgeInsets.only(
            left: AppSpacing.md,
            right: AppSpacing.md,
            top: AppSpacing.sm,
            bottom: MediaQuery.of(context).padding.bottom + AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: AppColors.glassHeader,
            border: Border(
              top: BorderSide(color: AppColors.glassBorder, width: 1),
            ),
          ),
          child: Row(
            children: [
              // Attach buttons
              _InputIconButton(
                icon: AppIcons.image,
                onTap: _pickAndSendImage,
              ),
              const SizedBox(width: AppSpacing.xs),
              _InputIconButton(
                icon: AppIcons.camera,
                onTap: _openChatCamera,
              ),
              const SizedBox(width: AppSpacing.sm),
              // Text field
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 120),
                  decoration: BoxDecoration(
                    color: AppColors.glassPrimary,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
                    border: Border.all(color: AppColors.glassBorder),
                  ),
                  child: TextField(
                    controller: _textController,
                    style: AppTypography.body.copyWith(
                      color: AppColors.textPrimary,
                    ),
                    maxLines: null,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      hintStyle: AppTypography.inputHint,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                        vertical: AppSpacing.md,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              // Send button
              GestureDetector(
                onTap: _sendText,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                  ),
                  child: chatProvider.isSending
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          AppIcons.send_1,
                          color: Colors.white,
                          size: 20,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDateSeparator(DateTime date) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: AppColors.glassStrong,
            borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
          ),
          child: Text(
            _formatDate(date),
            style: AppTypography.small.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
        ),
      ),
    );
  }

  /// Whether the message at [index] is the first (newest) in a consecutive
  /// run of image messages from the same sender within 2 minutes.
  bool _isImageGroupLeader(List<ChatMessageModel> messages, int index) {
    final msg = messages[index];
    if (!msg.isImage || msg.isDeleted) return false;
    if (_hasGroupingBlockingCaption(msg)) return true;
    if (index == 0) return true;
    final prev = messages[index - 1];
    return !prev.isImage ||
        prev.isDeleted ||
        _hasGroupingBlockingCaption(prev) ||
        prev.senderId != msg.senderId ||
        msg.createdAt.difference(prev.createdAt).inMinutes.abs() > 2 ||
        !_isSameDay(msg.createdAt, prev.createdAt);
  }

  /// Returns indices of all consecutive non-deleted image messages from the
  /// same sender starting at [startIndex] going upward (older = higher index).
  List<int> _getImageGroup(List<ChatMessageModel> messages, int startIndex) {
    final msg = messages[startIndex];
    if (_hasGroupingBlockingCaption(msg)) return [startIndex];
    final group = [startIndex];
    for (int i = startIndex + 1; i < messages.length; i++) {
      final next = messages[i];
      if (!next.isImage ||
          next.isDeleted ||
          _hasGroupingBlockingCaption(next) ||
          next.senderId != msg.senderId) {
        break;
      }
      if (msg.createdAt.difference(next.createdAt).inMinutes.abs() > 2) break;
      if (!_isSameDay(msg.createdAt, next.createdAt)) break;
      group.add(i);
    }
    return group;
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  bool _hasGroupingBlockingCaption(ChatMessageModel message) {
    return message.caption?.trim().isNotEmpty == true;
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(date.year, date.month, date.day);

    if (d == today) return 'Today';
    if (d == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return DateFormat('MMM d, yyyy').format(date);
  }
}

class _InputIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _InputIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: AppColors.glassPrimary,
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Icon(icon, size: 18, color: AppColors.textSecondary),
      ),
    );
  }
}

