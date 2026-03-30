import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/inputs/text_input_field.dart';

/// Welcome/Login Screen - Glassmorphism Design
/// Phone number login with role selection
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _phoneController = TextEditingController();
  final String _selectedCountryCode = '+91';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      final error = auth.errorMessage;
      if (error != null && error.contains('another device')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error),
            duration: const Duration(seconds: 5),
            backgroundColor: AppColors.warning,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
        auth.clearError();
      }
    });
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _signIn(String role) async {
    if (Platform.isIOS) {
      FocusScope.of(context).unfocus();
    }

    if (_phoneController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please enter your phone number'),
          backgroundColor: AppColors.critical,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final authProvider = context.read<AuthProvider>();
    final fullPhone = '$_selectedCountryCode${_phoneController.text.replaceAll(RegExp(r'\s+'), '')}';

    // Store pending registration data for new users
    authProvider.setPendingRegistration(
      name: '',
      phone: fullPhone,
      role: role,
    );
    authProvider.setPendingOtpRouteData(
      phoneNumber: '$_selectedCountryCode ${_phoneController.text}',
      role: role,
    );

    // Send OTP via Firebase Phone Auth
    await authProvider.sendOTP(fullPhone);

    if (!mounted) return;
    setState(() => _isLoading = false);

    // Check for immediate errors
    if (authProvider.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(authProvider.errorMessage!),
          backgroundColor: AppColors.critical,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      return;
    }

    // Navigate to OTP screen via GoRouter
    context.push('/otp', extra: {
      'phoneNumber': '$_selectedCountryCode ${_phoneController.text}',
      'role': role,
    });
  }

  @override
  Widget build(BuildContext context) {
    final dismissKeyboard = Platform.isIOS
        ? () => FocusScope.of(context).unfocus()
        : null;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: dismissKeyboard,
        child: SafeArea(
          child: SingleChildScrollView(
            keyboardDismissBehavior: Platform.isIOS
                ? ScrollViewKeyboardDismissBehavior.onDrag
                : ScrollViewKeyboardDismissBehavior.manual,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: MediaQuery.of(context).size.height -
                    MediaQuery.of(context).padding.top -
                    MediaQuery.of(context).padding.bottom,
              ),
              child: Column(
                children: [
                // Status bar spacer
                const SizedBox(height: 60),

                // Logo and branding
                _buildLogo(),
                const SizedBox(height: 48),

                // Phone input field
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.glassPrimary,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: AppColors.glassBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'PHONE NUMBER',
                              style: AppTypography.caption.copyWith(
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 10),
                            GlassInputField(
                              controller: _phoneController,
                              hint: '98XXX XXXXX',
                              keyboardType: TextInputType.phone,
                              prefixWidget: Padding(
                                padding: const EdgeInsets.only(
                                  left: 12,
                                  right: 10,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _selectedCountryCode,
                                      style: AppTypography.input.copyWith(
                                        color: AppColors.textPrimary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Container(
                                      width: 1,
                                      height: 22,
                                      color: AppColors.glassBorder,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Sign in buttons
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    children: [
                      _buildPrimaryButton(
                        _isLoading ? 'Sending OTP...' : 'Sign In',
                        onTap: _isLoading ? null : () => _signIn('employee'),
                      ),
                      const SizedBox(height: 16),
                      _buildGlassButton(
                        'Sign in as Enterprise',
                        onTap: _isLoading ? null : () {
                          context.push('/enterprise-login');
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                  const Spacer(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Column(
      children: [
        SvgPicture.asset(
          'assets/branding/izumi_logo.svg',
          width: 72,
          height: 72,
        ),
        const SizedBox(height: 16),
        Text(
          'IZUMI',
          style: AppTypography.h1.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Efficiency in motion',
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  // _buildPhoneCard removed in favor of PhoneInputField

  Widget _buildPrimaryButton(String label, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.6 : 1.0,
        child: Container(
          width: double.infinity,
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Center(child: Text(label, style: AppTypography.buttonLarge.copyWith(color: Colors.white))),
        ),
      ),
    );
  }

  Widget _buildGlassButton(String label, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.glassPrimary,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Center(
              child: Text(
                label,
                style: AppTypography.buttonLarge.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
