import 'dart:io';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:izumi/core/ui/app_icons.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';
import '../../providers/auth_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/permission_service.dart';
import '../../services/storage_service.dart';
import '../../widgets/glass/gradient_background.dart';
import '../../widgets/inputs/text_input_field.dart';
import '../../widgets/navigation/app_header.dart';

/// Edit Profile Screen - Unified Glass Design
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _storageService = StorageService();
  bool _isSaving = false;
  bool _isUploadingAvatar = false;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().currentUser;
    if (user != null) {
      _nameController.text = user.name;
      _phoneController.text = user.phone;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadAvatar() async {
    if (_isUploadingAvatar) return;

    final auth = context.read<AuthProvider>();
    final user = auth.currentUser;
    if (user == null) return;

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.glassStrong,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(AppIcons.camera, color: AppColors.textPrimary),
                title: Text('Camera', style: AppTypography.bodyMedium.copyWith(color: AppColors.textPrimary)),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(AppIcons.gallery, color: AppColors.textPrimary),
                title: Text('Gallery', style: AppTypography.bodyMedium.copyWith(color: AppColors.textPrimary)),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;

    if (source == null) return;

    // Guard camera permission when user selects camera source
    if (source == ImageSource.camera) {
      final granted = await PermissionService().ensurePermission(
        context: context,
        permission: Permission.camera,
        title: 'Camera Access',
        message: 'Izumi needs camera access to take a profile photo.',
      );
      if (!mounted) return;
      if (!granted) return;
    } else {
      final granted = await PermissionService().ensurePhotoLibraryPermission(
        context: context,
        title: 'Photo Library Access',
        message: 'Izumi needs photo library access to choose a profile photo.',
      );
      if (!mounted) return;
      if (!granted) return;
    }

    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, maxWidth: 600, maxHeight: 600, imageQuality: 80);
    if (!mounted) return;
    if (picked == null) return;

    setState(() => _isUploadingAvatar = true);

    try {
      // Evict old cached image before uploading new one
      final oldUrl = user.profileImageUrl;
      if (oldUrl != null && oldUrl.isNotEmpty) {
        imageCache.evict(oldUrl);
      }

      final imageUrl = await _storageService.uploadProfileImage(
        enterpriseId: user.enterpriseId,
        userId: user.id,
        file: File(picked.path),
      );

      // Evict new URL too in case it was previously cached
      imageCache.evict(imageUrl);

      await FirebaseFirestore.instance.collection('users').doc(user.id).update({
        'profileImageUrl': imageUrl,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });

      await auth.refreshUser();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Profile photo updated'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to upload photo'),
            backgroundColor: AppColors.critical,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingAvatar = false);
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _isSaving = true);

    try {
      final auth = context.read<AuthProvider>();
      final userId = auth.currentUser?.id;
      if (userId != null) {
        await FirebaseFirestore.instance.collection('users').doc(userId).update({
          'name': name,
          'updatedAt': Timestamp.fromDate(DateTime.now()),
        });
        await auth.refreshUser();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Profile updated'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to update profile'),
          backgroundColor: AppColors.critical,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              const AppHeader(
                title: 'Edit Profile',
                type: AppHeaderType.secondary,
                showAvatar: false,
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 120),
                  child: Column(
                    children: [
                      _buildAvatar(),
                      const SizedBox(height: 28),
                      _buildField(
                        label: 'Full Name',
                        controller: _nameController,
                        prefixIcon: AppIcons.user,
                      ),
                      const SizedBox(height: 16),
                      _buildField(
                        label: 'Phone Number',
                        controller: _phoneController,
                        prefixIcon: AppIcons.call,
                        enabled: false,
                      ),
                      const SizedBox(height: 32),
                      _buildSaveButton(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    final user = context.watch<AuthProvider>().currentUser;
    final profileUrl = user?.profileImageUrl;
    final hasImage = profileUrl != null && profileUrl.isNotEmpty;

    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.primary.withValues(alpha: 0.4),
                AppColors.primary.withValues(alpha: 0.15),
              ],
            ),
            border: Border.all(color: AppColors.glassBorder, width: 2),
          ),
          child: ClipOval(
            child: hasImage
                ? Image.network(
                    profileUrl,
                    fit: BoxFit.cover,
                    width: 120,
                    height: 120,
                    errorBuilder: (_, __, ___) => _buildInitialsAvatar(user?.initials),
                  )
                : _buildInitialsAvatar(user?.initials),
          ),
        ),
        if (_isUploadingAvatar)
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: 0.5),
            ),
            child: const Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
        Positioned(
          right: 0,
          bottom: 0,
          child: GestureDetector(
            onTap: _pickAndUploadAvatar,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.glassBorder, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(
                AppIcons.camera,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInitialsAvatar(String? initials) {
    return Container(
      color: AppColors.glassPrimary,
      child: Center(
        child: Text(
          initials ?? '?',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    required IconData prefixIcon,
    bool enabled = true,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.glassPrimary,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 10),
              GlassInputField(
                controller: controller,
                enabled: enabled,
                prefixIcon: prefixIcon,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSaveButton() {
    return GestureDetector(
      onTap: _isSaving ? null : _save,
      child: Container(
        width: double.infinity,
        height: 56,
        decoration: BoxDecoration(
          color: _isSaving ? AppColors.primary.withValues(alpha: 0.6) : AppColors.primary,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Center(
          child: _isSaving
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  'Save Changes',
                  style: AppTypography.buttonLarge.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      ),
    );
  }
}
