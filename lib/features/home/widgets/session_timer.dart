import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class SessionTimer extends StatelessWidget {
  final Duration duration;

  const SessionTimer({super.key, required this.duration});

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(d.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(d.inSeconds.remainder(60));
    return "${twoDigits(d.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _formatDuration(duration),
      style: GoogleFonts.outfit(
        fontSize: 48,
        fontWeight: FontWeight.bold,
        color: Colors.white,
        letterSpacing: 2,
      ),
    );
  }
}
