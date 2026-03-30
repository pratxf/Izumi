import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

/// Gradient Background Widget
/// Midnight slate gradient background for all screens
class GradientBackground extends StatelessWidget {
  final Widget child;

  const GradientBackground({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.backgroundGradient,
      ),
      child: child,
    );
  }
}

/// Gradient Scaffold
/// Complete scaffold with gradient background and safe area handling
class GradientScaffold extends StatelessWidget {
  final Widget body;
  final Widget? bottomNavigationBar;
  final bool extendBody;
  final bool extendBodyBehindAppBar;

  const GradientScaffold({
    super.key,
    required this.body,
    this.bottomNavigationBar,
    this.extendBody = true,
    this.extendBodyBehindAppBar = true,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: extendBody,
      extendBodyBehindAppBar: extendBodyBehindAppBar,
      backgroundColor: Colors.transparent,
      body: GradientBackground(child: body),
      bottomNavigationBar: bottomNavigationBar,
    );
  }
}

/// Scrollable Content Panel
/// White/glass scrollable area with rounded top corners (like Admin Dashboard)
class ScrollableContentPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double topRadius;
  final Color? backgroundColor;
  final ScrollController? controller;

  const ScrollableContentPanel({
    super.key,
    required this.child,
    this.padding,
    this.topRadius = 32,
    this.backgroundColor,
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = backgroundColor ?? AppColors.glassStrong;

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(topRadius),
          topRight: Radius.circular(topRadius),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 36,
            offset: const Offset(0, -10),
          ),
        ],
        border: Border.all(color: AppColors.glassBorder, width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(topRadius),
          topRight: Radius.circular(topRadius),
        ),
        child: SingleChildScrollView(
          controller: controller,
          padding: padding ?? const EdgeInsets.all(24),
          child: child,
        ),
      ),
    );
  }
}

