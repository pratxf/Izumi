import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      body: navigationShell,
      bottomNavigationBar: BottomNavBar(
        currentIndex: navigationShell.currentIndex,
        onTap: _onTabTap,
        items: BottomNavBar.adminItems,
      ),
    );
  }
}
