import 'package:flutter/material.dart';
import '../../widgets/navigation/bottom_nav_bar.dart';
import 'dashboard_screen.dart';
import 'images_screen.dart';
import '../employee/monitor_screen.dart';
import 'analytics_screen.dart';
import 'groups_screen.dart';
import '../employee/profile_screen.dart';

/// Admin Shell
/// Main navigation wrapper with 5-tab bottom nav
class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const DashboardScreen(),
    const ImagesScreen(),
    const MonitorScreen(),
    const AnalyticsScreen(),
    const GroupsScreen(),
  ];

  void _onTabTap(int index) {
    setState(() => _currentIndex = index);
  }

  void _openProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProfileScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true, // Content extends behind nav bar
      body: IndexedStack(
        index: _currentIndex,
        children: _screens.map((screen) {
          if (screen is DashboardScreen) {
            return DashboardScreen(onAvatarTap: _openProfile);
          }
          return screen;
        }).toList(),
      ),
      bottomNavigationBar: BottomNavBar(
        currentIndex: _currentIndex,
        onTap: _onTabTap,
        items: BottomNavBar.adminItems,
      ),
    );
  }
}

