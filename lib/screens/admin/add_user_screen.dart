import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_typography.dart';
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

  String? _role;
  String _countryCode = '+91';

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
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
              child: PrimaryButton.rectangular(
                label: 'Add User',
                icon: Icons.arrow_forward,
                onPressed: () {},
              ),
            ),
          ],
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
          dropdownColor: AppColors.glassNav,
          icon: const Icon(
            Icons.expand_more,
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
          dropdownColor: AppColors.glassNav,
            icon: const Icon(
              Icons.expand_more,
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
