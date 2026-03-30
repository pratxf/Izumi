import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_typography.dart';

/// Universal Glass Input Field
/// Single frosted glass surface with unified states
class GlassInputField extends StatefulWidget {
  final String? label;
  final String? hint;
  final String? errorText;
  final TextEditingController? controller;
  final TextInputType keyboardType;
  final bool obscureText;
  final IconData? prefixIcon;
  final Widget? prefixWidget;
  final Widget? suffixIcon;
  final ValueChanged<String>? onChanged;
  final int maxLines;
  final bool enabled;
  final FocusNode? focusNode;
  final Widget? prefix;
  final EdgeInsetsGeometry? contentPadding;

  const GlassInputField({
    super.key,
    this.label,
    this.hint,
    this.errorText,
    this.controller,
    this.keyboardType = TextInputType.text,
    this.obscureText = false,
    this.prefixIcon,
    this.prefixWidget,
    this.suffixIcon,
    this.onChanged,
    this.maxLines = 1,
    this.enabled = true,
    this.focusNode,
    this.prefix,
    this.contentPadding,
  });

  @override
  State<GlassInputField> createState() => _GlassInputFieldState();
}

class _GlassInputFieldState extends State<GlassInputField> {
  late FocusNode _focusNode;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  void _handleFocusChange() {
    setState(() => _isFocused = _focusNode.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    final hasError = widget.errorText != null;
    final isDisabled = !widget.enabled;
    final hintColor =
        isDisabled ? AppColors.textDisabled : AppColors.textSecondary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null) ...[
          Text(widget.label!, style: AppTypography.label),
          const SizedBox(height: AppSpacing.sm),
        ],
        ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              decoration: BoxDecoration(
                color: isDisabled
                    ? Colors.grey.shade100.withValues(alpha: 0.7)
                    : Colors.grey.shade100.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                border: Border.all(
                  color: hasError
                      ? AppColors.error
                      : _isFocused
                      ? AppColors.primary.withValues(alpha: 0.24)
                      : Colors.transparent,
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: _isFocused ? 0.04 : 0.02),
                    blurRadius: _isFocused ? 14 : 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: TextField(
                controller: widget.controller,
                focusNode: _focusNode,
                keyboardType: widget.keyboardType,
                obscureText: widget.obscureText,
                onChanged: widget.onChanged,
                maxLines: widget.maxLines,
                enabled: widget.enabled,
                textAlignVertical: TextAlignVertical.center,
                style: AppTypography.input.copyWith(
                  color: isDisabled
                      ? AppColors.textDisabled
                      : AppColors.textPrimary,
                ),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.transparent,
                  hintText: widget.hint,
                  hintStyle: AppTypography.inputHint.copyWith(
                    color: hintColor,
                  ),
                  isDense: true,
                  contentPadding: widget.contentPadding ??
                      EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                        vertical: widget.maxLines > 1
                            ? AppSpacing.md
                            : AppSpacing.md,
                      ),
                  prefixIcon: widget.prefixWidget ??
                      (widget.prefixIcon != null
                          ? Icon(
                              widget.prefixIcon,
                              size: 20,
                              color: _isFocused
                                  ? AppColors.primary
                                  : AppColors.textSecondary,
                            )
                          : null),
                  prefixIconConstraints:
                      const BoxConstraints(minWidth: 44, minHeight: 44),
                  prefix: widget.prefix,
                  suffixIcon: widget.suffixIcon,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                ),
              ),
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

/// Backwards-compatible wrapper
class TextInputField extends GlassInputField {
  const TextInputField({
    super.key,
    super.label,
    super.hint,
    super.errorText,
    super.controller,
    super.keyboardType,
    super.obscureText,
    super.prefixIcon,
    super.suffixIcon,
    super.onChanged,
    super.maxLines,
    super.enabled,
    super.focusNode,
  });
}
