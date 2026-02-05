import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

/// Gradient Background Widget
/// Teal mesh gradient background for all screens
class GradientBackground extends StatelessWidget {
  final Widget child;
  final bool isDark;

  const GradientBackground({
    super.key,
    required this.child,
    this.isDark = false,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final useDark = isDark || brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        gradient: useDark
            ? AppColors.backgroundGradientDark
            : AppColors.backgroundGradient,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor =
        backgroundColor ??
        (isDark
            ? const Color(0xCC0F172A) // 80% slate-900
            : const Color(0xCCFFFFFF)); // 80% white

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(topRadius),
          topRight: Radius.circular(topRadius),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 40,
            offset: const Offset(0, -10),
          ),
        ],
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
