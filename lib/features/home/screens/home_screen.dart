import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart'; // Added for context.go
import '../../../core/theme/app_theme.dart';
import '../widgets/session_timer.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isWorking = false;
  Timer? _timer;
  Duration _duration = Duration.zero;

  void _toggleSession() {
    setState(() {
      _isWorking = !_isWorking;
      if (_isWorking) {
        _startTimer();
      } else {
        _stopTimer();
        // Navigate to session summary (mock)
        // context.push('/session-summary');
      }
    });
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _duration += const Duration(seconds: 1);
      });
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _duration = Duration.zero;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _isWorking ? AppTheme.primary : AppTheme.background,
      appBar: AppBar(
        title: Text(
          _isWorking ? 'Session Active' : 'Dashboard',
          style: GoogleFonts.outfit(
            color: _isWorking ? Colors.white : AppTheme.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.history,
              color: _isWorking ? Colors.white : AppTheme.textPrimary,
            ),
            onPressed: () => context.push('/history'),
          ),
          IconButton(
            icon: Icon(
              Icons.person,
              color: _isWorking ? Colors.white : AppTheme.textPrimary,
            ),
            onPressed: () => context.push('/profile'),
          ),
        ],
        iconTheme: IconThemeData(
          color: _isWorking ? Colors.white : AppTheme.textPrimary,
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_isWorking) ...[
                // Active State
                const Spacer(),
                Center(child: SessionTimer(duration: _duration)),
                const SizedBox(height: 20),
                _buildStatRow("Distance", "1.2 km", Colors.white70),
                const SizedBox(height: 10),
                _buildStatRow("Nearest", "Central Park", Colors.white70),
                const Spacer(),
                ElevatedButton(
                  onPressed: _toggleSession,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                  ),
                  child: const Text('STOP WORK'),
                ),
              ] else ...[
                // Idle State
                const Spacer(),
                _buildSummaryCard("Last Session", "4h 20m"),
                const SizedBox(height: 16),
                _buildSummaryCard("Today's Distance", "12.5 km"),
                const Spacer(),
                ElevatedButton(
                  onPressed: _toggleSession,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary, // Premium Blue
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    textStyle: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  child: const Text('START WORK'),
                ),
                const SizedBox(height: 20),
                OutlinedButton(
                  onPressed: () {
                    context.push('/camera');
                  },
                  child: const Text("Open Camera (Mock)"),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: GoogleFonts.outfit(color: color, fontSize: 14)),
        Text(
          value,
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard(String title, String value) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: AppTheme.lightTheme.textTheme.bodyLarge),
          Text(value, style: AppTheme.lightTheme.textTheme.titleLarge),
        ],
      ),
    );
  }
}
