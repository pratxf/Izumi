import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:izumi/core/ui/app_icons.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';
import '../../../models/chat_message_model.dart';
import '../../../models/upload_status.dart';
import '../../employee/image_detail_screen.dart';
import 'swipe_to_reply_wrapper.dart';

class ChatMessageBubble extends StatelessWidget {
  final ChatMessageModel message;
  final bool isMe;
  final bool showSenderName;
  final VoidCallback? onImageTap;
  final void Function(ChatMessageModel)? onReply;
  final void Function(ChatMessageModel)? onDelete;
  final VoidCallback? onRetry;

  const ChatMessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.showSenderName = true,
    this.onImageTap,
    this.onReply,
    this.onDelete,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: isMe ? 48 : 0,
        right: isMe ? 0 : 48,
        bottom: AppSpacing.sm,
      ),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: SwipeToReplyWrapper(
          enabled: !message.isDeleted && onReply != null,
          isMe: isMe,
          onReply: () => onReply?.call(message),
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
                  padding: const EdgeInsets.all(AppSpacing.md),
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
                        Text(
                          message.senderName,
                          style: AppTypography.caption.copyWith(
                            color: AppColors.primaryLight,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                      ],
                      if (message.hasReply) ...[
                        _buildReplyPreview(),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                      _buildContent(context),
                      const SizedBox(height: AppSpacing.xs),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _formatTime(message.createdAt),
                            style: AppTypography.small.copyWith(
                              color: AppColors.textTertiary,
                              fontSize: 11,
                            ),
                          ),
                          if (isMe) ...[
                            const SizedBox(width: AppSpacing.xs),
                            _buildUploadStatusIndicator(),
                          ],
                        ],
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

  Widget _buildReplyPreview() {
    final isReplyImage = message.replyToType == 'image';
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.glassStrong,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border(
          left: BorderSide(
            color: AppColors.primaryLight,
            width: 3,
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  message.replyToSenderName ?? '',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.primaryLight,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                if (isReplyImage)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(AppIcons.camera,
                          size: 14, color: AppColors.textTertiary),
                      const SizedBox(width: 4),
                      Text(
                        'Photo',
                        style: AppTypography.small.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  )
                else
                  Text(
                    message.replyToText ?? '',
                    style: AppTypography.small.copyWith(
                      color: AppColors.textTertiary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (isReplyImage && message.replyToImageUrl != null) ...[
            const SizedBox(width: AppSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.network(
                message.replyToImageUrl!,
                width: 40,
                height: 40,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (message.isDeleted) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(AppIcons.forbidden_2, size: 14, color: AppColors.textTertiary),
          const SizedBox(width: AppSpacing.xs),
          Text(
            'This message was deleted',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textTertiary,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      );
    }

    switch (message.type) {
      case 'image':
        return _buildImageContent(context);
      case 'location':
        return _buildLocationContent(context);
      default:
        return _buildTextContent();
    }
  }

  Widget _buildTextContent() {
    return Text(
      message.text ?? '',
      style: AppTypography.body.copyWith(
        color: AppColors.textPrimary,
      ),
    );
  }

  Widget _buildImageContent(BuildContext context) {
    final metadata = _ImageCaptionMetadata.fromCaption(message.caption);
    final displayLocation = message.address?.isNotEmpty == true
        ? message.address
        : metadata.location;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onImageTap ??
              () => _showFullScreenImage(context, message.imageUrl!),
          child: ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(14),
              bottomRight: Radius.circular(14),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 260,
                maxHeight: 320,
                minWidth: 220,
              ),
              child: Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 4 / 5,
                    child: Image.network(
                      message.imageUrl ?? '',
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
                            size: 32,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (displayLocation != null)
                    Positioned(
                      left: 12,
                      bottom: 12,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 180),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.28),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.14),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  AppIcons.location,
                                  size: 12,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    displayLocation,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTypography.small.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (metadata.primaryName != null ||
            metadata.notes != null ||
            metadata.extraDetails.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (metadata.primaryName != null)
                  Text(
                    metadata.primaryName!,
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                if (metadata.notes != null) ...[
                  if (metadata.primaryName != null)
                    const SizedBox(height: AppSpacing.xs),
                  Text(
                    metadata.notes!,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ],
                if (metadata.extraDetails.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Theme(
                    data: Theme.of(context).copyWith(
                      dividerColor: Colors.transparent,
                    ),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: EdgeInsets.zero,
                      dense: true,
                      collapsedShape: const RoundedRectangleBorder(
                        side: BorderSide(color: Colors.transparent),
                      ),
                      shape: const RoundedRectangleBorder(
                        side: BorderSide(color: Colors.transparent),
                      ),
                      iconColor: AppColors.primary,
                      collapsedIconColor: AppColors.primary,
                      title: Text(
                        'View Details',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      children: metadata.extraDetails
                          .map(
                            (detail) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                detail,
                                style: AppTypography.small.copyWith(
                                  color: AppColors.textSecondary,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ] else if (message.caption != null && message.caption!.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Text(
              message.caption!,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildUploadStatusIndicator() {
    switch (message.uploadStatus) {
      case UploadStatus.pending:
        return const Icon(
          AppIcons.clock,
          size: 14,
          color: AppColors.textTertiary,
        );
      case UploadStatus.success:
        return const Icon(
          AppIcons.tick_circle,
          size: 14,
          color: AppColors.textTertiary,
        );
      case UploadStatus.error:
        return GestureDetector(
          onTap: onRetry,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                AppIcons.refresh_circle,
                size: 14,
                color: AppColors.error,
              ),
              if (message.errorMessage != null &&
                  message.errorMessage!.isNotEmpty) ...[
                const SizedBox(width: 4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: Text(
                    message.errorMessage!,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.error,
                      fontSize: 10,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        );
    }
  }

  Widget _buildLocationContent(BuildContext context) {
    return GestureDetector(
      onTap: () => _openInMaps(message.latitude!, message.longitude!),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.glassStrong,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: const Icon(
                AppIcons.location,
                color: AppColors.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.address ?? 'Shared Location',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Tap to open in Maps',
                    style: AppTypography.small.copyWith(
                      color: AppColors.primaryLight,
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

  void _showContextMenu(BuildContext context) {
    if (message.isDeleted) return;

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
                leading: const Icon(AppIcons.undo, color: AppColors.textPrimary),
                title: Text(
                  'Reply',
                  style:
                      AppTypography.body.copyWith(color: AppColors.textPrimary),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  onReply?.call(message);
                },
              ),
              if (isMe)
                ListTile(
                  leading: const Icon(AppIcons.trash, color: AppColors.error),
                  title: Text(
                    'Delete',
                    style: AppTypography.body.copyWith(color: AppColors.error),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _confirmDelete(context);
                  },
                ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.glassStrong,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
        title: Text(
          'Delete message?',
          style: AppTypography.body.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'This message will be deleted for everyone.',
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: AppTypography.body.copyWith(color: AppColors.textTertiary),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              onDelete?.call(message);
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

  String _formatTime(DateTime dateTime) {
    return DateFormat.jm().format(dateTime);
  }

  void _showFullScreenImage(BuildContext context, String imageUrl) {
    final meta = _ImageCaptionMetadata.fromCaption(message.caption);
    Navigator.of(context).push(
      PageRouteBuilder(
        barrierColor: Colors.black,
        pageBuilder: (_, __, ___) => ImageDetailScreen(
          imageUrl: imageUrl,
          thumbnailUrl: message.thumbnailUrl,
          location: message.address ?? meta.location ?? '',
          capturedBy: message.senderName,
          employeeId: message.senderId,
          timestamp: message.createdAt,
          latitude: message.latitude,
          longitude: message.longitude,
          name: meta.primaryName,
          notes: meta.notes,
          showCoordinatesInOverlay: false,
          showGeoOverlay: false,
        ),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: animation,
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 200),
      ),
    );
  }

  Future<void> _openInMaps(double lat, double lng) async {
    final uri =
        Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class _ImageCaptionMetadata {
  const _ImageCaptionMetadata({
    this.location,
    this.primaryName,
    this.notes,
    this.extraDetails = const [],
  });

  final String? location;
  final String? primaryName;
  final String? notes;
  final List<String> extraDetails;

  factory _ImageCaptionMetadata.fromCaption(String? caption) {
    if (caption == null || caption.trim().isEmpty) {
      return const _ImageCaptionMetadata();
    }

    final lines = caption
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    String? location;
    String? primaryName;
    String? notes;
    final details = <String>[];

    for (final line in lines) {
      final lower = line.toLowerCase();
      if (lower.startsWith('location:')) {
        location = line.substring(line.indexOf(':') + 1).trim();
      } else if (lower.startsWith('name:')) {
        primaryName = line.substring(line.indexOf(':') + 1).trim();
      } else if (lower.startsWith('notes:')) {
        notes = line.substring(line.indexOf(':') + 1).trim();
      } else {
        details.add(line);
      }
    }

    return _ImageCaptionMetadata(
      location: location,
      primaryName: primaryName,
      notes: notes,
      extraDetails: details,
    );
  }
}

