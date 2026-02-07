import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_typography.dart';
import '../../widgets/buttons/primary_button.dart';
import '../../widgets/inputs/text_input_field.dart';
import '../../widgets/glass/gradient_background.dart';
import '../../widgets/glass/glass_chip.dart';
import '../../widgets/navigation/app_header.dart';

/// Preview Screen
/// Photo preview with metadata entry form
class PreviewScreen extends StatefulWidget {
  final String location;
  final DateTime timestamp;

  const PreviewScreen({
    super.key,
    required this.location,
    required this.timestamp,
  });

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  String _category = 'distributor';
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _createFollowUp = false;
  DateTime? _dueDate;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _selectDueDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date != null) {
      setState(() => _dueDate = date);
    }
  }

  void _savePhoto() {
    // TODO: Save photo with metadata
    Navigator.pop(context);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Photo saved successfully!')));
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day} ${months[date.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              const AppHeader(
                title: 'Preview',
                type: AppHeaderType.secondary,
                showAvatar: false,
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                    // Photo Preview
                    Container(
                      width: double.infinity,
                      height: 200,
                      decoration: BoxDecoration(
                        color: AppColors.secondary,
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusLg,
                        ),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Stack(
                        children: [
                          // Placeholder
                          Center(
                            child: Icon(
                              Iconsax.image,
                              color: AppColors.textTertiary,
                              size: 48,
                            ),
                          ),
                          // Location overlay
                          Positioned(
                            left: AppSpacing.md,
                            bottom: AppSpacing.md,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm,
                                vertical: AppSpacing.xs,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.gradientStart.withValues(
                                  alpha: 0.6,
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Iconsax.location,
                                    color: AppColors.textPrimary,
                                    size: 12,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    widget.location,
                                    style: AppTypography.small.copyWith(
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    // Category Selection
                    Text('Category:', style: AppTypography.label),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        _buildCategoryChip('Distributor', 'distributor'),
                        const SizedBox(width: AppSpacing.md),
                        _buildCategoryChip('Farmer', 'farmer'),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    // Name Input
                    TextInputField(
                      label: 'Name',
                      hint: 'Enter name',
                      controller: _nameController,
                      prefixIcon: Iconsax.user,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    // Phone Input
                    TextInputField(
                      label: 'Phone (Optional)',
                      hint: 'Enter phone number',
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      prefixIcon: Iconsax.call,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    // Create Follow-up Checkbox
                    GestureDetector(
                      onTap: () =>
                          setState(() => _createFollowUp = !_createFollowUp),
                      child: Row(
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: _createFollowUp
                                  ? AppColors.primary
                                  : AppColors.glassPrimary,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: _createFollowUp
                                    ? AppColors.primary
                                    : AppColors.border,
                                width: 2,
                              ),
                            ),
                            child: _createFollowUp
                                ? const Icon(
                                    Icons.check,
                                    size: 16,
                                    color: AppColors.textPrimary,
                                  )
                                : null,
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Text(
                            'Create Follow-up',
                            style: AppTypography.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    // Due Date (if follow-up enabled)
                    if (_createFollowUp) ...[
                      const SizedBox(height: AppSpacing.lg),
                      GestureDetector(
                        onTap: _selectDueDate,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          decoration: BoxDecoration(
                            color: AppColors.glassPrimary,
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusMd,
                            ),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Iconsax.calendar,
                                color: AppColors.textTertiary,
                                size: 20,
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Text(
                                'Due Date',
                                style: AppTypography.body.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                _dueDate != null
                                    ? _formatDate(_dueDate!)
                                    : 'Select date',
                                style: AppTypography.bodyMedium.copyWith(
                                  color: _dueDate != null
                                      ? AppColors.textPrimary
                                      : AppColors.textTertiary,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Icon(
                                Icons.chevron_right,
                                color: AppColors.textTertiary,
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xxxl),
                    // Save Button
                    PrimaryButton.rectangular(
                      label: 'Save Photo',
                      icon: Iconsax.tick_circle,
                      onPressed: _savePhoto,
                    ),
                    const SizedBox(height: AppSpacing.xxxl),
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

  Widget _buildCategoryChip(String label, String value) {
    final isSelected = _category == value;
    return GlassChip(
      label: label,
      selected: isSelected,
      onTap: () => setState(() => _category = value),
    );
  }
}

