import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/navigation/bottom_nav_bar.dart';

/// Employee/Team Lead Shell
/// Main navigation wrapper with bottom nav bar using GoRouter StatefulShellRoute
class EmployeeShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const EmployeeShell({super.key, required this.navigationShell});

  void _onTabTap(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTeamLead = context.watch<AuthProvider>().isTeamLead;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      body: navigationShell,
      bottomNavigationBar: BottomNavBar(
        currentIndex: navigationShell.currentIndex,
        onTap: _onTabTap,
        items: isTeamLead
            ? BottomNavBar.teamLeadItems
            : BottomNavBar.employeeItems,
      ),
    );
  }
}
