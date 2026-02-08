import 'package:flutter/material.dart';
import '../../widgets/navigation/bottom_nav_bar.dart';
import 'home_screen.dart';
import 'gallery_screen.dart';
import 'monitor_screen.dart';
import 'todo_screen.dart';
import 'history_screen.dart';
import 'profile_screen.dart';

/// Employee/Team Lead Shell
/// Main navigation wrapper with bottom nav bar
class EmployeeShell extends StatefulWidget {
  final bool isTeamLead;

  const EmployeeShell({super.key, this.isTeamLead = false});

  @override
  State<EmployeeShell> createState() => _EmployeeShellState();
}

class _EmployeeShellState extends State<EmployeeShell> {
  int _currentIndex = 0;

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
    // Build screens with proper parameters
    final screens = widget.isTeamLead
        ? [
            HomeScreen(isTeamLead: true, onAvatarTap: _openProfile),
            const GalleryScreen(),
            const MonitorScreen(showFilter: true, isAdmin: false),
            const HistoryScreen(),
          ]
        : [
            HomeScreen(isTeamLead: false, onAvatarTap: _openProfile),
            const GalleryScreen(),
            TodoScreen(isTeamLead: false),
            const HistoryScreen(),
          ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true, // Content extends behind nav bar
      body: IndexedStack(index: _currentIndex, children: screens),
      bottomNavigationBar: BottomNavBar(
        currentIndex: _currentIndex,
        onTap: _onTabTap,
        items: widget.isTeamLead
            ? BottomNavBar.teamLeadItems
            : BottomNavBar.employeeItems,
      ),
    );
  }
}

