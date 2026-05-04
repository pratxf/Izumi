import 'dart:io';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:izumi/core/ui/app_icons.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;
import '../../services/permission_service.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';

/// Full-Screen Image Detail — 9:16 hero viewer with GPS overlay
class ImageDetailScreen extends StatefulWidget {
  final String imageUrl;
  final String? thumbnailUrl;
  final String location;
  final String capturedBy;
  final String employeeId;
  final DateTime timestamp;
  final String? category;
  final String? name;
  final String? phone;
  final String? customerType;
  final String? notes;
  final bool hasFollowUp;
  final double? latitude;
  final double? longitude;
  final bool isVerified;
  final String? heroTag;
  final bool showCoordinatesInOverlay;
  final bool showGeoOverlay;

  const ImageDetailScreen({
    super.key,
    required this.imageUrl,
    this.thumbnailUrl,
    required this.location,
    required this.capturedBy,
    required this.employeeId,
    required this.timestamp,
    this.category,
    this.name,
    this.phone,
    this.customerType,
    this.notes,
    this.hasFollowUp = false,
    this.latitude,
    this.longitude,
    this.isVerified = false,
    this.heroTag,
    this.showCoordinatesInOverlay = true,
    this.showGeoOverlay = true,
  });

  @override
  State<ImageDetailScreen> createState() => _ImageDetailScreenState();
}

class _ImageDetailScreenState extends State<ImageDetailScreen> {
  bool _isDownloading = false;

  // ─── Actions ────────────────────────────────────────────────────

