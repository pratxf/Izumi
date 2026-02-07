import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../widgets/inputs/otp_input_field.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';
import '../admin/admin_shell.dart';
import '../employee/employee_shell.dart';

/// OTP Verification Screen - Glassmorphism Design
class OtpScreen extends StatefulWidget {
  final String phoneNumber;
  final String role;

  const OtpScreen({super.key, required this.phoneNumber, required this.role});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  int _resendTimer = 45;
  Timer? _timer;
  bool _canResend = false;
  String _otpValue = '';

  @override
  void initState() {
    super.initState();
    _startResendTimer();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _timer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _startResendTimer() {
    setState(() {
      _resendTimer = 45;
      _canResend = false;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendTimer > 0) {
        setState(() => _resendTimer--);
      } else {
        setState(() => _canResend = true);
        timer.cancel();
      }
    });
  }

  void _verifyOtp() {
    if (_otpValue.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please enter the complete OTP'),
          backgroundColor: AppColors.critical,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      return;
    }

    // Navigate based on role
    Widget destination;
    if (widget.role == 'admin') {
      destination = const AdminShell();
    } else {
      destination = EmployeeShell(isTeamLead: widget.role == 'team_lead');
    }

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => destination),
      (route) => false,
    );
  }

  String get _maskedPhone {
    final parts = widget.phoneNumber.split(' ');
    if (parts.length < 2) return widget.phoneNumber;
    final number = parts.last;
    if (number.length < 4) return widget.phoneNumber;
    final masked =
        '${number.substring(0, 2)}XXX XX${number.substring(number.length - 3)}';
    return '${parts.first} $masked';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: Stack(
          children: [
            // Decorative blurs
            Positioned(
              top: -80,
              right: -80,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withValues(alpha: 0.15),
                ),
              ),
            ),
            Positioned(
              bottom: 100,
              left: -80,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withValues(alpha: 0.1),
                ),
              ),
            ),

            SafeArea(
              child: Column(
                children: [
                  // Back button
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                            color: AppColors.glassPrimary,
                            ),
                            child: Icon(
                              Icons.arrow_back_ios_new,
                              size: 18,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Logo
                  _buildLogo(),
                  const SizedBox(height: 16),

                  // Title
                  Text(
                    'Verification',
                    style: AppTypography.h1.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Enter the 4-digit code sent to',
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _maskedPhone,
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 40),

                  // OTP Inputs
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: OtpInputField(
                      length: 4,
                      onChanged: (value) => setState(() => _otpValue = value),
                      onCompleted: (value) =>
                          setState(() => _otpValue = value),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Resend
                  Text(
                    "Didn't receive the code?",
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: _canResend ? _startResendTimer : null,
                        child: Text(
                          'Resend OTP',
                          style: AppTypography.bodyMedium.copyWith(
                            color: _canResend
                                ? AppColors.primary
                                : AppColors.textDisabled,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (!_canResend) ...[
                        const SizedBox(width: 8),
                        Text(
                          '(00:${_resendTimer.toString().padLeft(2, '0')})',
                          style: AppTypography.bodyMedium.copyWith(
                            color: AppColors.textDisabled,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),

                  const Spacer(),

                  // Verify Button
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: GestureDetector(
                      onTap: _verifyOtp,
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
                        child: Center(
                          child: Text(
                            'Verify & Proceed',
                            style: AppTypography.buttonLarge,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 48),

                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return SizedBox(
      width: 56,
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.rotate(
            angle: 0.785398,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                border: Border.all(
                  color: AppColors.glassBorder,
                  width: 2,
                  strokeAlign: BorderSide.strokeAlignCenter,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Center(
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.glassBorder,
              ),
            ),
          ),
          Positioned(
            bottom: 4,
            left: 4,
            child: Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.glassBorder,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // OtpInputField handles rendering/styling
}

