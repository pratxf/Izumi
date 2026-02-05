import 'dart:ui'; // For ImageFilter
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_shadows.dart'; // Added for glass shadow
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_typography.dart';

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
  late FocusNode _focusNode;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(() {
      setState(() => _isFocused = _focusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasError = widget.errorText != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null) ...[
          Text(widget.label!, style: AppTypography.label),
          const SizedBox(height: AppSpacing.sm),
        ],
        ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              height: AppSpacing.inputHeight,
              decoration: BoxDecoration(
                color: AppColors.glassSlateSoft,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(
                  color: hasError
                      ? AppColors.error
                      : _isFocused
                      ? AppColors.primary.withValues(alpha: 0.5)
                      : AppColors.glassSlateBorder,
                  width: 1,
                ),
                boxShadow: _isFocused
                    ? [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.25),
                          blurRadius: 12,
                          spreadRadius: 0,
                        ),
                      ]
                    : AppShadows.glass,
              ),
              child: Row(
                children: [
                  // Country Code
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        right: BorderSide(color: AppColors.glassSlateBorder),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        widget.countryCode,
                        style: AppTypography.input,
                      ),
                    ),
                  ),
                  // Phone Number Input
                  Expanded(
                    child: TextField(
                      controller: widget.controller,
                      focusNode: _focusNode,
                      keyboardType: TextInputType.phone,
                      onChanged: widget.onChanged,
                      enabled: widget.enabled,
                      style: AppTypography.input,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(10),
                      ],
                      decoration: InputDecoration(
                        hintText: '98XXX XXXXX',
                        hintStyle: AppTypography.inputHint.copyWith(
                          color: AppColors.textMuted.withValues(alpha: 0.5),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            widget.errorText!,
            style: AppTypography.caption.copyWith(color: AppColors.errorDark),
          ),
        ],
      ],
    );
  }
}
