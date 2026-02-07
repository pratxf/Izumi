import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import '../../screens/auth/welcome_screen.dart';
import '../../screens/auth/enterprise_login_screen.dart';
import '../../screens/auth/otp_screen.dart';
import '../../screens/employee/home_screen.dart';
import '../../screens/employee/camera_screen.dart';
import '../../screens/employee/preview_screen.dart';
import '../../screens/employee/history_screen.dart';
import '../../screens/employee/profile_screen.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

final GoRouter appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (context, state) => const WelcomeScreen()),
    GoRoute(
      path: '/login',
      builder: (context, state) => const EnterpriseLoginScreen(),
    ),
    GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
    GoRoute(
      path: '/otp',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return OtpScreen(
          phoneNumber: extra['phoneNumber'] as String? ?? '',
          role: extra['role'] as String? ?? 'Employee',
        );
      },
    ),
    GoRoute(path: '/camera', builder: (context, state) => const CameraScreen()),
    GoRoute(
      path: '/camera/preview',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return PreviewScreen(
          location: extra['location'] as String? ?? 'Unknown Location',
          timestamp: extra['timestamp'] as DateTime? ?? DateTime.now(),
        );
      },
    ),
    GoRoute(
      path: '/history',
      builder: (context, state) => const HistoryScreen(),
    ),
    GoRoute(
      path: '/profile',
      builder: (context, state) => const ProfileScreen(),
    ),
  ],
);
