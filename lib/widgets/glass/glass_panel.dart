import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_shadows.dart';

/// Glass Panel Widget
/// Frosted glass container with blur effect for glassmorphism UI
class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final double blur;
  final Color? backgroundColor;
  final Color? borderColor;
  final List<BoxShadow>? boxShadow;
  final double? width;
  final double? height;
  final VoidCallback? onTap;

  const GlassPanel({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius = 24,
    this.blur = 16,
    this.backgroundColor,
    this.borderColor,
    this.boxShadow,
    this.width,
    this.height,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = backgroundColor ?? AppColors.glassSlateSoft;
    final border = borderColor ?? AppColors.glassSlateBorder;

    Widget content = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          width: width,
          height: height,
          padding: padding ?? const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                bgColor,
                bgColor.withValues(alpha: bgColor.a * 0.6),
              ],
            ),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: border, width: 1),
            boxShadow: boxShadow ?? AppShadows.glass,
          ),
          child: child,
        ),
      ),
    );

    if (margin != null) {
      content = Padding(padding: margin!, child: content);
    }

    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: content);
    }

    return content;
  }
}

/// Glass Card - Universal card with blur effect matching dashboard style
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final double blur;
  final Color? backgroundColor;
  final List<BoxShadow>? boxShadow;
  final VoidCallback? onTap;
  final Color? borderLeftColor;
  final double borderLeftWidth;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius = 20,
    this.blur = 12,
    this.backgroundColor,
    this.boxShadow,
    this.onTap,
    this.borderLeftColor,
    this.borderLeftWidth = 6,
  });

  @override
  Widget build(BuildContext context) {
    // Frosted Slate defaults
    final bgColor = backgroundColor ?? AppColors.glassSlateSoft;

    Widget content = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          margin: margin,
          padding: padding ?? const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(borderRadius),
            border: borderLeftColor != null
                ? Border(
                    left: BorderSide(
                      color: borderLeftColor!,
                      width: borderLeftWidth,
                    ),
                    top: BorderSide(
                      color: AppColors.glassSlateBorder,
                      width: 1,
                    ),
                    right: BorderSide(
                      color: AppColors.glassSlateBorder,
                      width: 1,
                    ),
                    bottom: BorderSide(
                      color: AppColors.glassSlateBorder,
                      width: 1,
                    ),
                  )
                : Border.all(color: AppColors.glassSlateBorder, width: 1),
          ),
          child: child,
        ),
      ),
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: content,
      );
    }

    return content;
  }
}
