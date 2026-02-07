import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Izumi App Shadows
/// Soft, diffused shadows for glassmorphism aesthetic
class AppShadows {
  AppShadows._();

  // ============ GLASS PANEL SHADOWS ============
  /// Main glass panel shadow - soft and diffused
  static List<BoxShadow> glass = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.18),
      blurRadius: 28,
      offset: const Offset(0, 10),
      spreadRadius: 0,
    ),
  ];

  /// Glass panel with stronger presence
  static List<BoxShadow> glassStrong = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.24),
      blurRadius: 36,
      offset: const Offset(0, 12),
      spreadRadius: 0,
    ),
  ];

  // ============ CARD SHADOWS ============
  /// Standard card shadow - subtle elevation
  static List<BoxShadow> card = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.06),
      blurRadius: 16,
      offset: const Offset(0, 4),
      spreadRadius: 0,
    ),
  ];

  /// Elevated card shadow - more prominent
  static List<BoxShadow> cardElevated = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.08),
      blurRadius: 24,
      offset: const Offset(0, 8),
      spreadRadius: 0,
    ),
  ];

  // ============ NAVIGATION SHADOWS ============
  /// Floating nav bar shadow
  static List<BoxShadow> navBar = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.25),
      blurRadius: 28,
      offset: const Offset(0, 12),
      spreadRadius: 0,
    ),
  ];

  /// Nav bar with stronger shadow for light backgrounds
  static List<BoxShadow> navBarStrong = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.35),
      blurRadius: 40,
      offset: const Offset(0, 14),
      spreadRadius: 0,
    ),
  ];

  // ============ BUTTON SHADOWS ============
  /// Primary button shadow with color glow
  static List<BoxShadow> primaryButton = [
    BoxShadow(
      color: AppColors.primary.withValues(alpha: 0.35),
      blurRadius: 18,
      offset: const Offset(0, 8),
      spreadRadius: 0,
    ),
  ];

  /// Subtle button shadow
  static List<BoxShadow> button = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.08),
      blurRadius: 8,
      offset: const Offset(0, 2),
      spreadRadius: 0,
    ),
  ];

  // ============ SPECIAL SHADOWS ============
  /// FAB shadow
  static List<BoxShadow> fab = [
    BoxShadow(
      color: AppColors.primary.withValues(alpha: 0.4),
      blurRadius: 24,
      offset: const Offset(0, 10),
      spreadRadius: 0,
    ),
  ];

  /// Inner shadow for pressed states (simulated)
  static List<BoxShadow> innerShadow = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.05),
      blurRadius: 4,
      offset: const Offset(0, 2),
      spreadRadius: -1,
    ),
  ];

  /// No shadow
  static List<BoxShadow> none = [];
}
