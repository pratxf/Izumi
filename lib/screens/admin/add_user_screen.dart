import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
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
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _userRepo = UserRepository();

  String? _role;
  String _countryCode = '+91';
  bool _sendInvite = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _addUser() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();

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

        // Different role — offer to add it
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
                'Would you like to add the ${_role!} role to their account?',
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
                    'Add Role',
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
            // Add the new role to existing user
            final docRef = existingQuery.docs.first.reference;
            final updatedRoles = [...existingRoles, _role!];
            await docRef.update({
              'roles': updatedRoles,
              'updatedAt': Timestamp.fromDate(DateTime.now()),
            });
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${_role!} role added to ${existingData['name']}')),
              );
              context.pop();
            }
          }
          setState(() => _isLoading = false);
          return;
        }
      }

      final user = UserModel(
        id: FirebaseFirestore.instance.collection('users').doc().id,
        name: name,
        phone: fullPhone,
        email: _emailController.text.trim().isNotEmpty ? _emailController.text.trim() : null,
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
                          const SizedBox(height: AppSpacing.md),
                          GlassInputField(
                            label: 'Email Address',
                            hint: 'name@company.com',
                            keyboardType: TextInputType.emailAddress,
                            controller: _emailController,
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
                    const SizedBox(height: AppSpacing.xl),
                    GlassPanel(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.15),
                              borderRadius:
                                  BorderRadius.circular(AppSpacing.radiusMd),
                              border:
                                  Border.all(color: AppColors.glassBorder),
                            ),
                            child: const Icon(
                              Iconsax.sms,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Send invitation email',
                                  style: AppTypography.bodyMedium.copyWith(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'User will receive login instructions',
                                  style: AppTypography.caption.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _sendInvite,
                            activeThumbColor: AppColors.primary,
                            inactiveThumbColor: AppColors.textSecondary,
                            inactiveTrackColor:
                                AppColors.glassPrimary.withValues(alpha: 0.7),
                            onChanged: (value) {
                              setState(() => _sendInvite = value);
                            },
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
                      icon: Iconsax.arrow_right_2,
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
            Iconsax.arrow_down_1,
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
            DropdownMenuItem(value: 'admin', child: Text('Admin')),
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
              Iconsax.arrow_down_1,
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
