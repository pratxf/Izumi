import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class DayDetailScreen extends StatelessWidget {
  const DayDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('Session Details')),
      body: const Center(child: Text("Day Detail Placeholder")),
    );
  }
}
