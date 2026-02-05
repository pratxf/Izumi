import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

class CameraScreen extends StatelessWidget {
  const CameraScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Mock Viewfinder
          Center(
            child: Container(
              width: double.infinity,
              height: double.infinity,
              color: Colors.grey.shade900,
              child: Center(
                child: Icon(Icons.camera_alt, size: 100, color: Colors.white24),
              ),
            ),
          ),

          // Controls
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(32),
              color: Colors.black54,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 32,
                    ),
                    onPressed: () => context.pop(),
                  ),
                  GestureDetector(
                    onTap: () {
                      // Capture mock and go to preview
                      context.push('/camera/preview');
                    },
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.grey, width: 4),
                      ),
                    ),
                  ),
                  const SizedBox(width: 48), // Spacer for balance
                ],
              ),
            ),
          ),

          // Top Bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Icon(Icons.flash_off, color: Colors.white),
                    Text(
                      'Visit Proof',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 18,
                      ),
                    ),
                    const Icon(Icons.flip_camera_ios, color: Colors.white),
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
