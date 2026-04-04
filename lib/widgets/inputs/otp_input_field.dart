import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
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
    _focusNode.addListener(() {
      if (mounted) setState(() {});
    });
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

  void _requestFocus() {
    FocusScope.of(context).unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasError = widget.errorText != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: _requestFocus,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(widget.length, (index) {
              final hasFocus = _focusNode.hasFocus;
              final isFilled = _value.length > index;
              final isActive = hasFocus && _value.length == index;
              final displayChar = isFilled ? _value[index] : '';

              return Padding(
                padding: EdgeInsets.only(
                  right: index < widget.length - 1 ? 10.0 : 0,
                ),
                child: SizedBox(
                  width: 48,
                  height: 56,
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isFilled
                          ? const Color(0xFFF0F7F1)
                          : const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: hasError
                            ? AppColors.error
                            : isActive
                                ? const Color(0xFF2E7D32)
                                : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      displayChar,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF111111),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
        // Hidden input for OTP entry
        SizedBox(
          height: 1,
          width: 1,
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            autofocus: false,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            maxLength: widget.length,
            onChanged: _onChanged,
            onTap: _requestFocus,
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
          const SizedBox(height: 16),
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
