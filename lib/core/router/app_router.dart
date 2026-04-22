import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../screens/auth/welcome_screen.dart';
import '../../screens/auth/enterprise_login_screen.dart';
import '../../screens/auth/otp_screen.dart';
import '../../screens/employee/employee_shell.dart';
import '../../screens/employee/home_screen.dart';
import '../../screens/employee/gallery_screen.dart';
import '../../screens/employee/todo_screen.dart';
import '../../screens/employee/history_screen.dart';
import '../../screens/employee/camera_screen.dart';
import '../../screens/employee/preview_screen.dart';
import '../../screens/employee/profile_screen.dart';
import '../../screens/employee/end_of_day_screen.dart';
import '../../screens/employee/image_detail_screen.dart';
import '../../screens/employee/team_lead_employee_detail_screen.dart';
import '../../screens/admin/admin_shell.dart';
import '../../screens/admin/dashboard_screen.dart';
import '../../screens/admin/images_screen.dart';
import '../../screens/employee/monitor_screen.dart';
import '../../screens/admin/analytics_screen.dart';
import '../../screens/admin/management_screen.dart';
import '../../screens/admin/create_task_screen.dart';
import '../../screens/admin/create_group_screen.dart';
import '../../screens/admin/edit_group_screen.dart';
import '../../screens/admin/employee_detail_screen.dart';
import '../../screens/admin/export_data_screen.dart';
import '../../screens/admin/add_user_screen.dart';
import '../../screens/employee/edit_profile_screen.dart';
import '../../screens/notifications/notifications_screen.dart';
import '../../screens/chat/chat_groups_screen.dart';
import '../../screens/chat/chat_conversation_screen.dart';
import '../../screens/chat/chat_camera_screen.dart';
import '../../screens/chat/create_chat_group_screen.dart';
import '../../screens/chat/edit_chat_group_screen.dart';
import '../../models/chat_group_model.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'root');

