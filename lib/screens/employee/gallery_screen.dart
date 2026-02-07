import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_shadows.dart';
import '../../core/constants/app_typography.dart';
import '../../widgets/glass/gradient_background.dart';
import '../../widgets/navigation/app_header.dart';
import '../../widgets/inputs/text_input_field.dart';
import 'camera_screen.dart';
import 'image_detail_screen.dart';

/// Employee Gallery Screen - Photo gallery with glassmorphism design
class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  final _searchController = TextEditingController();

  // Mock photo data grouped by date
  final List<Map<String, dynamic>> _photoGroups = [
    {
      'title': 'Today',
      'count': 15,
      'photos': [
        {'time': '14:32', 'url': 'https://picsum.photos/seed/1/200'},
        {'time': '14:15', 'url': 'https://picsum.photos/seed/2/200'},
        {'time': '13:48', 'url': 'https://picsum.photos/seed/3/200'},
        {'time': '11:20', 'url': 'https://picsum.photos/seed/4/200'},
        {'time': '10:05', 'url': 'https://picsum.photos/seed/5/200'},
        {'time': '09:55', 'url': 'https://picsum.photos/seed/6/200'},
      ],
    },
    {
      'title': 'Yesterday',
      'count': 8,
      'photos': [
        {'time': '16:45', 'url': 'https://picsum.photos/seed/7/200'},
        {'time': '15:30', 'url': 'https://picsum.photos/seed/8/200'},
        {'time': '14:10', 'url': 'https://picsum.photos/seed/9/200'},
      ],
    },
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const AppHeader(
              title: 'Gallery',
              type: AppHeaderType.secondary,
              showAvatar: false,
            ),

            // Content
            Expanded(
              child: Stack(
                children: [
                  CustomScrollView(
                    slivers: [
                      // Search Bar (sticky)
                      SliverPersistentHeader(
                        pinned: true,
                        delegate: _SearchBarDelegate(
                          controller: _searchController,
                        ),
                      ),

                      // Photo Groups
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate((
                            context,
                            index,
                          ) {
                            final group = _photoGroups[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: _buildPhotoGroup(group),
                            );
                          }, childCount: _photoGroups.length),
                        ),
                      ),
                    ],
                  ),

                  // Camera FAB
                  Positioned(
                    right: 24,
                    bottom: 120,
                    child: GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const CameraScreen(),
                          ),
                        );
                      },
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.glassBorder,
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.3),
                              blurRadius: 16,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Iconsax.camera,
                          color: AppColors.textPrimary,
                          size: 24,
                        ),
                      ),
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

  Widget _buildPhotoGroup(Map<String, dynamic> group) {
    final photos = group['photos'] as List;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: AppColors.glassPanelGradient,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.glassBorder),
            boxShadow: AppShadows.glass,
          ),
          child: Column(
            children: [
              // Group Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    group['title'],
                    style: AppTypography.bodyLarge.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.glassStrong,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.glassBorder),
                    ),
                    child: Text(
                      '${group['count']} PHOTOS',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Photo Grid
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: photos.length,
                itemBuilder: (context, index) {
                  final photo = photos[index];
                  return _buildPhotoTile(photo, group['title']);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoTile(Map<String, dynamic> photo, String groupTitle) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ImageDetailScreen(
              imageUrl: photo['url'],
              location: groupTitle,
              capturedBy: 'You',
              employeeId: 'EMP-01',
              timestamp: DateTime.now(),
            ),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: AppColors.glassStrong,
          border: Border.all(color: AppColors.glassBorder),
          boxShadow: AppShadows.glass,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                photo['url'],
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: AppColors.glassPrimary,
                  child: const Icon(
                    Iconsax.image,
                    color: AppColors.textTertiary,
                    size: 24,
                  ),
                ),
              ),
              // Time Overlay
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        AppColors.gradientStart.withValues(alpha: 0.6),
                      ],
                    ),
                  ),
                  child: Text(
                    photo['time'],
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sticky Search Bar Delegate
class _SearchBarDelegate extends SliverPersistentHeaderDelegate {
  final TextEditingController controller;

  _SearchBarDelegate({required this.controller});

  @override
  double get minExtent => 72;

  @override
  double get maxExtent => 72;

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) =>
      false;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          decoration: BoxDecoration(
            color: AppColors.glassHeader,
            border: Border(
              bottom: BorderSide(color: AppColors.glassBorder),
            ),
          ),
          child: GlassInputField(
            controller: controller,
            hint: 'Search photos, tags...',
            prefixIcon: Iconsax.search_normal,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
        ),
      ),
    );
  }
}

