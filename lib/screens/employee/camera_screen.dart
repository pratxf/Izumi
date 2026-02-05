import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import '../../core/constants/app_colors.dart';

/// Professional Geotagged Field Camera Screen
/// Layout based on "Professional Geotagged Field Camera" HTML reference
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  // Mock modes
  final List<String> _modes = ['SCAN', 'PHOTO', 'VIDEO'];
  int _selectedModeIndex = 1;

  @override
  Widget build(BuildContext context) {
    // Full screen setup
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Camera Preview (Simulated with Image)
          // In a real app, this would be the CameraPreview widget
          Positioned.fill(
            child: Image.network(
              'https://lh3.googleusercontent.com/aida-public/AB6AXuDXrkzGTir6h0zq4lOJJayxXYEY1-VeAtRMtEJKArikef3QbopkLIpLJ7GDuCoRdnvvLENXcclbmc5TOq8-MrC-7EW81QzGttoYw-vanRvFut-LEHclPcVWl9xVDF6ZH_-CtTOK3oo0JB0kTDzjda6LCpDZkyzQbfLS4aqbYFXnGRmwyiwJPSVEqRHFe_3iVZoj_v_Lblg6CghyRL1g_oKNdJXFaG0o_mHBXpzf8kC3hOntnOE64Q0zdMk2V0UrK9N7pCrkKV-vcelA',
              fit: BoxFit.cover,
            ),
          ),

          // 2. Vignette Overlay
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.6),
                  ],
                  radius: 1.0,
                  stops: const [0.5, 1.0],
                ),
              ),
            ),
          ),

          // 3. Top Control Bar (Close, Live Indicator, Flash)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Close Button
                    _buildGlassCircleButton(
                      icon: Icons.close,
                      onTap: () => Navigator.pop(context),
                    ),

                    // Live Indicator
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: Colors.redAccent,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.redAccent.withValues(
                                        alpha: 0.8,
                                      ),
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'FIELD LIVE',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Flash Button
                    _buildGlassCircleButton(
                      icon: Icons.flash_on,
                      onTap: () {
                        // Toggle flash
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 4. Center Reticle
          Center(
            child: Container(
              width: 256,
              height: 256,
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.3),
                  width: 0.5,
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Stack(
                children: [
                  // Corners
                  _buildCorner(Alignment.topLeft),
                  _buildCorner(Alignment.topRight),
                  _buildCorner(Alignment.bottomLeft),
                  _buildCorner(Alignment.bottomRight),
                  // Center Dot
                  Center(
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 5. Glass Watermark (Bottom Left)
          Positioned(
            left: 24,
            bottom: 180, // Above bottom controls
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  width: 280,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 32,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Location Header
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: const [
                                BoxShadow(color: Colors.black12, blurRadius: 4),
                              ],
                            ),
                            child: const Icon(
                              Iconsax.location,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Rajendra Nagar',
                                style: TextStyle(
                                  color: Color(0xFF0F172A), // Slate 900
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  height: 1,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'FIELD INTELLIGENCE OVERLAY',
                                style: TextStyle(
                                  color: const Color(0xFF64748B), // Slate 500
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        height: 1,
                        color: const Color(0xFFCBD5E1).withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 12),
                      // Details Grid
                      Row(
                        children: [
                          Expanded(
                            child: _buildWatermarkDetail('DATE', '04 Feb 2026'),
                          ),
                          Expanded(
                            child: _buildWatermarkDetail('TIME', '14:32:15 PM'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 1,
                        color: const Color(0xFFF1F5F9), // Slate 100
                      ),
                      const SizedBox(height: 8),
                      _buildWatermarkDetail(
                        'COORDINATES',
                        'Lat: 17.4065° N | Long: 78.4842° E',
                        isCoordinates: true,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 6. Bottom Control Panel (Gradient bg)
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
                    Colors.black.withValues(alpha: 0.9),
                    Colors.black.withValues(alpha: 0.4),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Mode Selector
                  SizedBox(
                    height: 30,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: _modes.asMap().entries.map((entry) {
                        final index = entry.key;
                        final mode = entry.value;
                        final isSelected = index == _selectedModeIndex;
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: GestureDetector(
                            onTap: () {
                              setState(() => _selectedModeIndex = index);
                            },
                            child: Column(
                              children: [
                                Text(
                                  mode,
                                  style: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.white.withValues(alpha: 0.4),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 2,
                                  ),
                                ),
                                if (isSelected) ...[
                                  const SizedBox(height: 6),
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: AppColors.primary,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.primary.withValues(
                                            alpha: 0.8,
                                          ),
                                          blurRadius: 10,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 40),

                  // Main Controls
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Gallery Thumbnail
                        _buildSquareGlassButton(
                          isThumbnail: true,
                          thumbnailUrl:
                              'https://lh3.googleusercontent.com/aida-public/AB6AXuDXrkzGTir6h0zq4lOJJayxXYEY1-VeAtRMtEJKArikef3QbopkLIpLJ7GDuCoRdnvvLENXcclbmc5TOq8-MrC-7EW81QzGttoYw-vanRvFut-LEHclPcVWl9xVDF6ZH_-CtTOK3oo0JB0kTDzjda6LCpDZkyzQbfLS4aqbYFXnGRmwyiwJPSVEqRHFe_3iVZoj_v_Lblg6CghyRL1g_oKNdJXFaG0o_mHBXpzf8kC3hOntnOE64Q0zdMk2V0UrK9N7pCrkKV-vcelA',
                        ),

                        // Shutter Button
                        GestureDetector(
                          onTap: () {},
                          child: Container(
                            width: 80,
                            height: 80,
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                            ),
                            child: Container(
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.2,
                                    ),
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
                                      color: Colors.white.withValues(
                                        alpha: 0.3,
                                      ),
                                      width: 2,
                                    ),
                                  ),
                                  child: Center(
                                    child: Container(
                                      width: 8,
                                      height: 8,
                                      decoration: const BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Switch Camera Button
                        _buildSquareGlassButton(
                          icon: Icons.cameraswitch_outlined,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassCircleButton({
    required IconData icon,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.2),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }

  Widget _buildSquareGlassButton({
    IconData? icon,
    bool isThumbnail = false,
    String? thumbnailUrl,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: isThumbnail && thumbnailUrl != null
              ? Image.network(
                  thumbnailUrl,
                  fit: BoxFit.cover,
                  opacity: const AlwaysStoppedAnimation(0.8),
                )
              : Icon(icon, color: Colors.white, size: 28),
        ),
      ),
    );
  }

  Widget _buildCorner(Alignment alignment) {
    // Logic to determine border sides specific to corner
    bool isTop = alignment.y == -1.0;
    bool isLeft = alignment.x == -1.0;

    return Align(
      alignment: alignment,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          border: Border(
            top: isTop
                ? const BorderSide(color: Colors.white, width: 2)
                : BorderSide.none,
            bottom: !isTop
                ? const BorderSide(color: Colors.white, width: 2)
                : BorderSide.none,
            left: isLeft
                ? const BorderSide(color: Colors.white, width: 2)
                : BorderSide.none,
            right: !isLeft
                ? const BorderSide(color: Colors.white, width: 2)
                : BorderSide.none,
          ),
          borderRadius: BorderRadius.only(
            topLeft: isTop && isLeft ? const Radius.circular(12) : Radius.zero,
            topRight: isTop && !isLeft
                ? const Radius.circular(12)
                : Radius.zero,
            bottomLeft: !isTop && isLeft
                ? const Radius.circular(12)
                : Radius.zero,
            bottomRight: !isTop && !isLeft
                ? const Radius.circular(12)
                : Radius.zero,
          ),
        ),
      ),
    );
  }

  Widget _buildWatermarkDetail(
    String label,
    String value, {
    bool isCoordinates = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF94A3B8), // Slate 400
            fontSize: 8,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 2),
        isCoordinates
            ? Row(
                children: [
                  Text(
                    'Lat: 17.4065° N',
                    style: TextStyle(
                      color: const Color(0xFF1E293B), // Slate 800
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      '|',
                      style: TextStyle(
                        color: const Color(0xFFCBD5E1), // Slate 300
                      ),
                    ),
                  ),
                  Text(
                    'Long: 78.4842° E',
                    style: TextStyle(
                      color: const Color(0xFF1E293B), // Slate 800
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              )
            : Text(
                value,
                style: const TextStyle(
                  color: Color(0xFF1E293B), // Slate 800
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ],
    );
  }
}
