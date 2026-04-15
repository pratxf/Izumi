import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'core/constants/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'firebase_options.dart';
import 'widgets/glass/gradient_background.dart';
import 'providers/auth_provider.dart';
import 'providers/session_provider.dart';
import 'providers/photo_provider.dart';
import 'providers/task_provider.dart';
import 'providers/group_provider.dart';
import 'providers/user_provider.dart';
import 'providers/dashboard_provider.dart';
import 'providers/analytics_provider.dart';
import 'providers/team_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/enterprise_provider.dart';
import 'services/connectivity_monitor.dart';
import 'services/diagnostic_logger.dart';
import 'tracking/tracking_foreground_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Clear stale image cache from previous sessions
  PaintingBinding.instance.imageCache.clear();
  PaintingBinding.instance.imageCache.clearLiveImages();

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Note: Firestore has `persistenceEnabled: true` by default on Android and
  // iOS, so offline-first session writes + the OfflineQueueManager work out
  // of the box. We deliberately do NOT override [FirebaseFirestore.instance.settings]
  // here — setting `cacheSizeBytes: UNLIMITED` on top of an existing default
  // (100MB LRU) cache stalled the internal mutation queue on some Android
  // builds, causing queued chat writes to hang indefinitely. Default is fine.

  TrackingForegroundService.initialize();
  unawaited(ConnectivityMonitor.instance.start());
  unawaited(DiagnosticLogger.I.init());

  // Activate App Check in background — provider registration is instant,
  // actual attestation happens lazily on first Firebase call.
  unawaited(
    FirebaseAppCheck.instance
        .activate(
      androidProvider: AndroidProvider.playIntegrity,
      appleProvider: AppleProvider.deviceCheck,
    )
        .catchError((e) {
      debugPrint('[main] AppCheck activation failed: $e');
    }),
  );

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Color(0xFFFFFFFF),
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  // Set preferred orientations
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const IzumiApp());
}

/// Izumi Field Workforce Intelligence Platform
/// Main application entry point
class IzumiApp extends StatelessWidget {
  const IzumiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => SessionProvider()),
        ChangeNotifierProvider(create: (_) => PhotoProvider()),
        ChangeNotifierProvider(create: (_) => TaskProvider()),
        ChangeNotifierProvider(create: (_) => GroupProvider()),
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => DashboardProvider()),
        ChangeNotifierProvider(create: (_) => AnalyticsProvider()),
        ChangeNotifierProvider(create: (_) => TeamProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(create: (_) => EnterpriseProvider()),
      ],
      child: const _IzumiRouter(),
    );
  }
}

/// Stateful router wrapper — creates GoRouter once and lets
/// refreshListenable handle auth-state-driven redirects.
class _IzumiRouter extends StatefulWidget {
  const _IzumiRouter();

  @override
  State<_IzumiRouter> createState() => _IzumiRouterState();
}

class _IzumiRouterState extends State<_IzumiRouter> {
  late final GoRouter _router;
  final List<StreamSubscription> _notificationSubs = [];

  @override
  void initState() {
    super.initState();
    final authProvider = context.read<AuthProvider>();
    _router = createAppRouter(authProvider);
    _wireEnterpriseIntoConsumers();
    _setupNotificationListeners(authProvider);
    _setupEnterpriseBootstrap(authProvider);
  }

  /// Attach the [EnterpriseProvider] to every provider that needs the
  /// employee list. Must happen before any bootstrap attempt so that when
  /// consumers read `.employees`, they see the populated list.
  void _wireEnterpriseIntoConsumers() {
    final enterprise = context.read<EnterpriseProvider>();
    context.read<DashboardProvider>().attachEnterprise(enterprise);
    context.read<AnalyticsProvider>().attachEnterprise(enterprise);
    context.read<TeamProvider>().attachEnterprise(enterprise);
    context.read<UserProvider>().attachEnterprise(enterprise);
  }

