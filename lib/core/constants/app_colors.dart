import 'package:flutter/material.dart';

/// Izumi App Color Palette
/// Unified Enterprise Glass Design System (Indigo/Slate)
class AppColors {
  AppColors._();

  // ============ PRIMARY ACCENT (Enterprise System) ============
  /// Royal Indigo - Main actions, focus states
  static const Color primary = Color(0xFF6366F1);
  static const Color primaryLight = Color(0xFF818CF8);
  static const Color primaryDark = Color(0xFF4F46E5);
  static const Color accent = primary;

  // ============ GRADIENT BACKGROUND ============
  /// Midnight Slate Gradient
  static const Color gradientStart = Color(0xFF0F172A); // Slate 900
  static const Color gradientMid = Color(0xFF1E293B); // Slate 800
  static const Color gradientEnd = Color(0xFF334155); // Slate 700

  // ============ GLASS PANEL (Frosted Slate) ============
  /// Subtle depth without visual noise
  static const Color glassPrimary = Color(0x730F172A); // 45%
  static const Color glassStrong = Color(0xA60F172A); // 65%
  static const Color glassBorder = Color(0x5E94A3B8); // 37%
  static const Color glassHeader = Color(0x990F172A); // 60%
  static const Color glassNav = Color(0xCC0F172A); // 80%
  static const Color glassHover = Color(0x8A1E293B); // hover/active

  // Aliases for implementation convenience
  static const Color glassPanel = glassPrimary;

  // ============ NAVIGATION BAR ============
  static const Color navBarBackground = glassNav;
  static const Color navBarActivePill = Color(0xFF1E293B);
  static const Color navBarInactiveIcon = Color(0xFF94A3B8);

  // ============ TEXT COLORS (Primary Reading Hierarchy) ============
  /// Primary Text (high emphasis)
  static const Color textPrimary = Color(0xFFF8FAFC);

  /// Secondary Text (body/support)
  static const Color textSecondary = Color(0xFFCBD5E1);

  /// Tertiary Text (muted structure)
  static const Color textTertiary = Color(0xFF94A3B8);

  /// Disabled / Subtle Text
  static const Color textDisabled = Color(0xFF64748B);

  // Semantics mapping
  static const Color textOnGradient = textPrimary;
  static const Color textOnGradientMuted = textSecondary;
  static const Color textOnCard = textPrimary;
  static const Color textOnCardMuted = textSecondary;

  // ============ SEMANTIC COLORS (Enterprise Accent) ============
  static const Color success = Color(0xFF10B981); // Emerald
  static const Color warning = Color(0xFFD97706); // Amber
  static const Color critical = Color(0xFFDC2626); // Red
  static const Color info = Color(0xFF6366F1); // Indigo (Primary)
  static const Color error = critical;

  // ============ SURFACE COLORS ============
  static const Color surface = glassStrong;
  static const Color surfaceLight = glassPrimary;
  static const Color surfaceMuted = Color(0x1F0F172A);

  static const Color border = glassBorder;
  static const Color divider = glassBorder;

  // ============ GRADIENTS ============
  /// Main background gradient
  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [gradientStart, gradientMid, gradientEnd],
    stops: [0.0, 0.5, 1.0],
  );

  /// Glass Panel Gradient
  static const LinearGradient glassPanelGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [glassPrimary, glassStrong],
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

  static const Color iconPurple = info;
  static const Color iconOrange = warning;
  static const Color iconGreen = success;
  static const Color iconBlue = info;
  static const Color iconRed = critical;
  static const Color iconTeal = success;
  static const Color iconAmber = warning;

  static const Color priorityHigh = critical;
  static const Color priorityMedium = warning;
  static const Color priorityLow = textTertiary;
  static const Color inactiveGrey = textDisabled;

  // Legacy glass aliases
  static const Color glassWhite = glassPrimary;
  static const Color glassWhiteStrong = glassStrong;
  static const Color glassDark = glassStrong;

  // Restored aliases (Fixing analysis errors)
  static const Color badgeSuccess = Color(0x3310B981);
  static const Color badgeWarning = Color(0x33D97706);
  static const Color warningDark = warning;
  static const LinearGradient backgroundGradientDark = backgroundGradient;

  static const Color badgeInfo = Color(0x336366F1);

  // Backwards compatibility
  static const Color glassSlateSoft = glassPrimary;
  static const Color glassSlateStrong = glassStrong;
  static const Color glassSlateBorder = glassBorder;
  static const Color textMuted = textDisabled;
}