GoRouter createAppRouter(AuthProvider authProvider) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    refreshListenable: authProvider,
    redirect: (context, state) {
      final isAuthenticated = authProvider.isAuthenticated;
      final isLoading = authProvider.status == AuthStatus.initial ||
          authProvider.status == AuthStatus.loading;
      final currentPath = state.matchedLocation;
      final hasPendingOtp = authProvider.hasPendingOtp;

      final authPaths = ['/', '/otp', '/enterprise-login'];
      final isOnAuthPage = authPaths.contains(currentPath);

      debugPrint('Router redirect: path=$currentPath, status=${authProvider.status}, isAuth=$isAuthenticated, isOnAuthPage=$isOnAuthPage, hasPendingOtp=$hasPendingOtp');

      if (isLoading) return null;

      if (!isAuthenticated) {
        if (hasPendingOtp && currentPath != '/otp') return '/otp';
        return isOnAuthPage ? null : '/';
      }

      if (isAuthenticated && isOnAuthPage) {
        final role = authProvider.activeRole;
        if (role == 'admin') return '/admin/dashboard';
        if (role == 'employee' || role == 'team_lead') return '/employee/home';
        return '/employee/home'; // fallback for unknown role
      }

      // Prevent non-admins from accessing admin routes
      // Team leads are allowed to access /admin/create-task
      if (isAuthenticated && currentPath.startsWith('/admin') && authProvider.activeRole != 'admin') {
        if (authProvider.activeRole == 'team_lead' && currentPath == '/admin/create-task') {
          return null; // Allow team leads to create tasks
        }
        return '/employee/home';
      }

      return null;
    },
    routes: [
      // ── Auth Routes ──
      GoRoute(
        path: '/',
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: '/otp',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          final provider = context.read<AuthProvider>();
          return OtpScreen(
            phoneNumber: extra['phoneNumber'] as String? ??
                provider.pendingOtpPhoneNumber ??
                '',
            role: extra['role'] as String? ??
                provider.pendingOtpRole ??
                'employee',
            name: extra['name'] as String? ??
                provider.pendingOtpName ??
                '',
          );
        },
      ),
      GoRoute(
        path: '/enterprise-login',
        builder: (context, state) => const EnterpriseLoginScreen(),
      ),

      // ── Employee Shell ──
      StatefulShellRoute.indexedStack(
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state, navigationShell) {
          return EmployeeShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/employee/home',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/employee/gallery',
                builder: (context, state) => const GalleryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/employee/tasks',
                builder: (context, state) {
                  final isTeamLead = context.read<AuthProvider>().isTeamLead;
                  return TodoScreen(isTeamLead: isTeamLead);
                },
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/employee/history',
                builder: (context, state) => const HistoryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/employee/chat',
                builder: (context, state) => const ChatGroupsScreen(),
              ),
            ],
          ),
        ],
      ),

      // ── Employee Full-Screen Routes ──
      GoRoute(
        path: '/employee/camera',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const CameraScreen(),
      ),
      GoRoute(
        path: '/employee/camera/preview',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return PreviewScreen(
            location: extra['location'] as String? ?? 'Unknown Location',
            timestamp: extra['timestamp'] as DateTime? ?? DateTime.now(),
            imagePath: extra['imagePath'] as String?,
          );
        },
      ),
      GoRoute(
        path: '/employee/profile',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: '/employee/edit-profile',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const EditProfileScreen(),
      ),
      GoRoute(
        path: '/employee/end-of-day',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return EndOfDayScreen(
            sessionDuration:
                extra['sessionDuration'] as Duration? ?? Duration.zero,
            locations: extra['locations'] as List<String>? ?? const [],
            photosCount: extra['photosCount'] as int? ?? 0,
            tasksCompleted: extra['tasksCompleted'] as int? ?? 0,
          );
        },
      ),
      GoRoute(
        path: '/employee/image-detail',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return ImageDetailScreen(
            imageUrl: extra['imageUrl'] as String? ?? '',
            thumbnailUrl: extra['thumbnailUrl'] as String?,
            location: extra['location'] as String? ?? '',
            capturedBy: extra['capturedBy'] as String? ?? '',
            employeeId: extra['employeeId'] as String? ?? '',
            timestamp: extra['timestamp'] as DateTime? ?? DateTime.now(),
            category: extra['category'] as String?,
            name: extra['name'] as String?,
            phone: extra['phone'] as String?,
            customerType: extra['customerType'] as String?,
            notes: extra['notes'] as String?,
            hasFollowUp: extra['hasFollowUp'] as bool? ?? false,
            latitude: extra['latitude'] as double?,
            longitude: extra['longitude'] as double?,
            isVerified: extra['isVerified'] as bool? ?? false,
            heroTag: extra['heroTag'] as String?,
          );
        },
      ),

      GoRoute(
        path: '/employee/notifications',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const NotificationsScreen(),
      ),
      GoRoute(
        path: '/employee/monitor',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const MonitorScreen(showFilter: true),
      ),
      GoRoute(
        path: '/employee/team-lead-detail',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return TeamLeadEmployeeDetailScreen(
            name: extra['name'] as String? ?? '',
            initials: extra['initials'] as String? ?? '',
            isOnline: extra['isOnline'] as bool? ?? true,
            employeeId: extra['employeeId'] as String?,
          );
        },
      ),

      // ── Admin Shell ──
      StatefulShellRoute.indexedStack(
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state, navigationShell) {
          return AdminShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/admin/dashboard',
                builder: (context, state) => const DashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/admin/tasks',
                builder: (context, state) => const MonitorScreen(isAdmin: true),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/admin/analytics',
                builder: (context, state) => const AnalyticsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/admin/management',
                builder: (context, state) => const ManagementScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/admin/chat',
                builder: (context, state) => const ChatGroupsScreen(),
              ),
            ],
          ),
        ],
      ),

      // ── Chat Full-Screen Routes ──
      GoRoute(
        path: '/chat/conversation',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return ChatConversationScreen(
            groupId: extra['groupId'] as String? ?? '',
            groupName: extra['groupName'] as String? ?? 'Chat',
          );
        },
      ),

      GoRoute(
        path: '/chat/camera',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return ChatCameraScreen(
            groupId: extra['groupId'] as String? ?? '',
            groupName: extra['groupName'] as String? ?? 'Chat',
          );
        },
      ),

      // ── Admin Full-Screen Routes ──
      GoRoute(
        path: '/admin/create-task',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return CreateTaskScreen(
            initialAssigneeName: extra['initialAssigneeName'] as String?,
            isTeamLead: extra['isTeamLead'] as bool? ?? false,
          );
        },
      ),
      GoRoute(
        path: '/admin/create-group',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const CreateGroupScreen(),
      ),
      GoRoute(
        path: '/admin/create-chat-group',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const CreateChatGroupScreen(),
      ),
      GoRoute(
        path: '/admin/edit-chat-group',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final group = state.extra as ChatGroupModel;
          return EditChatGroupScreen(group: group);
        },
      ),
      GoRoute(
        path: '/admin/edit-group',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return EditGroupScreen(
            groupId: extra['groupId'] as String? ?? '',
            groupName: extra['groupName'] as String? ?? '',
            teamLeadIds: extra['teamLeadIds'] != null
                ? List<String>.from(extra['teamLeadIds'] as List)
                : const [],
            members: extra['members'] != null
                ? List<Map<String, dynamic>>.from(
                    (extra['members'] as List).map((m) => Map<String, dynamic>.from(m as Map)))
                : const [],
          );
        },
      ),
      GoRoute(
        path: '/admin/employee/:id',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return EmployeeDetailScreen(
            name: extra['name'] as String? ?? '',
            isActive: extra['isActive'] as bool? ?? false,
          );
        },
      ),
      GoRoute(
        path: '/admin/add-user',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const AddUserScreen(),
      ),
      GoRoute(
        path: '/admin/export',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const ExportDataScreen(),
      ),
      GoRoute(
        path: '/admin/edit-profile',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const EditProfileScreen(),
      ),
      GoRoute(
        path: '/admin/profile',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const ProfileScreen(isAdmin: true),
      ),
      GoRoute(
        path: '/admin/employee-images',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return ImagesScreen(
            initialEmployeeId: extra['employeeId'] as String?,
          );
        },
      ),
    ],
  );
}
