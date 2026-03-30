import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';

class SwipeToReplyWrapper extends StatefulWidget {
  final bool enabled;
  final bool isMe;
  final VoidCallback onReply;
  final Widget child;

  const SwipeToReplyWrapper({
    super.key,
    required this.enabled,
    required this.isMe,
    required this.onReply,
    required this.child,
  });

  @override
  State<SwipeToReplyWrapper> createState() => _SwipeToReplyWrapperState();
}

class _SwipeToReplyWrapperState extends State<SwipeToReplyWrapper>
    with SingleTickerProviderStateMixin {
  static const double _maxTranslate = 72;
  static const double _triggerThreshold = 52;
  static const double _verticalLockThreshold = 12;

  late final AnimationController _resetController;
  Animation<double>? _resetAnimation;
  double _dragOffset = 0;
  bool _didTrigger = false;
  bool _isHorizontalDrag = false;

  @override
  void initState() {
    super.initState();
    _resetController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    )..addListener(() {
        final animation = _resetAnimation;
        if (animation == null) return;
        setState(() => _dragOffset = animation.value);
      });
  }

  @override
  void dispose() {
    _resetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    final progress = (_dragOffset.abs() / _triggerThreshold).clamp(0.0, 1.0);
    final iconAlignment =
        widget.isMe ? Alignment.centerRight : Alignment.centerLeft;
    final iconPadding = EdgeInsets.only(
      left: widget.isMe ? 0 : AppSpacing.md,
      right: widget.isMe ? AppSpacing.md : 0,
    );

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) {
        _resetController.stop();
        _resetAnimation = null;
        _didTrigger = false;
        _isHorizontalDrag = false;
      },
      onHorizontalDragUpdate: (details) {
        final dx = details.delta.dx;
        final dy = details.delta.dy.abs();

        if (!_isHorizontalDrag && dy > _verticalLockThreshold && dy > dx.abs()) {
          return;
        }

        final intendedDirection = widget.isMe ? math.min(dx, 0.0) : math.max(dx, 0.0);
        if (intendedDirection == 0) return;

        _isHorizontalDrag = true;
        final nextOffset = (_dragOffset + intendedDirection)
            .clamp(-_maxTranslate, _maxTranslate);

        setState(() => _dragOffset = nextOffset);

        if (!_didTrigger && _dragOffset.abs() >= _triggerThreshold) {
          _didTrigger = true;
          HapticFeedback.lightImpact();
          widget.onReply();
        }
      },
      onHorizontalDragEnd: (_) => _animateBack(),
      onHorizontalDragCancel: _animateBack,
      child: Stack(
        alignment: iconAlignment,
        children: [
          IgnorePointer(
            child: Padding(
              padding: iconPadding,
              child: Opacity(
                opacity: progress,
                child: Transform.scale(
                  scale: 0.88 + (0.12 * progress),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.22),
                      ),
                    ),
                    child: const Icon(
                      Icons.reply_rounded,
                      size: 18,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Transform.translate(
            offset: Offset(_dragOffset, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }

  void _animateBack() {
    _isHorizontalDrag = false;
    _resetAnimation = Tween<double>(
      begin: _dragOffset,
      end: 0,
    ).animate(CurvedAnimation(
      parent: _resetController,
      curve: Curves.easeOutCubic,
    ));
    _resetController
      ..reset()
      ..forward();
  }
}
