import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';

class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final TextEditingController _otpController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              Text(
                'Verify OTP',
                style: AppTheme.lightTheme.textTheme.displayLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Enter the 4-digit code sent to your phone',
                style: AppTheme.lightTheme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),

              // OTP Input (Simple Mock)
              TextFormField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 4,
                style: GoogleFonts.outfit(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 16,
                ),
                decoration: const InputDecoration(
                  counterText: "",
                  hintText: "----",
                ),
              ),
              const SizedBox(height: 24),

              // Action Button
              ElevatedButton(
                onPressed: () {
                  // Navigate to Home
                  context.go('/home');
                },
                child: const Text('Verify & Login'),
              ),

              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  // Resend logic mock
                },
                child: Text(
                  'Resend OTP',
                  style: GoogleFonts.outfit(
                    color: AppTheme.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
