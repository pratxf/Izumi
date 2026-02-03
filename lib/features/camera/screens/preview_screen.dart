import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';

class PreviewScreen extends StatefulWidget {
  const PreviewScreen({super.key});

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  bool _isDistributor = true;
  final _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Confirm Visit'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: Column(
        children: [
          // Photo Preview (Mock)
          Container(
            height: 200,
            width: double.infinity,
            color: Colors.grey.shade300,
            child: const Center(
              child: Icon(Icons.image, size: 64, color: Colors.grey),
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Location Metadata
                    Row(
                      children: [
                        const Icon(Icons.location_on, color: AppTheme.accent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '123 Main St, Central District',
                                style: AppTheme.lightTheme.textTheme.bodyLarge,
                              ),
                              Text(
                                'Lat: 40.7128, Long: -74.0060',
                                style: AppTheme.lightTheme.textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 32),

                    // Toggle
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: const Text('Distributor'),
                            selected: _isDistributor,
                            onSelected: (v) =>
                                setState(() => _isDistributor = true),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ChoiceChip(
                            label: const Text('Customer'),
                            selected: !_isDistributor,
                            onSelected: (v) =>
                                setState(() => _isDistributor = false),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Inputs
                    TextFormField(
                      decoration: const InputDecoration(
                        labelText: 'Contact Name',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      decoration: const InputDecoration(
                        labelText: 'Phone Number',
                        prefixText: '+91 ',
                      ),
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 24),

                    ElevatedButton(
                      onPressed: () {
                        // Submit logic mock
                        // Return to Home
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Proof Verified & Uploaded!'),
                          ),
                        );
                        context.go('/home');
                      },
                      child: const Text('Submit Proof'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