  Future<void> _openOnMap() async {
    if (widget.latitude == null ||
        widget.longitude == null ||
        (widget.latitude == 0.0 && widget.longitude == 0.0)) {
      _showSnackBar('Location coordinates not available', isError: true);
      return;
    }
    final url = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${widget.latitude},${widget.longitude}',
    );
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {
      _showSnackBar('Could not open maps', isError: true);
    }
  }

  Future<void> _downloadImage() async {
    if (_isDownloading) return;
    setState(() => _isDownloading = true);

    try {
      final granted = await PermissionService().ensurePhotoLibraryAddPermission(
        context: context,
        title: 'Save to Photos',
        message:
            'Izumi needs photo library access to save images to your device.',
      );
      if (!granted) return;

      final response = await http.get(Uri.parse(widget.imageUrl));
      if (response.statusCode != 200) throw Exception('Download failed');

      final tempDir = Directory.systemTemp;
      final ext = p.extension(Uri.parse(widget.imageUrl).path);
      final fileName =
          'izumi_${DateTime.now().millisecondsSinceEpoch}${ext.isNotEmpty ? ext : '.jpg'}';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(response.bodyBytes);

      await Gal.putImage(file.path);
      await file.delete();

      _showSnackBar('Image saved to gallery');
    } catch (_) {
      _showSnackBar('Failed to save image', isError: true);
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.critical : AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ─── Build ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Blurred background fill — uses the cached thumbnail (already on
          // disk from the grid) so it appears immediately instead of flashing
          // white while the full image downloads.
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: CachedNetworkImage(
                imageUrl: (widget.thumbnailUrl?.isNotEmpty == true)
                    ? widget.thumbnailUrl!
                    : widget.imageUrl,
                fit: BoxFit.cover,
                fadeInDuration: Duration.zero,
                placeholder: (_, __) => const SizedBox.shrink(),
                errorWidget: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),
          Positioned.fill(
            child: Container(color: Colors.black.withValues(alpha: 0.6)),
          ),

          // Main content
          SafeArea(
            child: Column(
              children: [
                // Top bar
                _buildTopBar(),

                // 9:16 image with overlay
                Expanded(child: _buildImageViewer()),

                // Bottom action buttons
                _buildActionBar(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Top Bar ────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: () => context.pop(),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.12),
              ),
              child: const Icon(
                AppIcons.arrow_left_2,
                color: Colors.white,
                size: 22,
              ),
            ),
          ),
          Text(
            'Photo',
            style: AppTypography.bodyLarge.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 42),
        ],
      ),
    );
  }

  // ─── 9:16 Image Viewer with GPS Overlay ─────────────────────────

  Widget _buildImageViewer() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: AspectRatio(
          aspectRatio: 9 / 16,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Hero image
                _buildHeroImage(),

                if (widget.showGeoOverlay) ...[
                  // Bottom gradient for text readability
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 220,
                    child: IgnorePointer(
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black87],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // GPS + timestamp overlay
                  Positioned(
                    left: 14,
                    right: 14,
                    bottom: 14,
                    child: _buildGeoOverlay(),
                  ),
                ],

                // Top-right metadata badges
                Positioned(
                  top: 12,
                  right: 12,
                  child: _buildMetadataBadges(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroImage() {
    final thumb = widget.thumbnailUrl;
    final hasThumb =
        thumb != null && thumb.isNotEmpty && thumb != widget.imageUrl;

    final image = hasThumb
        ? _ProgressiveCachedImage(
            thumbnailUrl: thumb,
            fullUrl: widget.imageUrl,
          )
        : CachedNetworkImage(
            imageUrl: widget.imageUrl,
            fit: BoxFit.cover,
            fadeInDuration: const Duration(milliseconds: 150),
            placeholder: (_, __) => Container(
              color: AppColors.gradientStart,
              child: const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white38,
                  ),
                ),
              ),
            ),
            errorWidget: (_, __, ___) => Container(
              color: AppColors.gradientStart,
              child: const Center(
                child: Icon(AppIcons.image,
                    color: AppColors.textTertiary, size: 48),
              ),
            ),
          );

    if (widget.heroTag != null) {
      return Hero(tag: widget.heroTag!, child: image);
    }
    return image;
  }

  // ─── GPS / Location Overlay ─────────────────────────────────────

  Widget _buildGeoOverlay() {
    final hasLocation = widget.location.isNotEmpty;
    final hasCoords = widget.latitude != null &&
        widget.longitude != null &&
        !(widget.latitude == 0.0 && widget.longitude == 0.0);
    final formattedDate =
        DateFormat('dd MMM yyyy, hh:mm a').format(widget.timestamp);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasLocation)
          Row(
            children: [
              const Icon(AppIcons.location, size: 14, color: Colors.white),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.location,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        if (hasLocation) const SizedBox(height: 6),
        if (hasCoords && widget.showCoordinatesInOverlay)
          Row(
            children: [
              const Icon(AppIcons.gps, size: 12, color: Colors.white70),
              const SizedBox(width: 6),
              Text(
                'Lat ${widget.latitude!.toStringAsFixed(5)}\u00B0  '
                'Long ${widget.longitude!.toStringAsFixed(5)}\u00B0',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        if (hasCoords && widget.showCoordinatesInOverlay) const SizedBox(height: 4),
        Row(
          children: [
            const Icon(AppIcons.clock, size: 12, color: Colors.white70),
            const SizedBox(width: 6),
            Text(
              formattedDate,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        if (widget.capturedBy.isNotEmpty) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(AppIcons.user, size: 12, color: Colors.white70),
              const SizedBox(width: 6),
              Text(
                widget.capturedBy,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
        if (widget.name != null && widget.name!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(AppIcons.user_tag, size: 12, color: Colors.white70),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.name!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
        if (widget.phone != null && widget.phone!.isNotEmpty) ...[
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () {
              final uri = Uri(scheme: 'tel', path: widget.phone);
              launchUrl(uri);
            },
            child: Row(
              children: [
                const Icon(AppIcons.call, size: 12, color: Colors.white70),
                const SizedBox(width: 6),
                Text(
                  widget.phone!,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    decoration: TextDecoration.underline,
                    decorationColor: Colors.white54,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (widget.notes != null && widget.notes!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(AppIcons.note, size: 12, color: Colors.white70),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.notes!,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    fontStyle: FontStyle.italic,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  // ─── Top-Right Badges ───────────────────────────────────────────

  Widget _buildMetadataBadges() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (widget.isVerified)
          _buildBadge(
            'VERIFIED',
            AppColors.success.withValues(alpha: 0.85),
          ),
        if (widget.category != null) ...[
          const SizedBox(height: 6),
          _buildBadge(
            widget.category!.toUpperCase(),
            AppColors.primary.withValues(alpha: 0.85),
          ),
        ],
        if (widget.customerType != null && widget.customerType!.isNotEmpty) ...[
          const SizedBox(height: 6),
          _buildBadge(
            widget.customerType!.toUpperCase(),
            widget.customerType == 'new'
                ? AppColors.success.withValues(alpha: 0.85)
                : const Color(0xD93B82F6), // blue
          ),
        ],
        if (widget.hasFollowUp) ...[
          const SizedBox(height: 6),
          _buildBadge(
            'FOLLOW-UP',
            const Color(0xD9F59E0B), // amber/orange
          ),
        ],
      ],
    );
  }

  Widget _buildBadge(String label, Color bgColor) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: bgColor.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.14),
            ),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ),
      ),
    );
  }

  // ─── Bottom Action Bar ──────────────────────────────────────────

  Widget _buildActionBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: _buildActionButton(
              icon: AppIcons.map,
              label: 'View on Map',
              onTap: _openOnMap,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildActionButton(
              icon: _isDownloading ? AppIcons.timer : AppIcons.document_download,
              label: _isDownloading ? 'Saving...' : 'Download',
              onTap: _downloadImage,
            ),
          ),
        ],
      ),
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
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.15),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows the cached thumbnail instantly (shared cache with the grid tiles),
/// then fades the full-resolution image in on top when it finishes loading.
///
/// Both layers share the same `flutter_cache_manager` disk cache keyed by URL,
/// so a thumbnail already fetched by `PhotoTileImage` appears with no network
/// round-trip — eliminating the white flash.
class _ProgressiveCachedImage extends StatelessWidget {
  final String thumbnailUrl;
  final String fullUrl;
  const _ProgressiveCachedImage({
    required this.thumbnailUrl,
    required this.fullUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        CachedNetworkImage(
          imageUrl: thumbnailUrl,
          fit: BoxFit.cover,
          fadeInDuration: Duration.zero,
          placeholder: (_, __) => Container(color: AppColors.gradientStart),
          errorWidget: (_, __, ___) =>
              Container(color: AppColors.gradientStart),
        ),
        CachedNetworkImage(
          imageUrl: fullUrl,
          fit: BoxFit.cover,
          fadeInDuration: const Duration(milliseconds: 200),
          // Transparent placeholder so the thumbnail underneath shows through
          // while the full image is still downloading.
          placeholder: (_, __) => const SizedBox.shrink(),
          errorWidget: (_, __, ___) => const SizedBox.shrink(),
        ),
      ],
    );
  }
}
