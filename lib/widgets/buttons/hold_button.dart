import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_typography.dart';

/// Hold to Confirm Button Widget
/// Requires 2-second hold to trigger action
/// Shows circular progress animation during hold
class HoldButton extends StatefulWidget {
  final String label;
  final VoidCallback? onComplete;
  final Duration holdDuration;
  final bool isEnabled;

  const HoldButton({
    super.key,
    required this.label,
    this.onComplete,
    this.holdDuration = const Duration(seconds: 2),
    this.isEnabled = true,
  });

  @override
  State<HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<HoldButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _isHolding = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.holdDuration,
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        HapticFeedback.heavyImpact();
        widget.onComplete?.call();
        _reset();
      }
    });

    _controller.addListener(() {
      // Haptic feedback at 50%
      if (_controller.value >= 0.5 && _controller.value < 0.52) {
        HapticFeedback.mediumImpact();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _startHold() {
    if (!widget.isEnabled) return;
    setState(() => _isHolding = true);
    HapticFeedback.lightImpact();
    _controller.forward();
  }

  void _reset() {
    setState(() => _isHolding = false);
    _controller.reset();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _startHold(),
      onTapUp: (_) => _reset(),
      onTapCancel: _reset,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Container(
            width: double.infinity,
            height: AppSpacing.buttonHeight,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(
                color: widget.isEnabled ? AppColors.primary : AppColors.border,
                width: 2,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd - 2),
              child: Stack(
                children: [
                  // Progress fill
                  Positioned.fill(
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: _controller.value,
                      child: Container(
                        color: AppColors.primary.withValues(alpha: 0.2),
                      ),
                    ),
                  ),
                  // Label
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isHolding) ...[
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              value: _controller.value,
                              strokeWidth: 2.5,
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                AppColors.primary,
                              ),
                              backgroundColor: AppColors.border,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                        ],
                        Text(
                          widget.label,
                          style: AppTypography.buttonMedium.copyWith(
                            color: widget.isEnabled
                                ? AppColors.primary
                                : AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