  /// Bootstrap order on auth success:
  ///   1. EnterpriseProvider.load() — one-shot fetch of enterprise employees
  ///      (splash gate waits on its isReady flag)
  ///   2. DashboardProvider.initWithEnterpriseId() — starts RTDB streams,
  ///      reads employees from EnterpriseProvider
  ///
  /// On logout, clears EnterpriseProvider so the next login re-fetches.
  void _setupEnterpriseBootstrap(AuthProvider authProvider) {
    String? lastBootstrappedEnterpriseId;

    Future<void> tryBootstrap() async {
      if (!mounted) return;

      final enterprise = context.read<EnterpriseProvider>();

      // Handle logout / unauthenticated state — clear enterprise state so
      // the splash gate re-fires on next login.
      if (!authProvider.isAuthenticated) {
        if (enterprise.isReady) {
          enterprise.clear();
          lastBootstrappedEnterpriseId = null;
        }
        return;
      }

      final enterpriseId = authProvider.enterpriseId;
      if (enterpriseId == null) return;

      // Avoid redundant bootstraps when AuthProvider notifies for unrelated
      // reasons (e.g. role switch, FCM token update).
      if (lastBootstrappedEnterpriseId == enterpriseId) return;
      lastBootstrappedEnterpriseId = enterpriseId;

      try {
        // Step 1: Await enterprise load — the splash gate watches isReady
        await enterprise.load(enterpriseId);
      } catch (e) {
        debugPrint('[main] EnterpriseProvider.load failed: $e');
        // load() flips isReady=true even on failure so the app remains usable
      }

      if (!mounted) return;

      // Step 2: Kick off dashboard streams now that employees are available
      final dashboardProvider = context.read<DashboardProvider>();
      dashboardProvider.initWithEnterpriseId(enterpriseId);
    }

    authProvider.addListener(() {
      unawaited(tryBootstrap());
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(tryBootstrap());
    });
  }

  void _setupNotificationListeners(AuthProvider authProvider) {
    final notifService = authProvider.notificationService;

    // Foreground local notification tap
    _notificationSubs.add(
      notifService.onLocalNotificationTap.listen((data) {
        _navigateFromNotificationData(data, authProvider);
      }),
    );

    // Background/terminated FCM notification tap
    _notificationSubs.add(
      notifService.onMessageOpened.listen((message) {
        _navigateFromNotificationData(message.data, authProvider);
      }),
    );

    // Cold-start: app opened from a terminated-state notification
    notifService.getInitialMessage().then((message) {
      if (message != null) {
        // Delay slightly to let router initialize
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            _navigateFromNotificationData(message.data, authProvider);
          }
        });
      }
    });
  }

  void _navigateFromNotificationData(
    Map<String, dynamic> data,
    AuthProvider authProvider,
  ) {
    final action = data['action'] as String?;
    if (action == null) return;

    final isAdmin = authProvider.isAdmin;

    switch (action) {
      case 'TASK_ASSIGNED':
      case 'TASK_COMPLETED':
        _router.go(isAdmin ? '/admin/tasks' : '/employee/tasks');
        break;
      case 'SESSION_STARTED':
      case 'SESSION_ENDED':
        _router.go(isAdmin ? '/admin/dashboard' : '/employee/home');
        break;
      case 'CHAT_MESSAGE':
        final groupId = data['groupId'] as String?;
        final groupName = data['groupName'] as String? ?? 'Chat';
        if (groupId != null) {
          _router.push('/chat/conversation', extra: {
            'groupId': groupId,
            'groupName': groupName,
          });
        } else {
          _router.go(isAdmin ? '/admin/chat' : '/employee/chat');
        }
        break;
    }
  }

  @override
  void dispose() {
    for (final sub in _notificationSubs) {
      sub.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authStatus = context.watch<AuthProvider>().status;
    final enterpriseReady = context.watch<EnterpriseProvider>().isReady;

    final authLoading =
        authStatus == AuthStatus.initial || authStatus == AuthStatus.loading;
    // After auth succeeds we also wait for EnterpriseProvider to finish its
    // one-shot employee fetch. This guarantees every downstream provider and
    // screen reads a populated employee list — no more race conditions.
    final waitingForEnterprise =
        authStatus == AuthStatus.authenticated && !enterpriseReady;
    final isInitializing = authLoading || waitingForEnterprise;

    return MaterialApp.router(
      title: 'Izumi',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      routerConfig: _router,
      builder: (context, child) {
        if (child == null) return const SizedBox.shrink();
        // Show branded splash while auth state is being resolved
        if (isInitializing) {
          return GradientBackground(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SvgPicture.asset(
                    'assets/branding/izumi_logo.svg',
                    width: 80,
                    height: 80,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return GradientBackground(child: child);
      },
    );
  }
}
