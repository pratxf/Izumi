import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_shadows.dart'; // Added for glass shadow
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_typography.dart';

/// OTP Input Field Widget
/// 4-box input with auto-advance cursor
class OtpInputField extends StatefulWidget {
  final int length;
  final ValueChanged<String>? onCompleted;
  final ValueChanged<String>? onChanged;
  final String? errorText;

  const OtpInputField({
    super.key,
    this.length = 4,
    this.onCompleted,
    this.onChanged,
    this.errorText,
  });

  @override
  State<OtpInputField> createState() => _OtpInputFieldState();
}

class _OtpInputFieldState extends State<OtpInputField> {
  late List<TextEditingController> _controllers;
  late List<FocusNode> _focusNodes;
  late List<String> _values;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(widget.length, (_) => TextEditingController());
    _focusNodes = List.generate(widget.length, (_) => FocusNode());
    _values = List.filled(widget.length, '');
  }

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    for (var focusNode in _focusNodes) {
      focusNode.dispose();
    }
    super.dispose();
  }

  void _onChanged(String value, int index) {
    if (value.length > 1) {
      value = value.substring(value.length - 1);
      _controllers[index].text = value;
    }

    _values[index] = value;
    final otp = _values.join();
    widget.onChanged?.call(otp);

    if (value.isNotEmpty && index < widget.length - 1) {
      _focusNodes[index + 1].requestFocus();
    }

    if (otp.length == widget.length) {
      widget.onCompleted?.call(otp);
    }
  }

  void _onKeyDown(KeyEvent event, int index) {
    if (event.logicalKey == LogicalKeyboardKey.backspace &&
        _controllers[index].text.isEmpty &&
        index > 0) {
      _focusNodes[index - 1].requestFocus();
      _controllers[index - 1].clear();
      _values[index - 1] = '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasError = widget.errorText != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(widget.length, (index) {
            final isFilled = _values[index].isNotEmpty;
            final isFocused = _focusNodes[index].hasFocus;

            return Padding(
              padding: EdgeInsets.only(
                right: index < widget.length - 1 ? AppSpacing.md : 0,
              ),
              child: KeyboardListener(
                focusNode: FocusNode(),
                onKeyEvent: (event) {
                  if (event is KeyDownEvent) {
                    _onKeyDown(event, index);
                  }
                },
                child: Container(
                  width: AppSpacing.otpBoxSize,
                  height: AppSpacing.otpBoxSize,
                  decoration: BoxDecoration(
                    color: AppColors.glassSlateSoft,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    border: Border.all(
                      color: hasError
                          ? AppColors.error
                          : isFocused || isFilled
                          ? AppColors.primary.withValues(alpha: 0.5)
                          : AppColors.glassSlateBorder,
                      width: 1,
                    ),
                    boxShadow: isFocused
                        ? [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.25),
                              blurRadius: 12,
                              spreadRadius: 0,
                            ),
                          ]
                        : AppShadows.glass,
                  ),
                  child: TextField(
                    controller: _controllers[index],
                    focusNode: _focusNodes[index],
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 1,
                    onChanged: (value) => _onChanged(value, index),
                    style: AppTypography.h1.copyWith(
                      fontSize: 24,
                      color: AppColors.textPrimary,
                    ),
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      counterText: '',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
        if (hasError) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            widget.errorText!,
            style: AppTypography.caption.copyWith(color: AppColors.errorDark),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}
