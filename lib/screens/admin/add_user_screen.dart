import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:izumi/core/ui/app_icons.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_typography.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/user_repository.dart';
import '../../widgets/buttons/primary_button.dart';
import '../../widgets/glass/gradient_background.dart';
import '../../widgets/glass/glass_panel.dart';
import '../../widgets/inputs/text_input_field.dart';
import '../../widgets/navigation/app_header.dart';

class AddUserScreen extends StatefulWidget {
  const AddUserScreen({super.key});

  @override
  State<AddUserScreen> createState() => _AddUserScreenState();
}

class _AddUserScreenState extends State<AddUserScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _userRepo = UserRepository();

  String? _role;
  String _countryCode = '+91';
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _addUser() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.replaceAll(RegExp(r'[\s\-\(\)]'), '').trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a name')),
      );
      return;
    }
    if (_role == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a role')),
      );
      return;
    }
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a phone number')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authProvider = context.read<AuthProvider>();

      // Force-refresh token so Firestore gets current custom claims
      final hasClaims = await authProvider.refreshTokenAndClaims();
      if (!mounted) return;
      if (!hasClaims) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Session expired. Please log out and log in again.')),
        );
        setState(() => _isLoading = false);
        return;
      }

      final enterpriseId = authProvider.enterpriseId ?? authProvider.currentUser?.enterpriseId ?? '';
      final now = DateTime.now();
      final fullPhone = '$_countryCode$phone';

      // Phone uniqueness check within this enterprise
      final existingQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('phone', isEqualTo: fullPhone)
          .where('enterpriseId', isEqualTo: enterpriseId)
          .limit(1)
          .get();

      if (existingQuery.docs.isNotEmpty) {
        final existingData = existingQuery.docs.first.data();
        final existingRoles = existingData['roles'] != null
            ? List<String>.from(existingData['roles'])
            : [existingData['role'] ?? 'employee'];

        if (existingRoles.contains(_role)) {
          // Same role already exists
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('A user with this phone number and role already exists')),
            );
          }
          setState(() => _isLoading = false);
          return;
        }

        // Different role — offer to replace it
        if (mounted) {
          final shouldAdd = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: AppColors.glassStrong,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: Text(
                'User Exists',
                style: AppTypography.h3.copyWith(color: AppColors.textPrimary),
              ),
              content: Text(
                'A user with this phone number already exists as ${existingRoles.join(", ")}. '
                'Do you want to change their role to ${_role!}? This will replace existing role access.',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(
                    'Cancel',
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(
                    'Change Role',
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          );

          if (shouldAdd == true) {
            // Replace role for existing user and sync custom claims via backend callable
            final callable = FirebaseFunctions.instanceFor(region: 'asia-south1')
                .httpsCallable('updateUserRole');
            await callable.call({
              'targetUserId': existingQuery.docs.first.id,
              'newRole': _role!,
            });
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Role changed to ${_role!} for ${existingData['name']}')),
              );
              context.pop();
            }
          }
          setState(() => _isLoading = false);
          return;
        }
      }

      // Probe Firebase Auth for a stranded record on this phone before
      // we create a placeholder doc. This catches Auth zombies left over
      // from prior deletes so the admin sees them explicitly rather than
      // hitting phone-number-already-exists on first login.
      final collisionCallable =
          FirebaseFunctions.instanceFor(region: 'asia-south1')
              .httpsCallable('checkPhoneCollision');
      final collisionResp =
          await collisionCallable.call({'phone': fullPhone});
      final collision =
          Map<String, dynamic>.from(collisionResp.data as Map);
      final verdict = collision['verdict'] as String? ?? 'none';
      final collisionMessage = collision['message'] as String? ?? '';

      if (verdict == 'otherEnterpriseAuth') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(collisionMessage)),
          );
        }
        setState(() => _isLoading = false);
        return;
      }

      if (verdict == 'orphanAuthSameEnterprise' ||
          verdict == 'unknownAuth') {
        if (!mounted) return;
        final shouldClean = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.glassStrong,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            title: Text(
              'Old account found',
              style: AppTypography.h3.copyWith(color: AppColors.textPrimary),
            ),
            content: Text(
              '$collisionMessage\n\n'
              'The old Firebase Auth record (UID: ${collision['authUid']}) '
              'will be deleted before this user is created.',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(
                  'Cancel',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(
                  'Clean up & create',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        );

        if (shouldClean != true) {
          if (mounted) setState(() => _isLoading = false);
          return;
        }

        final cleanup = FirebaseFunctions.instanceFor(region: 'asia-south1')
            .httpsCallable('adminCleanup');
        await cleanup.call({'phone': fullPhone, 'deleteOnly': true});
      }

      final user = UserModel(
        id: FirebaseFirestore.instance.collection('users').doc().id,
        name: name,
        phone: fullPhone,
        email: null,
        roles: [_role!],
        activeRole: _role!,
        enterpriseId: enterpriseId,
        createdAt: now,
        updatedAt: now,
      );

      await _userRepo.createUser(user);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$name added successfully')),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add user: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
              title: 'Add New User',
              type: AppHeaderType.secondary,
              showAvatar: false,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GlassPanel(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionTitle('Basic Info'),
                          const SizedBox(height: AppSpacing.md),
                          GlassInputField(
                            label: 'Full Name',
                            hint: 'e.g. Sarah Johnson',
                            controller: _nameController,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    GlassPanel(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionTitle('Role'),
                          const SizedBox(height: AppSpacing.md),
                          _buildRoleDropdown(),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    GlassPanel(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionTitle('Phone Number'),
                          const SizedBox(height: AppSpacing.md),
                          Row(
                            children: [
                              _buildCountryDropdown(),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: GlassInputField(
                                  hint: '00000 00000',
                                  keyboardType: TextInputType.phone,
                                  controller: _phoneController,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.primary),
                    )
                  : PrimaryButton.rectangular(
                      label: 'Add User',
                      icon: AppIcons.arrow_right_2,
                      onPressed: _addUser,
                    ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: AppTypography.caption.copyWith(
        color: AppColors.textSecondary,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.1,
      ),
    );
  }

  Widget _buildRoleDropdown() {
    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _role,
          isExpanded: true,
          dropdownColor: AppColors.glassStrong,
          icon: const Icon(
            AppIcons.arrow_down_1,
            color: AppColors.textSecondary,
          ),
          hint: Text(
            'Select Role',
            style: AppTypography.inputHint.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          items: const [
            DropdownMenuItem(value: 'employee', child: Text('Employee')),
            DropdownMenuItem(value: 'team_lead', child: Text('Team Lead')),
          ],
          onChanged: (value) => setState(() => _role = value),
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildCountryDropdown() {
    return SizedBox(
      width: 88,
      child: GlassPanel(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _countryCode,
            isExpanded: true,
            dropdownColor: AppColors.glassStrong,
            icon: const Icon(
              AppIcons.arrow_down_1,
              color: AppColors.textSecondary,
              size: 18,
            ),
            items: const [
              DropdownMenuItem(value: '+91', child: Text('+91')),
              DropdownMenuItem(value: '+1', child: Text('+1')),
              DropdownMenuItem(value: '+44', child: Text('+44')),
            ],
            onChanged: (value) =>
                setState(() => _countryCode = value ?? '+91'),
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
