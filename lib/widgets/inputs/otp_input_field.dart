import 'package:flutter/material.dart';
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
  late TextEditingController _controller;
  late FocusNode _focusNode;
  String _value = '';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    if (value.length > widget.length) {
      value = value.substring(0, widget.length);
      _controller.text = value;
      _controller.selection = TextSelection.collapsed(offset: value.length);
    }
    setState(() => _value = value);
    widget.onChanged?.call(value);
    if (value.length == widget.length) {
      widget.onCompleted?.call(value);
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
            final hasFocus = _focusNode.hasFocus;
            final isFilled = _value.length > index;
            final isActive = hasFocus && _value.length == index;
            final displayChar = isFilled ? _value[index] : '';

            return Padding(
              padding: EdgeInsets.only(
                right: index < widget.length - 1 ? AppSpacing.md : 0,
              ),
              child: GestureDetector(
                onTap: () => _focusNode.requestFocus(),
                child: Container(
                  width: 64,
                  height: 64,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.glassPrimary,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: hasError
                          ? AppColors.error
                          : isActive || isFilled
                          ? AppColors.primary.withValues(alpha: 0.5)
                          : AppColors.glassBorder,
                      width: 1,
                    ),
                    boxShadow: isActive
                        ? [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.25),
                              blurRadius: 18,
                            ),
                          ]
                        : AppShadows.glass,
                  ),
                  child: Text(
                    displayChar,
                    style: AppTypography.h2.copyWith(
                      fontSize: 22,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
        // Hidden input for OTP entry
        SizedBox(
          height: 0,
          width: 0,
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            maxLength: widget.length,
            onChanged: _onChanged,
            style: const TextStyle(color: Colors.transparent, fontSize: 1),
            cursorColor: Colors.transparent,
            enableInteractiveSelection: false,
            decoration: const InputDecoration(
              counterText: '',
              border: InputBorder.none,
            ),
          ),
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

