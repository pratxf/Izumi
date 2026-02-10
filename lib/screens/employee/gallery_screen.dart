import 'dart:ui';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_shadows.dart';
import '../../core/constants/app_typography.dart';
import '../../models/photo_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/photo_provider.dart';
import '../../widgets/glass/gradient_background.dart';
import '../../widgets/navigation/app_header.dart';
import '../../widgets/inputs/text_input_field.dart';
import 'image_detail_screen.dart';

/// Employee Gallery Screen - Photo gallery with glassmorphism design
class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  final _searchController = TextEditingController();
  bool _initialized = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initProvider();
    });
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
      });
    });
  }

  void _initProvider() {
    if (_initialized) return;
    _initialized = true;
    final auth = context.read<AuthProvider>();
    // Use Firebase Auth UID directly as fallback — always available when authenticated
    final userId = auth.currentUser?.id
        ?? FirebaseAuth.instance.currentUser?.uid
        ?? '';
    debugPrint('[GalleryScreen] _initProvider: userId=$userId');
    if (userId.isEmpty) {
      debugPrint('[GalleryScreen] ERROR: userId is empty, cannot load photos');
      return;
    }
    context.read<PhotoProvider>().streamPhotos(userId);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photoProvider = context.watch<PhotoProvider>();
    final auth = context.read<AuthProvider>();

    // If searching, filter photos; otherwise use grouped-by-date
    final Map<String, List<PhotoModel>> photoGroups;
    if (_searchQuery.isNotEmpty) {
      final filtered = photoProvider.searchPhotos(_searchQuery);
      // Group filtered results into a single group
      photoGroups = filtered.isNotEmpty ? {'Results': filtered} : {};
    } else {
      photoGroups = photoProvider.photosByDate;
    }

    final groupKeys = photoGroups.keys.toList();

    return GradientBackground(
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const AppHeader(
              title: 'Gallery',
              type: AppHeaderType.secondary,
              showAvatar: false,
              showLeading: false,
            ),

            // Search Bar
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              color: AppColors.glassHeader,
              child: GlassInputField(
                controller: _searchController,
                hint: 'Search photos, tags...',
                prefixIcon: Iconsax.search_normal,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),

            // Content
            Expanded(
              child: Stack(
                children: [
                  if (photoProvider.isLoading && photoProvider.photos.isEmpty)
                    const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    )
                  else if (groupKeys.isEmpty)
                    Center(
                      child: Text(
                        _searchQuery.isNotEmpty
                            ? 'No photos found'
                            : 'No photos yet',
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    )
                  else
                    ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                      itemCount: groupKeys.length,
                      itemBuilder: (context, index) {
                        final key = groupKeys[index];
                        final photos = photoGroups[key]!;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: _buildPhotoGroup(key, photos, auth),
                        );
                      },
                    ),

                  // Camera FAB
                  Positioned(
                    right: 24,
                    bottom: 120,
                    child: GestureDetector(
                      onTap: () => context.push('/employee/camera'),
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

  Widget _buildPhotoGroup(
    String title,
    List<PhotoModel> photos,
    AuthProvider auth,
  ) {
    const spacing = 12.0;

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
                    title,
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
                      '${photos.length} PHOTOS',
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

              // Photo Grid (auto-sized)
              LayoutBuilder(
                builder: (context, constraints) {
                  final tileSize =
                      (constraints.maxWidth - (spacing * 2)) / 3;
                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: [
                      for (final photo in photos)
                        SizedBox(
                          width: tileSize,
                          height: tileSize,
                          child: _buildPhotoTile(photo, auth),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoTile(PhotoModel photo, AuthProvider auth) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ImageDetailScreen(
              imageUrl: photo.imageUrl,
              location: photo.location,
              capturedBy: auth.currentUser?.name ?? 'You',
              employeeId: photo.employeeId,
              timestamp: photo.timestamp,
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
                photo.thumbnailUrl.isNotEmpty
                    ? photo.thumbnailUrl
                    : photo.imageUrl,
                fit: BoxFit.cover,
                cacheWidth: 300,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Container(
                    color: AppColors.glassPrimary,
                    child: const Center(
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
                },
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
                    photo.formattedTime,
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

