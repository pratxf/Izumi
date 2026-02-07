import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_typography.dart';
import 'text_input_field.dart';

/// Phone Input Field Widget
/// Country code prefix + phone number input
class PhoneInputField extends StatefulWidget {
  final String? label;
  final String? errorText;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final String countryCode;
  final bool enabled;

  const PhoneInputField({
    super.key,
    this.label,
    this.errorText,
    this.controller,
    this.onChanged,
    this.countryCode = '+91',
    this.enabled = true,
  });

  @override
  State<PhoneInputField> createState() => _PhoneInputFieldState();
}

class _PhoneInputFieldState extends State<PhoneInputField> {
  @override
  Widget build(BuildContext context) {
    return GlassInputField(
      label: widget.label,
      hint: '98XXX XXXXX',
      errorText: widget.errorText,
      controller: widget.controller,
      keyboardType: TextInputType.phone,
      onChanged: widget.onChanged,
      enabled: widget.enabled,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      prefix: Padding(
        padding: const EdgeInsets.only(right: AppSpacing.md),
        child: IntrinsicHeight(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.countryCode, style: AppTypography.input),
              const SizedBox(width: AppSpacing.md),
              const VerticalDivider(width: 1, thickness: 1),
            ],
          ),
        ),
      ),
      suffixIcon: null,
    );
  }
}

