import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Izumi App Typography
/// Unified Enterprise Glass typography (Inter everywhere)
class AppTypography {
  AppTypography._();

  // Platform font family + fallbacks
  static String get fontFamily =>
      Platform.isIOS ? '.SF Pro Text' : GoogleFonts.inter().fontFamily!;

  static List<String> get fontFallbacks => Platform.isIOS
      ? const ['Helvetica Neue', 'Arial']
      : const ['Arial'];

  // Screen Titles (SemiBold)
  static TextStyle get displayLarge => _base(
    size: 40,
    weight: FontWeight.w700,
    letterSpacing: 0.8,
    height: 1.2,
  );

  // Section Title (SemiBold)
  static TextStyle get h1 => _base(
    size: 32,
    weight: FontWeight.w700,
    letterSpacing: 0.6,
    height: 1.2,
  );

  // Section Header (SemiBold)
  static TextStyle get h2 => _base(
    size: 22,
    weight: FontWeight.w600,
    letterSpacing: 0.4,
    height: 1.4,
  );

  // Section Header (Medium)
  static TextStyle get h3 => _base(
    size: 20,
    weight: FontWeight.w600,
    letterSpacing: 0.3,
    height: 1.4,
  );

  // Headline (Medium)
  static TextStyle get headline => _base(
    size: 18,
    weight: FontWeight.w500,
    letterSpacing: 0.3,
    height: 1.4,
  );

  // Body (Regular)
  static TextStyle get bodyLarge => _base(
    size: 18,
    weight: FontWeight.w400,
    letterSpacing: 0.5,
    height: 1.6,
  );

  // Body (Regular)
  static TextStyle get body => _base(
    size: 16,
    weight: FontWeight.w400,
    letterSpacing: 0.5,
    height: 1.6,
  );

  // Body (Regular)
  static TextStyle get bodyMedium => _base(
    size: 16,
    weight: FontWeight.w400,
    letterSpacing: 0.5,
    height: 1.6,
  );

  // Labels / Meta (Regular)
  static TextStyle get caption => _base(
    size: 13,
    weight: FontWeight.w300,
    letterSpacing: 0.3,
    height: 1.4,
    color: AppColors.textSecondary,
  );

  // Meta Small (Regular)
  static TextStyle get small => _base(
    size: 12,
    weight: FontWeight.w300,
    letterSpacing: 0.3,
    height: 1.4,
    color: AppColors.textTertiary,
  );

  // Button Text
  static TextStyle get buttonLarge => _base(
    size: 16,
    weight: FontWeight.w500,
    letterSpacing: 0.4,
    height: 1.2,
  );

  static TextStyle get buttonMedium => _base(
    size: 16,
    weight: FontWeight.w500,
    letterSpacing: 0.4,
    height: 1.2,
  );

  // Input Text
  static TextStyle get input => _base(
    size: 16,
    weight: FontWeight.w400,
    letterSpacing: 0.5,
    height: 1.4,
  );

  static TextStyle get inputHint => _base(
    size: 16,
    weight: FontWeight.w400,
    letterSpacing: 0.5,
    height: 1.4,
    color: AppColors.textTertiary,
  );

  // Label
  static TextStyle get label => _base(
    size: 13,
    weight: FontWeight.w400,
    letterSpacing: 0.3,
    height: 1.4,
    color: AppColors.textSecondary,
  );
  // Tab Bar (10pt)
  static TextStyle get tabActive => _base(
    size: 12,
    weight: FontWeight.w600,
    letterSpacing: 0.3,
    height: 1.2,
    color: AppColors.primary,
  );

  static TextStyle get tabInactive => _base(
    size: 12,
    weight: FontWeight.w500,
    letterSpacing: 0.3,
    height: 1.2,
    color: AppColors.textTertiary,
  );

  // Body Small (13pt) - Smaller body text
  static TextStyle get bodySmall => _base(
    size: 14,
    weight: FontWeight.w400,
    letterSpacing: 0.4,
    height: 1.6,
    color: AppColors.textSecondary,
  );

  // Overline (10pt) - Smallest text, all caps style
  static TextStyle get overline => _base(
    size: 12,
    weight: FontWeight.w500,
    letterSpacing: 0.6,
    height: 1.3,
    color: AppColors.textTertiary,
  );

  static TextStyle _base({
    required double size,
    required FontWeight weight,
    double letterSpacing = 0.0,
    double height = 1.4,
    Color color = AppColors.textPrimary,
  }) {
    final baseStyle = Platform.isIOS
        ? TextStyle(fontFamily: fontFamily)
        : GoogleFonts.inter();
    return baseStyle.copyWith(
      fontSize: size,
      fontWeight: weight,
      color: color,
      decoration: TextDecoration.none,
      letterSpacing: letterSpacing,
      height: height,
      fontFamilyFallback: fontFallbacks,
    );
  }
}
