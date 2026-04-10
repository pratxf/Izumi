import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/session_provider.dart';
import '../../tracking/session_task_guard.dart';
import '../../widgets/navigation/bottom_nav_bar.dart';

/// Admin Shell
/// Main navigation wrapper with 5-tab bottom nav using GoRouter StatefulShellRoute
class AdminShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const AdminShell({super.key, required this.navigationShell});

  void _onTabTap(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBackPress(context);
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        body: navigationShell,
        bottomNavigationBar: BottomNavBar(
          currentIndex: navigationShell.currentIndex,
          onTap: _onTabTap,
          items: BottomNavBar.adminItems,
        ),
      ),
    );
  }

  void _handleBackPress(BuildContext context) {
    final sessionProvider = context.read<SessionProvider>();
    final hasActiveSession = sessionProvider.activeSession != null;

    if (!hasActiveSession) {
      Navigator.of(context).maybePop();
      return;
    }

    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'Active Session',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'You have an active session. Going back will keep your session running in the background. Exit anyway?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Exit'),
          ),
        ],
      ),
    ).then((confirmed) async {
      if (confirmed == true) {
        await SessionTaskGuard.setIntentionalBackground(true);
        if (context.mounted) {
          SystemNavigator.pop();
        }
      }
    });
  }
}
