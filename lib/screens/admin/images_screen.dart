import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';
import '../../widgets/glass/gradient_background.dart';

/// Admin Images Screen - Cloud images gallery with employee filter
class ImagesScreen extends StatefulWidget {
  const ImagesScreen({super.key});

  @override
  State<ImagesScreen> createState() => _ImagesScreenState();
}

class _ImagesScreenState extends State<ImagesScreen> {
  final _searchController = TextEditingController();
  String _selectedEmployee = 'All Employees';

  final List<String> _employees = [
    'All Employees',
    'Rahul Kumar',
    'Priya Singh',
    'Amit Sharma',
    'Neha Verma',
  ];

  // Mock photo data grouped by date
  final List<Map<String, dynamic>> _photoGroups = [
    {
      'title': 'Today',
      'count': 15,
      'photos': [
        {
          'time': '14:32',
          'employee': 'RK',
          'url': 'https://picsum.photos/seed/a1/200',
        },
        {
          'time': '14:15',
          'employee': 'PS',
          'url': 'https://picsum.photos/seed/a2/200',
        },
        {
          'time': '13:48',
          'employee': 'AS',
          'url': 'https://picsum.photos/seed/a3/200',
        },
        {
          'time': '11:20',
          'employee': 'NV',
          'url': 'https://picsum.photos/seed/a4/200',
        },
        {
          'time': '10:05',
          'employee': 'RK',
          'url': 'https://picsum.photos/seed/a5/200',
        },
        {
          'time': '09:55',
          'employee': 'PS',
          'url': 'https://picsum.photos/seed/a6/200',
        },
      ],
    },
    {
      'title': 'Yesterday',
      'count': 8,
      'photos': [
        {
          'time': '16:45',
          'employee': 'AS',
          'url': 'https://picsum.photos/seed/b1/200',
        },
        {
          'time': '15:30',
          'employee': 'NV',
          'url': 'https://picsum.photos/seed/b2/200',
        },
        {
          'time': '14:10',
          'employee': 'RK',
          'url': 'https://picsum.photos/seed/b3/200',
        },
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
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildGlassButton(
                    icon: Icons.arrow_back,
                    onTap: () => Navigator.maybePop(context),
                  ),
                  Text(
                    'Gallery',
                    style: AppTypography.h2.copyWith(
                      color: const Color(0xFF1F2937),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  _buildGlassButton(icon: Icons.more_vert),
                ],
              ),
            ),

            // Content
            Expanded(
              child: CustomScrollView(
                slivers: [
                  // Search Bar (sticky)
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _SearchBarDelegate(controller: _searchController),
                  ),

                  // Employee Filter
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: _buildEmployeeFilter(),
                    ),
                  ),

                  // Photo Groups
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
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
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlassButton({required IconData icon, VoidCallback? onTap}) {
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
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.glassSlateSoft,
                  Colors.white.withValues(alpha: 0.25),
                ],
              ),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.glassSlateBorder),
            ),
            child: Icon(icon, color: const Color(0xFF1F2937), size: 22),
          ),
        ),
      ),
    );
  }

  Widget _buildEmployeeFilter() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.glassSlateSoft,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedEmployee,
              isExpanded: true,
              icon: Icon(
                Iconsax.arrow_down_1,
                color: const Color(0xFF6B7280),
                size: 20,
              ),
              dropdownColor: Colors.white,
              style: AppTypography.bodyMedium.copyWith(
                color: const Color(0xFF1F2937),
              ),
              items: _employees.map((e) {
                return DropdownMenuItem(
                  value: e,
                  child: Row(
                    children: [
                      Icon(
                        e == 'All Employees' ? Iconsax.people : Iconsax.user,
                        size: 18,
                        color: const Color(0xFF6B7280),
                      ),
                      const SizedBox(width: 12),
                      Text(e),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (v) {
                if (v != null) setState(() => _selectedEmployee = v);
              },
            ),
          ),
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
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: 0.45),
                Colors.white.withValues(alpha: 0.2),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
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
                      color: const Color(0xFF1F2937),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      '${group['count']} PHOTOS',
                      style: TextStyle(
                        color: const Color(0xFF6B7280),
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
                  return _buildPhotoTile(photo);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoTile(Map<String, dynamic> photo) {
    return GestureDetector(
      onTap: () {
        // View full photo
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: Colors.grey.shade200,
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
              Image.network(
                photo['url'],
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: Colors.grey.shade300,
                  child: Icon(
                    Iconsax.image,
                    color: Colors.grey.shade500,
                    size: 24,
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
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    photo['employee'],
                    style: const TextStyle(
                      color: Colors.white,
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
                        Colors.black.withValues(alpha: 0.6),
                      ],
                    ),
                  ),
                  child: Text(
                    photo['time'],
                    style: const TextStyle(
                      color: Colors.white,
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
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
            ),
            child: TextField(
              controller: controller,
              style: AppTypography.bodyMedium.copyWith(
                color: const Color(0xFF1F2937),
              ),
              decoration: InputDecoration(
                hintText: 'Search photos, employees...',
                hintStyle: AppTypography.bodyMedium.copyWith(
                  color: const Color(0xFF6B7280),
                ),
                prefixIcon: Icon(
                  Iconsax.search_normal,
                  color: const Color(0xFF6B7280),
                  size: 20,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
