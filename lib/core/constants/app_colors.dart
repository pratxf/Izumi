import 'package:flutter/material.dart';

/// Izumi App Color Palette
/// Apple-Style Light Frosted Glass Design System
class AppColors {
  AppColors._();

  // ============ PRIMARY ACCENT ============
  /// Indigo - Main actions, focus states
  static const Color primary = Color(0xFF4F46E5);
  static const Color primaryLight = Color(0xFF6366F1);
  static const Color primaryDark = Color(0xFF4338CA);
  static const Color accent = primary;

  // ============ GRADIENT BACKGROUND ============
  /// Soft Light Surface
  static const Color gradientStart = Color(0xFFFFFFFF);
  static const Color gradientMid = Color(0xFFF5F7FA);
  static const Color gradientEnd = Color(0xFFEEF2F7);

  // ============ GLASS PANEL (Apple Frosted Light) ============
  static const Color glassPrimary = Color(0xB3FFFFFF); // 70%
  static const Color glassStrong = Color(0xD9FFFFFF); // 85%
  static const Color glassBorder = Color(0x99D1D5DB); // 60%
  static const Color glassHeader = Color(0xCCFFFFFF); // 80%
  static const Color glassNav = Color(0xE6FFFFFF); // 90%
  static const Color glassHover = Color(0xFFF3F4F6); // solid hover

  // Aliases for implementation convenience
  static const Color glassPanel = glassPrimary;

  // ============ NAVIGATION BAR ============
  static const Color navBarBackground = glassNav;
  static const Color navBarActivePill = Color(0xFFEEF2FF);
  static const Color navBarInactiveIcon = Color(0xFF6B7280);

  // ============ TEXT COLORS (Apple Style Hierarchy) ============
  /// Primary Text (high emphasis)
  static const Color textPrimary = Color(0xFF0F172A);

  /// Secondary Text (body/support)
  static const Color textSecondary = Color(0xFF334155);

  /// Tertiary Text (muted structure)
  static const Color textTertiary = Color(0xFF64748B);

  /// Disabled / Subtle Text
  static const Color textDisabled = Color(0xFF9CA3AF);

  // Semantics mapping
  static const Color textOnGradient = textPrimary;
  static const Color textOnGradientMuted = textSecondary;
  static const Color textOnCard = textPrimary;
  static const Color textOnCardMuted = textSecondary;

  // ============ SEMANTIC COLORS ============
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color critical = Color(0xFFEF4444);
  static const Color info = Color(0xFF4F46E5);
  static const Color error = critical;

  // ============ SURFACE COLORS ============
  static const Color surface = glassStrong;
  static const Color surfaceLight = glassPrimary;
  static const Color surfaceMuted = Color(0x1F94A3B8);

  static const Color border = glassBorder;
  static const Color divider = Color(0xFFE5E7EB);

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
  static const Color badgeActiveBackground = Color(0x2E22C55E); // 18%
  static const Color badgeBreakBackground = Color(0x2EF59E0B); // 18%
  static const Color badgeOfflineBackground = Color(0x59CBD5E1); // 35%
  static const Color badgeHighPriority = Color(0x2EEF4444); // 18%
  static const Color badgeMediumPriority = Color(0x2EF59E0B); // 18%

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

  // Restored aliases
  static const Color badgeSuccess = Color(0x2E22C55E);
  static const Color badgeWarning = Color(0x2EF59E0B);
  static const Color warningDark = warning;
  static const LinearGradient backgroundGradientDark = backgroundGradient;

  static const Color badgeInfo = Color(0x2E4F46E5);

  // Backwards compatibility
  static const Color glassSlateSoft = glassPrimary;
  static const Color glassSlateStrong = glassStrong;
  static const Color glassSlateBorder = glassBorder;
  static const Color textMuted = textDisabled;
}
