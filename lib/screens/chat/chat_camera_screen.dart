import 'dart:io';
import 'dart:async';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:izumi/core/ui/app_icons.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_typography.dart';
import '../../models/chat_message_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../services/location_service.dart';
import '../../services/permission_service.dart';

/// Camera screen for chat – captures geotagged photos and sends to a chat group.
class ChatCameraScreen extends StatefulWidget {
  final String groupId;
  final String groupName;

  const ChatCameraScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  State<ChatCameraScreen> createState() => _ChatCameraScreenState();
}

class _ChatCameraScreenState extends State<ChatCameraScreen> {
  static const double _cameraFrameAspectRatio = 9 / 16;
  final PermissionService _permissionService = PermissionService();
  final LocationService _locationService = LocationService();
  CameraController? _controller;
  Future<void>? _initializeControllerFuture;
  List<CameraDescription> _cameras = [];
  int _selectedCameraIndex = 0;
  FlashMode _flashMode = FlashMode.off;
  bool _permissionDenied = false;
  bool _isCapturingPhoto = false;

  // Location state
  String _locationName = 'Fetching location...';
  double _lat = 0.0;
  double _lng = 0.0;

  // Preview state
  String? _capturedImagePath;
  DateTime? _capturedTimestamp;
  bool _isSending = false;
  final TextEditingController _captionController = TextEditingController();
  final GlobalKey _stampedPreviewKey = GlobalKey();

