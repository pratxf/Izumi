import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:izumi/core/ui/app_icons.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';
import '../../../models/chat_message_model.dart';
import 'swipe_to_reply_wrapper.dart';

class ChatImageGroupBubble extends StatelessWidget {
  final List<ChatMessageModel> messages;
  final bool isMe;
  final bool showSenderName;
  final void Function(ChatMessageModel)? onReply;
  final void Function(ChatMessageModel)? onDelete;

  const ChatImageGroupBubble({
    super.key,
    required this.messages,
    required this.isMe,
    this.showSenderName = true,
    this.onReply,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final newestMessage = messages.first;
    final captionMessage = messages.firstWhere(
      (message) => message.caption?.trim().isNotEmpty == true,
      orElse: () => newestMessage,
    );
    final captionText = captionMessage.caption?.trim();

    return Padding(
      padding: EdgeInsets.only(
        left: isMe ? 48 : 0,
        right: isMe ? 0 : 48,
        bottom: AppSpacing.sm,
      ),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: SwipeToReplyWrapper(
          enabled: onReply != null,
          isMe: isMe,
          onReply: () => onReply?.call(messages.first),
          child: GestureDetector(
            onLongPress: () => _showContextMenu(context),
            child: ClipRRect(
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(AppSpacing.radiusLg),
                topRight: const Radius.circular(AppSpacing.radiusLg),
                bottomLeft: Radius.circular(isMe ? AppSpacing.radiusLg : 4),
                bottomRight: Radius.circular(isMe ? 4 : AppSpacing.radiusLg),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: isMe
                        ? AppColors.primary.withValues(alpha: 0.25)
                        : AppColors.glassPrimary,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(AppSpacing.radiusLg),
                      topRight: const Radius.circular(AppSpacing.radiusLg),
                      bottomLeft:
                          Radius.circular(isMe ? AppSpacing.radiusLg : 4),
                      bottomRight:
                          Radius.circular(isMe ? 4 : AppSpacing.radiusLg),
                    ),
                    border: Border.all(
                      color: isMe
                          ? AppColors.primary.withValues(alpha: 0.4)
                          : AppColors.glassBorder,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!isMe && showSenderName) ...[
                        Padding(
                          padding: const EdgeInsets.only(
                            left: AppSpacing.xs,
                            bottom: AppSpacing.xs,
                          ),
                          child: Text(
                            newestMessage.senderName,
                            style: AppTypography.caption.copyWith(
                              color: AppColors.primaryLight,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                      _buildImageGrid(context),
                      if (captionText != null && captionText.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xs,
                          ),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 260),
                            child: Text(
                              captionText,
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.textSecondary,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.xs),
                      Padding(
                        padding: const EdgeInsets.only(left: AppSpacing.xs),
                        child: Text(
                          DateFormat.jm().format(newestMessage.createdAt),
                          style: AppTypography.small.copyWith(
                            color: AppColors.textTertiary,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImageGrid(BuildContext context) {
    const gap = 3.0;
    const totalWidth = 260.0;
    const halfWidth = (totalWidth - gap) / 2;

    final count = messages.length;

    if (count == 2) {
      return SizedBox(
        width: totalWidth,
        child: Row(
          children: [
            _imageCell(context, 0, halfWidth, 160),
            const SizedBox(width: gap),
            _imageCell(context, 1, halfWidth, 160),
          ],
        ),
      );
    }

    if (count == 3) {
      return SizedBox(
        width: totalWidth,
        child: Column(
          children: [
            Row(
              children: [
                _imageCell(context, 0, halfWidth, 130),
                const SizedBox(width: gap),
                _imageCell(context, 1, halfWidth, 130),
              ],
            ),
            const SizedBox(height: gap),
            _imageCell(context, 2, totalWidth, 130),
          ],
        ),
      );
    }

    // 4+ images: 2x2 grid, "+N" overlay on 4th if more
    return SizedBox(
      width: totalWidth,
      child: Column(
        children: [
          Row(
            children: [
              _imageCell(context, 0, halfWidth, 130),
              const SizedBox(width: gap),
              _imageCell(context, 1, halfWidth, 130),
            ],
          ),
          const SizedBox(height: gap),
          Row(
            children: [
              _imageCell(context, 2, halfWidth, 130),
              const SizedBox(width: gap),
              Stack(
                children: [
                  _imageCell(context, 3, halfWidth, 130),
                  if (count > 4)
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusSm),
                        child: Container(
                          color: Colors.black.withValues(alpha: 0.55),
                          alignment: Alignment.center,
                          child: Text(
                            '+${count - 4}',
                            style: AppTypography.h2.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _imageCell(
    BuildContext context,
    int index,
    double width,
    double height,
  ) {
    final message = messages[index];
    final imageUrl = message.thumbnailUrl ?? message.imageUrl ?? '';

    return GestureDetector(
      onTap: () => _openFullScreenGallery(context, index),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        child: SizedBox(
          width: width,
          height: height,
          child: Image.network(
            imageUrl,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return Container(
                color: AppColors.glassStrong,
                child: const Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                ),
              );
            },
            errorBuilder: (_, __, ___) => Container(
              color: AppColors.glassStrong,
              child: const Center(
                child: Icon(
                  AppIcons.image,
                  color: AppColors.textTertiary,
                  size: 24,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openFullScreenGallery(BuildContext context, int initialIndex) {
    final imageUrls = messages
        .map((m) => m.imageUrl ?? '')
        .where((url) => url.isNotEmpty)
        .toList();
    if (initialIndex >= imageUrls.length) initialIndex = 0;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FullScreenGallery(
          imageUrls: imageUrls,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  void _showContextMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: AppColors.glassStrong,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppSpacing.radiusLg),
          ),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(top: AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.textTertiary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              ListTile(
                leading:
                    const Icon(AppIcons.undo, color: AppColors.textPrimary),
                title: Text(
                  'Reply',
                  style: AppTypography.body
                      .copyWith(color: AppColors.textPrimary),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  onReply?.call(messages.first);
                },
              ),
              if (isMe)
                ListTile(
                  leading:
                      const Icon(AppIcons.trash, color: AppColors.error),
                  title: Text(
                    'Delete all',
                    style:
                        AppTypography.body.copyWith(color: AppColors.error),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _confirmDeleteAll(context);
                  },
                ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDeleteAll(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.glassStrong,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
        title: Text(
          'Delete ${messages.length} photos?',
          style: AppTypography.body.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'These photos will be deleted for everyone.',
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style:
                  AppTypography.body.copyWith(color: AppColors.textTertiary),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              for (final msg in messages) {
                onDelete?.call(msg);
              }
            },
            child: Text(
              'Delete',
              style: AppTypography.body.copyWith(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-screen gallery viewer with swipe navigation.
class _FullScreenGallery extends StatefulWidget {
  final List<String> imageUrls;
  final int initialIndex;

  const _FullScreenGallery({
    required this.imageUrls,
    required this.initialIndex,
  });

  @override
  State<_FullScreenGallery> createState() => _FullScreenGalleryState();
}

class _FullScreenGalleryState extends State<_FullScreenGallery> {
  late final PageController _pageController;
  late int _currentPage;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        title: Text(
          '${_currentPage + 1} / ${widget.imageUrls.length}',
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        centerTitle: true,
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.imageUrls.length,
        onPageChanged: (page) => setState(() => _currentPage = page),
        itemBuilder: (context, index) {
          return Center(
            child: InteractiveViewer(
              child: Image.network(
                widget.imageUrls[index],
                fit: BoxFit.contain,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.primary,
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
