import 'package:flutter/material.dart';

/// Izumi App Color Palette
/// Strict Enterprise Glassmorphism Theme (Indigo/Slate)
class AppColors {
  AppColors._();

  // ============ PRIMARY ACCENT (Enterprise System) ============
  /// Royal Indigo - Main actions, focus states
  static const Color primary = Color(0xFF6366F1);
  static const Color primaryLight = Color(0xFF818CF8); // Interactive Accent
  static const Color primaryDark = Color(0xFF4F46E5);

  // ============ GRADIENT BACKGROUND ============
  /// Frosted Slate Gradient
  static const Color gradientStart = Color(0xFF0F172A); // Slate 900
  static const Color gradientMid = Color(0xFF1E293B); // Slate 800
  static const Color gradientEnd = Color(0xFF334155); // Slate 700

  // ============ GLASS PANEL (Frosted Slate) ============
  /// Subtle depth without visual noise
  static const Color glassSlateSoft = Color(
    0x730F172A,
  ); // rgba(15, 23, 42, 0.45)
  static const Color glassSlateStrong = Color(
    0xA60F172A,
  ); // rgba(15, 23, 42, 0.65)
  static const Color glassSlateBorder = Color(
    0x4094A3B8,
  ); // rgba(148, 163, 184, 0.25)

  // Aliases for compatibility
  static const Color glassWhite = glassSlateSoft;
  static const Color glassWhiteStrong = glassSlateStrong;
  static const Color glassBorder = glassSlateBorder;
  static const Color glassDark = glassSlateStrong;

  // ============ NAVIGATION BAR ============
  static const Color navBarBackground = Color(
    0xD90F172A,
  ); // Slate 900 with opacity
  static const Color navBarActivePill = Color(0xFF1E293B);
  static const Color navBarInactiveIcon = Color(0xFF94A3B8);

  // ============ TEXT COLORS (Primary Reading Hierarchy) ============
  /// Primary Text (high emphasis) - Main content, titles
  static const Color textPrimary = Color(0xFFF8FAFC);

  /// Secondary Text (body/support) - Descriptions, labels
  static const Color textSecondary = Color(0xFFCBD5E1);

  /// Tertiary Text (muted structure) - Hints, timestamps
  static const Color textTertiary = Color(0xFF94A3B8);

  /// Disabled / Subtle Text
  static const Color textMuted = Color(0xFF64748B);

  // ============ SEMANTIC COLORS (Enterprise Accent) ============
  static const Color success = Color(0xFF10B981); // Confirmations
  static const Color warning = Color(0xFFD97706); // Attention
  static const Color critical = Color(0xFFDC2626); // Escalations/Urgent (Error)
  static const Color info = Color(0xFF6366F1); // Primary/Info
  static const Color error = critical; // Alias

  // ============ SEMANTIC TEXT COLORS ============
  static const Color textSuccess = Color(0xFF34D399);
  static const Color textWarning = Color(0xFFFBBF24);
  static const Color textCritical = Color(0xFFF87171);
  static const Color textAccent = Color(0xFF818CF8);

  // ============ SURFACE COLORS ============
  static const Color surface = glassSlateStrong;
  static const Color surfaceLight = glassSlateSoft;
  static const Color surfaceMuted = Color(0x1A0F172A);

  static const Color border = glassSlateBorder;
  static const Color divider = glassSlateBorder;

  // ============ GRADIENTS ============
  /// Main background gradient
  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [gradientStart, gradientMid, gradientEnd],
    stops: [0.0, 0.5, 1.0],
  );

  /// Highlight Glow for headers
  static const LinearGradient highlightGlow = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1E293B), Color(0xFF475569)],
  );

  static const LinearGradient glassPanelGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [glassSlateSoft, glassSlateStrong],
  );

  // ============ STATUS BADGES ============
  static const Color badgeActiveBackground = Color(0x3310B981);
  static const Color badgeBreakBackground = Color(0x33F59E0B);
  static const Color badgeOfflineBackground = Color(0x3394A3B8);
  static const Color badgeHighPriority = Color(0x33DC2626);
  static const Color badgeMediumPriority = Color(0x33D97706);

  // ============ LEGACY COMPATIBILITY ============
  static const Color background = gradientStart;
  static const Color secondary = surfaceMuted;
  static const Color errorDark = critical;
  static const Color successDark = success;
  static const Color activeGreen = success;

  static const Color iconPurple = info; // Mapped to primary/info
  static const Color iconOrange = warning; // Map to warning
  static const Color iconGreen = success;
  static const Color iconBlue = info;
  static const Color iconRed = critical;
  static const Color iconTeal = Color(0xFF2DD4BF);
  static const Color iconAmber = warning;

  static const Color priorityHigh = critical;
  static const Color priorityMedium = warning;
  static const Color priorityLow = textTertiary;
  static const Color inactiveGrey = textMuted;

  // Restored aliases for compatibility
  static const Color textOnGradient = textPrimary;
  static const Color textOnGradientMuted = textSecondary;
  static const LinearGradient backgroundGradientDark = backgroundGradient;

  static const Color badgeSuccess = Color(0x3310B981);
  static const Color badgeWarning = Color(0x33D97706);
  static const Color warningDark = warning;

  static const Color badgeInfo = Color(0x336366F1);
}