  late final DateTime _timestamp = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupCamera();
      _fetchLocation();
    });
  }

  Future<void> _fetchLocation() async {
    try {
      final permissionResult = await _locationService.checkPermissions();
      if (permissionResult != LocationPermissionResult.granted) {
        return;
      }
      final position = await _locationService.getCurrentPosition();
      final address = await _locationService.getAddressFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (mounted) {
        setState(() {
          _lat = position.latitude;
          _lng = position.longitude;
          _locationName = address;
        });
      }
    } catch (e) {
      debugPrint('[ChatCamera] Location fetch failed: $e');
    }
  }

  Future<void> _setupCamera() async {
    if (!mounted) return;
    final granted = await _permissionService.ensurePermission(
      context: context,
      permission: Permission.camera,
      title: 'Camera Access',
      message: 'Izumi needs camera access to capture geotagged photos.',
    );
    if (!granted) {
      if (mounted) setState(() => _permissionDenied = true);
      return;
    }
    if (mounted) setState(() => _permissionDenied = false);

    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        if (mounted) setState(() {});
        return;
      }
      await _initializeCamera(_cameras[_selectedCameraIndex]);
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  Future<void> _initializeCamera(CameraDescription description) async {
    await _controller?.dispose();
    final controller = CameraController(
      description,
      ResolutionPreset.high,
      enableAudio: false,
    );
    _controller = controller;
    _initializeControllerFuture = controller.initialize();
    try {
      await _initializeControllerFuture;
      await controller.setFlashMode(_flashMode);
    } catch (_) {}
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller?.dispose();
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _capturePhoto() async {
    if (_controller == null || _isCapturingPhoto) return;
    setState(() => _isCapturingPhoto = true);
    try {
      await _initializeControllerFuture;
      final file = await _controller!.takePicture();
      if (!mounted) return;
      setState(() {
        _capturedImagePath = file.path;
        _capturedTimestamp = DateTime.now();
      });
    } catch (e) {
      debugPrint('[ChatCamera] Photo capture failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to capture photo')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCapturingPhoto = false);
      }
    }
  }

  Future<void> _sendPhoto() async {
    if (_capturedImagePath == null || _isSending) return;

    setState(() => _isSending = true);

    final authProvider = context.read<AuthProvider>();
    final chatProvider = context.read<ChatProvider>();
    final userId = authProvider.currentUser?.id ?? '';
    final userName = authProvider.currentUser?.name ?? '';
    final enterpriseId = authProvider.enterpriseId ?? '';

    final note = _captionController.text.trim();
    final stampedImageFile = await _buildStampedPreviewFile();
    final imageFile = stampedImageFile ?? File(_capturedImagePath!);
    if (!mounted) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    navigator.pop();

    unawaited(() async {
      final success = await chatProvider.sendImageMessage(
        groupId: widget.groupId,
        enterpriseId: enterpriseId,
        imageFile: imageFile,
        senderId: userId,
        senderName: userName,
        caption: note.isEmpty ? null : note,
        latitude: _lat,
        longitude: _lng,
        address: _locationName != 'Fetching location...' ? _locationName : null,
      );

      if (!success) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Failed to send photo')),
        );
      }
    }());
  }

  Future<File?> _buildStampedPreviewFile() async {
    try {
      final boundary = _stampedPreviewKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return null;

      final image = await boundary.toImage(pixelRatio: 3);
      final byteData = await image.toByteData(format: ImageByteFormat.png);
      if (byteData == null) return null;

      final directory = await getTemporaryDirectory();
      final stampedPath = path.join(
        directory.path,
        'chat_stamp_${DateTime.now().microsecondsSinceEpoch}.png',
      );
      final stampedFile = File(stampedPath);
      await stampedFile.writeAsBytes(byteData.buffer.asUint8List());
      return stampedFile;
    } catch (e) {
      debugPrint('[ChatCamera] Failed to build stamped preview image: $e');
      return null;
    }
  }

  void _retakePhoto() {
    setState(() {
      _capturedImagePath = null;
      _capturedTimestamp = null;
      _captionController.clear();
    });
  }

  Future<void> _toggleFlash() async {
    if (_controller == null) return;
    setState(() {
      _flashMode =
          _flashMode == FlashMode.off ? FlashMode.torch : FlashMode.off;
    });
    try {
      await _controller!.setFlashMode(_flashMode);
    } catch (_) {}
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;
    _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras.length;
    await _initializeCamera(_cameras[_selectedCameraIndex]);
  }

  @override
  Widget build(BuildContext context) {
    // Show preview mode after capture
    if (_capturedImagePath != null) {
      return _buildPreviewMode();
    }
    return _buildCameraMode();
  }

  // ── Camera Mode ──────────────────────────────────────────────────────

  Widget _buildCameraMode() {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Camera preview
          Positioned.fill(
            child: Container(
              color: Colors.black,
              alignment: Alignment.center,
              child: AspectRatio(
                aspectRatio: _cameraFrameAspectRatio,
                child: ClipRect(child: _buildCameraPreview()),
              ),
            ),
          ),

          // Dark vignette overlay
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.45),
                  ],
                  radius: 1.08,
                  stops: const [0.7, 1.0],
                ),
              ),
            ),
          ),

          // Header
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildCameraHeader(
              context,
              title: 'Chat Camera',
              onBackTap: () => Navigator.of(context).pop(),
            ),
          ),

          // Geotag overlay
          Positioned(
            left: 12,
            bottom: 12,
            child: _buildGeoTagCard(),
          ),

          // Bottom controls
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.only(bottom: 48, top: 24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.72),
                    Colors.black.withValues(alpha: 0.28),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const SizedBox(width: 56),
                    // Shutter
                    GestureDetector(
                      onTap: _isCapturingPhoto ? null : _capturePhoto,
                      child: Container(
                        width: 80,
                        height: 80,
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.glassBorder,
                            width: 3,
                          ),
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withValues(alpha: 0.2),
                                blurRadius: 16,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: Center(
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.glassBorder,
                                  width: 2,
                                ),
                              ),
                              child: const Center(
                                child: SizedBox(
                                  width: 8,
                                  height: 8,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: AppColors.textPrimary,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Switch camera
                    _buildSquareGlassButton(
                      icon: AppIcons.camera,
                      onTap: _switchCamera,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Preview Mode ─────────────────────────────────────────────────────

  Widget _buildPreviewMode() {
    final reply = context.watch<ChatProvider>().replyingTo;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Captured image
          Positioned.fill(
            child: Container(
              color: Colors.black,
              alignment: Alignment.center,
              child: AspectRatio(
                aspectRatio: _cameraFrameAspectRatio,
                child: RepaintBoundary(
                  key: _stampedPreviewKey,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.file(
                        File(_capturedImagePath!),
                        fit: BoxFit.cover,
                      ),
                      Positioned(
                        left: 12,
                        bottom: 12,
                        child: _buildGeoTagCard(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Dark vignette
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.45),
                  ],
                  radius: 1.08,
                  stops: const [0.7, 1.0],
                ),
              ),
            ),
          ),

          // Header
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildCameraHeader(
              context,
              title: 'Preview',
              onBackTap: _retakePhoto,
            ),
          ),

          // Bottom: retake + send
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).padding.bottom + 18,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.72),
                    Colors.black.withValues(alpha: 0.28),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (reply != null) ...[
                    _buildReplyPreview(reply),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(28),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(28),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.22),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  _buildComposerActionButton(
                                    icon: AppIcons.refresh,
                                    onTap: _retakePhoto,
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  Expanded(
                                    child: _buildCaptionField(),
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  _buildComposerSendButton(),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Shared Widgets ───────────────────────────────────────────────────

  Widget _buildCameraHeader(
    BuildContext context, {
    required String title,
    required VoidCallback onBackTap,
  }) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Container(
      padding: EdgeInsets.fromLTRB(20, topPadding + 12, 20, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.4),
            Colors.black.withValues(alpha: 0.12),
            Colors.transparent,
          ],
        ),
      ),
      child: Row(
        children: [
          _buildHeaderButton(
            icon: AppIcons.arrow_left_2,
            onTap: onBackTap,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              title,
              style: AppTypography.h3.copyWith(color: Colors.white),
            ),
          ),
          _buildHeaderButton(
            icon: _flashMode == FlashMode.off
                ? AppIcons.flash_slash
                : AppIcons.flash,
            onTap: _toggleFlash,
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.18),
          ),
        ),
        child: Icon(
          icon,
          size: 22,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildSquareGlassButton({
    required IconData icon,
    VoidCallback? onTap,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.glassPrimary,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Icon(icon, color: AppColors.textPrimary, size: 28),
          ),
        ),
      ),
    );
  }

  Widget _buildCaptionField() {
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      alignment: Alignment.center,
      child: TextField(
        controller: _captionController,
        style: AppTypography.body.copyWith(
          color: Colors.white,
        ),
        cursorColor: Colors.white,
        minLines: 1,
        maxLines: 3,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          hintText: 'Add a caption...',
          hintStyle: AppTypography.body.copyWith(
            color: Colors.white.withValues(alpha: 0.7),
          ),
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md,
          ),
        ),
      ),
    );
  }

  Widget _buildComposerActionButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.18),
          ),
        ),
        child: Icon(
          icon,
          color: Colors.white,
          size: 22,
        ),
      ),
    );
  }

  Widget _buildComposerSendButton() {
    return GestureDetector(
      onTap: _isSending ? null : _sendPhoto,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: AppColors.primary,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.26),
              blurRadius: 14,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Center(
          child: _isSending
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Colors.white,
                  ),
                )
              : const Icon(
                  AppIcons.send_1,
                  color: Colors.white,
                  size: 22,
                ),
        ),
      ),
    );
  }

  Widget _buildReplyPreview(ChatMessageModel reply) {
    final isReplyImage = reply.isImage;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.glassHeader,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          if (isReplyImage && reply.imageUrl != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(
                reply.imageUrl!,
                width: 36,
                height: 36,
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
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (_permissionDenied) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(AppIcons.camera_slash,
                color: AppColors.textTertiary, size: 48),
            const SizedBox(height: 16),
            Text(
              'Camera permission required',
              style: AppTypography.bodyMedium
                  .copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _setupCamera,
              child: Text(
                'Try Again',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (_controller == null || _initializeControllerFuture == null) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: const Icon(
          AppIcons.camera_slash,
          color: AppColors.textTertiary,
          size: 48,
        ),
      );
    }
    return FutureBuilder<void>(
      future: _initializeControllerFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          final preview = CameraPreview(_controller!);
          return ClipRect(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _controller!.value.previewSize?.height ?? 0,
                height: _controller!.value.previewSize?.width ?? 0,
                child: preview,
              ),
            ),
          );
        }
        return Container(
          color: Colors.black,
          alignment: Alignment.center,
          child: const CircularProgressIndicator(
            color: AppColors.textPrimary,
          ),
        );
      },
    );
  }

  Widget _buildGeoTagCard() {
    final dateStr = _formatFullTimestamp(_capturedTimestamp ?? _timestamp);

    return GestureDetector(
      onTap: () => _openMap(_lat, _lng),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 200),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    AppIcons.location,
                    color: Colors.white,
                    size: 13,
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _locationName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.small.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Lat ${_lat.toStringAsFixed(5)}  •  Lng ${_lng.toStringAsFixed(5)}',
                        style: AppTypography.small.copyWith(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 8,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        dateStr,
                        style: AppTypography.small.copyWith(
                          color: Colors.white.withValues(alpha: 0.72),
                          fontSize: 8,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatFullTimestamp(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString().substring(2);
    final hour =
        date.hour > 12 ? date.hour - 12 : (date.hour == 0 ? 12 : date.hour);
    final hourStr = hour.toString().padLeft(2, '0');
    final min = date.minute.toString().padLeft(2, '0');
    final amPm = date.hour >= 12 ? 'PM' : 'AM';
    final offset = date.timeZoneOffset;
    final offsetHours = offset.inHours.abs().toString().padLeft(2, '0');
    final offsetMins =
        (offset.inMinutes.remainder(60)).abs().toString().padLeft(2, '0');
    final sign = offset.isNegative ? '-' : '+';
    return '$day/$month/$year $hourStr:$min $amPm GMT $sign$offsetHours:$offsetMins';
  }

  Future<void> _openMap(double lat, double lng) async {
    if (lat == 0.0 && lng == 0.0) return;
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
