import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:izumi/core/ui/app_icons.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';
import '../../providers/session_provider.dart';
import '../../services/permission_service.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  final PermissionService _permissionService = PermissionService();
  CameraController? _controller;
  Future<void>? _initializeControllerFuture;
  List<CameraDescription> _cameras = [];
  int _selectedCameraIndex = 0;
  FlashMode _flashMode = FlashMode.off;
  bool _permissionDenied = false;
  bool _isCapturingPhoto = false;

  late final DateTime _timestamp = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _setupCamera());
  }

  Future<void> _setupCamera() async {
    if (!mounted) return;
    final granted = await _permissionService.ensurePermission(
      context: context,
      permission: Permission.camera,
      title: 'Camera Access',
      message: 'Izumi needs camera access to capture geotagged field photos.',
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
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: Container(
              color: Colors.black,
              alignment: Alignment.center,
              child: AspectRatio(
                aspectRatio: 9 / 16,
                child: ClipRect(
                  child: _buildCameraPreview(),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
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
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildCameraHeader(context),
          ),
          Positioned(
            left: 12,
            bottom: 12,
            child: _buildGeoTagCard(),
          ),
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

  Widget _buildCameraHeader(BuildContext context) {
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
            onTap: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              'Camera',
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

  Widget _buildCameraPreview() {
    if (_permissionDenied) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              AppIcons.camera_slash,
              color: AppColors.textTertiary,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              'Camera permission required',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
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
    final session = context.watch<SessionProvider>();
    final locationName = session.currentLocation.isNotEmpty
        ? session.currentLocation
        : 'Fetching location...';
    final lat = session.currentLat;
    final lng = session.currentLng;
    final dateStr = _formatFullTimestamp(_timestamp);

    return GestureDetector(
      onTap: () => _openMap(lat, lng),
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
                        locationName,
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
                        'Lat ${lat.toStringAsFixed(5)}  •  Lng ${lng.toStringAsFixed(5)}',
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

  Future<void> _capturePhoto() async {
    if (_controller == null || _isCapturingPhoto) return;
    setState(() => _isCapturingPhoto = true);
    try {
      await _initializeControllerFuture;
      final file = await _controller!.takePicture();
      debugPrint('[CameraScreen] Captured photo temp path=${file.path}');
      if (!mounted) return;
      final session = context.read<SessionProvider>();
      final location = session.currentLocation.isNotEmpty
          ? session.currentLocation
          : 'Unknown location';
      context.push('/employee/camera/preview', extra: {
        'location': location,
        'timestamp': DateTime.now(),
        'imagePath': file.path,
      });
    } catch (e) {
      debugPrint('[CameraScreen] Photo capture failed: $e');
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
