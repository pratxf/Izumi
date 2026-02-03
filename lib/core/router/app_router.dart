import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/screens/splash_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/otp_screen.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/camera/screens/camera_screen.dart';
import '../../features/camera/screens/preview_screen.dart';
import '../../features/history/screens/history_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/history/screens/day_detail_screen.dart';

// Placeholder imports for now
// import '../../features/camera/screens/camera_screen.dart';
// import '../../features/history/screens/history_screen.dart';
// import '../../features/profile/screens/profile_screen.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

final GoRouter appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (context, state) => const SplashScreen()),
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
    GoRoute(path: '/otp', builder: (context, state) => const OtpScreen()),
    GoRoute(path: '/camera', builder: (context, state) => const CameraScreen()),
    GoRoute(
      path: '/camera/preview',
      builder: (context, state) => const PreviewScreen(),
    ),
    GoRoute(
      path: '/history',
      builder: (context, state) => const HistoryScreen(),
    ),
    GoRoute(
      path: '/profile',
      builder: (context, state) => const ProfileScreen(),
    ),
    GoRoute(
      path: '/history/detail',
      builder: (context, state) => const DayDetailScreen(),
    ),
    // Additional routes can be added here as we implement screens
  ],
);
