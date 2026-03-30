import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:izumi/core/ui/app_icons.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';
import '../../models/photo_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/photo_provider.dart';
import '../../widgets/glass/gradient_background.dart';
import '../../widgets/inputs/text_input_field.dart';
import '../../widgets/navigation/app_header.dart';

/// Admin Images Screen - Cloud images gallery with employee filter
class ImagesScreen extends StatefulWidget {
  final String? initialEmployeeId;

  const ImagesScreen({super.key, this.initialEmployeeId});

  @override
  State<ImagesScreen> createState() => _ImagesScreenState();
}

class _ImagesScreenState extends State<ImagesScreen> {
  final _searchController = TextEditingController();
  late String _selectedEmployeeId;
  String? _lastLoadedEnterpriseId;

  @override
  void initState() {
    super.initState();
    _selectedEmployeeId = widget.initialEmployeeId ?? 'all';
    _loadPhotos();
  }

  void _loadPhotos() {
    final enterpriseId = context.read<AuthProvider>().enterpriseId;
    if (enterpriseId != null) {
      _lastLoadedEnterpriseId = enterpriseId;
      context.read<PhotoProvider>().streamPhotosForEnterprise(enterpriseId);
      // Ensure employees are loaded for the dropdown filter
      final dashboardProvider = context.read<DashboardProvider>();
      if (dashboardProvider.employees.isEmpty) {
        dashboardProvider.initDashboard(enterpriseId);
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _searchQuery = '';

  Map<String, List<PhotoModel>> _filterPhotos(Map<String, List<PhotoModel>> photosByDate) {
    final filtered = <String, List<PhotoModel>>{};
    for (final entry in photosByDate.entries) {
      var photos = entry.value;
      if (_selectedEmployeeId != 'all') {
        photos = photos.where((p) => p.employeeId == _selectedEmployeeId).toList();
      }
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        photos = photos.where((p) =>
            p.location.toLowerCase().contains(query) ||
            _getEmployeeName(p.employeeId).toLowerCase().contains(query) ||
            (p.customerName?.toLowerCase().contains(query) ?? false) ||
            (p.category?.toLowerCase().contains(query) ?? false)
        ).toList();
      }
      if (photos.isNotEmpty) {
        filtered[entry.key] = photos;
      }
    }
    return filtered;
  }

  String _getEmployeeName(String employeeId) {
    final dashboardProvider = context.read<DashboardProvider>();
    final emp = dashboardProvider.employees.where((e) => e.id == employeeId).firstOrNull;
    return emp?.name ?? 'Employee';
  }

  String _getEmployeeInitials(String employeeId) {
    final dashboardProvider = context.read<DashboardProvider>();
    final emp = dashboardProvider.employees.where((e) => e.id == employeeId).firstOrNull;
    return emp?.initials ?? '?';
  }

  @override
  Widget build(BuildContext context) {
    // Reactive re-load when enterpriseId becomes available after init
    final enterpriseId = context.watch<AuthProvider>().enterpriseId;
    if (enterpriseId != null && enterpriseId != _lastLoadedEnterpriseId) {
      _lastLoadedEnterpriseId = enterpriseId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<PhotoProvider>().streamPhotosForEnterprise(enterpriseId);
      });
    }

    final photoProvider = context.watch<PhotoProvider>();
    final dashboardProvider = context.watch<DashboardProvider>();
    final filteredGroups = _filterPhotos(photoProvider.photosByDate);

    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
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
                hint: 'Search photos, employees...',
                prefixIcon: AppIcons.search_normal,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                onChanged: (value) => setState(() => _searchQuery = value.trim()),
              ),
            ),

            // Employee Filter
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: _buildEmployeeFilter(dashboardProvider),
            ),

            // Content
            Expanded(
              child: photoProvider.isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.primary),
                    )
                  : filteredGroups.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                AppIcons.image,
                                size: 48,
                                color: AppColors.textTertiary,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No photos yet',
                                style: AppTypography.bodyMedium.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                          itemCount: filteredGroups.length,
                          itemBuilder: (context, index) {
                            final dateKey = filteredGroups.keys.elementAt(index);
                            final photos = filteredGroups[dateKey]!;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: _buildPhotoGroup(dateKey, photos),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildEmployeeFilter(DashboardProvider dashboardProvider) {
    final employees = dashboardProvider.employees;

    // Reset to 'all' if selected employee ID is not in the list yet
    final hasSelectedEmployee = _selectedEmployeeId == 'all' ||
        employees.any((e) => e.id == _selectedEmployeeId);
    final effectiveValue = hasSelectedEmployee ? _selectedEmployeeId : 'all';

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.glassPrimary,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: effectiveValue,
              isExpanded: true,
              icon: Icon(
                AppIcons.arrow_down_1,
                color: AppColors.textSecondary,
                size: 20,
              ),
              dropdownColor: AppColors.glassStrong,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textPrimary,
              ),
              items: [
                DropdownMenuItem(
                  value: 'all',
                  child: Row(
                    children: [
                      Icon(AppIcons.people, size: 18, color: AppColors.textSecondary),
                      const SizedBox(width: 12),
                      const Text('All Employees'),
                    ],
                  ),
                ),
                ...employees.map((e) => DropdownMenuItem(
                      value: e.id,
                      child: Row(
                        children: [
                          Icon(AppIcons.user, size: 18, color: AppColors.textSecondary),
                          const SizedBox(width: 12),
                          Text(e.name),
                        ],
                      ),
                    )),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _selectedEmployeeId = v);
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoGroup(String dateKey, List<PhotoModel> photos) {
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
          ),
          child: Column(
            children: [
              // Group Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    dateKey,
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
                      color: AppColors.glassPrimary,
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

              // Photo Grid
              LayoutBuilder(
                builder: (context, constraints) {
                  final tileSize = (constraints.maxWidth - (spacing * 2)) / 3;
                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: [
                      for (final photo in photos)
                        SizedBox(
                          width: tileSize,
                          height: tileSize,
                          child: _buildPhotoTile(photo),
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

  Widget _buildPhotoTile(PhotoModel photo) {
    final initials = _getEmployeeInitials(photo.employeeId);
    final imageUrl = photo.thumbnailUrl.isNotEmpty ? photo.thumbnailUrl : photo.imageUrl;
    final heroTag = 'admin_photo_${photo.id}';

    return GestureDetector(
      onTap: () {
        if (photo.imageUrl.isNotEmpty) {
          precacheImage(NetworkImage(photo.imageUrl), context);
        }
        context.push('/employee/image-detail', extra: {
          'imageUrl': photo.imageUrl,
          'thumbnailUrl': imageUrl,
          'location': photo.location,
          'capturedBy': _getEmployeeName(photo.employeeId),
          'employeeId': photo.employeeId,
          'timestamp': photo.timestamp,
          'latitude': photo.latitude,
          'longitude': photo.longitude,
          'category': photo.category,
          'name': photo.customerName,
          'phone': photo.customerPhone,
          'hasFollowUp': photo.hasFollowUp,
          'heroTag': heroTag,
        });
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: AppColors.glassPrimary,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Hero(
                tag: heroTag,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: AppColors.glassPrimary,
                    child: const Icon(
                      AppIcons.image,
                      color: AppColors.textTertiary,
                      size: 24,
                    ),
                  ),
                ),
              ),
              // Employee Badge (top-left)
              Positioned(
                top: 6,
                left: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.gradientStart.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    initials,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
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

