import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Izumi App Typography
/// Unified Enterprise Glass typography (Inter everywhere)
class AppTypography {
  AppTypography._();

  // Font Family
  static String get fontFamily => GoogleFonts.inter().fontFamily!;

  // Screen Titles (SemiBold)
  static TextStyle get displayLarge => GoogleFonts.inter(
    fontSize: 34,
    fontWeight: FontWeight.w600, // SemiBold
    color: AppColors.textPrimary,
    decoration: TextDecoration.none,
    letterSpacing: -0.4,
    height: 1.2,
  );

  // Section Title (SemiBold)
  static TextStyle get h1 => GoogleFonts.inter(
    fontSize: 28,
    fontWeight: FontWeight.w600, // SemiBold
    color: AppColors.textPrimary,
    decoration: TextDecoration.none,
    letterSpacing: -0.4,
    height: 1.2,
  );

  // Section Header (SemiBold)
  static TextStyle get h2 => GoogleFonts.inter(
    fontSize: 22,
    fontWeight: FontWeight.w600, // SemiBold
    color: AppColors.textPrimary,
    decoration: TextDecoration.none,
    letterSpacing: -0.4,
    height: 1.3,
  );

  // Section Header (Medium)
  static TextStyle get h3 => GoogleFonts.inter(
    fontSize: 20,
    fontWeight: FontWeight.w500, // Medium
    color: AppColors.textPrimary,
    decoration: TextDecoration.none,
    letterSpacing: -0.4,
    height: 1.3,
  );

  // Headline (Medium)
  static TextStyle get headline => GoogleFonts.inter(
    fontSize: 17,
    fontWeight: FontWeight.w500, // Medium
    color: AppColors.textPrimary,
    decoration: TextDecoration.none,
    letterSpacing: -0.4,
    height: 1.3,
  );

  // Body (Regular)
  static TextStyle get bodyLarge => GoogleFonts.inter(
    fontSize: 17,
    fontWeight: FontWeight.w400, // Regular
    color: AppColors.textPrimary,
    decoration: TextDecoration.none,
    letterSpacing: -0.4,
    height: 1.5,
  );

  // Body (Regular)
  static TextStyle get body => GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w400, // Regular
    color: AppColors.textPrimary,
    decoration: TextDecoration.none,
    letterSpacing: -0.3,
    height: 1.5,
  );

  // Body (Regular)
  static TextStyle get bodyMedium => GoogleFonts.inter(
    fontSize: 15,
    fontWeight: FontWeight.w400, // Regular
    color: AppColors.textPrimary,
    decoration: TextDecoration.none,
    letterSpacing: -0.2,
    height: 1.5,
  );

  // Labels / Meta (Regular)
  static TextStyle get caption => GoogleFonts.inter(
    fontSize: 13,
    fontWeight: FontWeight.w400, // Regular
    color: AppColors.textSecondary,
    decoration: TextDecoration.none,
    letterSpacing: -0.1,
    height: 1.4,
  );

  // Meta Small (Regular)
  static TextStyle get small => GoogleFonts.inter(
    fontSize: 11,
    fontWeight: FontWeight.w400, // Regular
    color: AppColors.textTertiary,
    decoration: TextDecoration.none,
    letterSpacing: 0,
    height: 1.4,
  );

  // Button Text
  static TextStyle get buttonLarge => GoogleFonts.inter(
    fontSize: 17,
    fontWeight: FontWeight.w500, // Medium
    color: AppColors.textPrimary,
    decoration: TextDecoration.none,
    letterSpacing: -0.4,
    height: 1.2,
  );

  static TextStyle get buttonMedium => GoogleFonts.inter(
    fontSize: 15,
    fontWeight: FontWeight.w500, // Medium
    color: AppColors.textPrimary,
    decoration: TextDecoration.none,
    letterSpacing: -0.2,
    height: 1.2,
  );

  // Input Text
  static TextStyle get input => GoogleFonts.inter(
    fontSize: 17,
    fontWeight: FontWeight.w400, // Regular
    color: AppColors.textPrimary,
    decoration: TextDecoration.none,
    letterSpacing: -0.4,
    height: 1.3,
  );

  static TextStyle get inputHint => GoogleFonts.inter(
    fontSize: 17,
    fontWeight: FontWeight.w400, // Regular
    color: AppColors.textTertiary,
    decoration: TextDecoration.none,
    letterSpacing: -0.4,
    height: 1.3,
  );

  // Label
  static TextStyle get label => GoogleFonts.inter(
    fontSize: 13,
    fontWeight: FontWeight.w400, // Regular
    color: AppColors.textSecondary,
    decoration: TextDecoration.none,
    letterSpacing: -0.1,
    height: 1.4,
  );
  // Tab Bar (10pt)
  static TextStyle get tabActive => GoogleFonts.inter(
    fontSize: 10,
    fontWeight: FontWeight.w600,
    color: AppColors.primary,
    decoration: TextDecoration.none,
    letterSpacing: -0.1,
    height: 1.2,
  );

  static TextStyle get tabInactive => GoogleFonts.inter(
    fontSize: 10,
    fontWeight: FontWeight.w500,
    color: AppColors.textTertiary,
    decoration: TextDecoration.none,
    letterSpacing: -0.1,
    height: 1.2,
  );

  // Body Small (13pt) - Smaller body text
  static TextStyle get bodySmall => GoogleFonts.inter(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    decoration: TextDecoration.none,
    letterSpacing: -0.1,
    height: 1.4,
  );

  // Overline (10pt) - Smallest text, all caps style
  static TextStyle get overline => GoogleFonts.inter(
    fontSize: 10,
    fontWeight: FontWeight.w500,
    color: AppColors.textTertiary,
    decoration: TextDecoration.none,
    letterSpacing: 0.5,
    height: 1.3,
  );
}
