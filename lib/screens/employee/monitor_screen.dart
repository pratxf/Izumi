import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';
import '../../widgets/glass/gradient_background.dart';

/// Monitor Screen - Team Lead task monitoring view
/// Standard Dark Glass Design
class MonitorScreen extends StatefulWidget {
  const MonitorScreen({super.key});

  @override
  State<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends State<MonitorScreen> {
  String _selectedFilter = 'monitor';

  final List<Map<String, dynamic>> _assignees = [
    {
      'name': 'Rajesh Kumar',
      'status': 'Done',
      'time': '10:42 AM',
      'avatar': 'https://i.pravatar.cc/150?img=11',
      'isDone': true,
    },
    {
      'name': 'Priya Sharma',
      'status': 'Done',
      'time': '11:15 AM',
      'avatar': 'https://i.pravatar.cc/150?img=5',
      'isDone': true,
    },
    {
      'name': 'Amit Patel',
      'status': 'Done',
      'time': '12:30 PM',
      'avatar': 'https://i.pravatar.cc/150?img=12',
      'isDone': true,
    },
    {
      'name': 'Sunita Rao',
      'status': 'Pending',
      'time': null,
      'avatar': 'https://i.pravatar.cc/150?img=9',
      'isDone': false,
    },
    {
      'name': 'Rakesh Gupta',
      'status': 'Pending',
      'time': null,
      'avatar': 'https://i.pravatar.cc/150?img=8',
      'isDone': false,
    },
  ];

  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      isDark: true,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              Column(
                children: [
                  // Header
                  _buildHeader(),

                  // Filter Tabs
                  _buildFilterTabs(),
                  const SizedBox(height: 24),

                  // Content
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 100),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Text(
                              'My Group Tasks',
                              style: AppTypography.h3,
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Main Task Card
                          _buildTaskCard(),
                          const SizedBox(height: 24),

                          // New Region Assignment Card
                          _buildNewAssignmentCard(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              // Bottom Navigation
              Positioned(
                bottom: 24,
                left: 24,
                right: 24,
                child: _buildFloatingNavBar(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Tasks',
            style: AppTypography.displayLarge.copyWith(fontSize: 32),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
            decoration: BoxDecoration(
              color: AppColors.glassSlateSoft,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: AppColors.glassSlateBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.add, color: AppColors.primary, size: 20),
                const SizedBox(width: 4),
                Text(
                  'Create',
                  style: AppTypography.buttonMedium.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterTabs() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          _buildFilterPill('All', 'all'),
          const SizedBox(width: 12),
          _buildFilterPill('Task', 'task'),
          const SizedBox(width: 12),
          _buildFilterPill('Monitor', 'monitor'),
        ],
      ),
    );
  }

  Widget _buildFilterPill(String label, String value) {
    final isSelected = _selectedFilter == value;
    return GestureDetector(
      onTap: () => setState(() => _selectedFilter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.glassSlateSoft,
          borderRadius: BorderRadius.circular(20),
          border: isSelected
              ? null
              : Border.all(color: AppColors.glassSlateBorder),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: AppTypography.bodySmall.copyWith(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            color: isSelected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildTaskCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: AppColors.glassSlateSoft,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.glassSlateBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          // Map Image Header
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: SizedBox(
              height: 192,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    'https://lh3.googleusercontent.com/aida-public/AB6AXuAbg-MMgaGbKRQwM82KB0Uwq3QJBENjWPVBxBnrGUgEC9H8ZG9rT3MOMLNcaihnp-qGfTyXZhNc0h1duikkQ-8Wi5cTrRxfS0m5QR1FaaSqWxZ1lwUfEgTPZNAX9soE1WXVgX891oQ-vo6PYirMzy4LZ5LCbyjR90VIIQ6f1cCkoycNkym5oXmUaRMTuX3BowkIsxP16jm3eaF9rScJ_56dcZj0zqktSNuGLMPAER4tvJYnZk27RFg5p7Q7Ila7kYhTHn8mnrmrfNsp',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        Container(color: AppColors.background),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.8),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 16,
                    left: 24,
                    right: 24,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Visit Region A', style: AppTypography.h2),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(
                                  Icons.group,
                                  color: Colors.white70,
                                  size: 16,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Assigned to: 5 employees',
                                  style: AppTypography.caption,
                                ),
                              ],
                            ),
                          ],
                        ),
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.glassSlateSoft,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.glassSlateBorder,
                            ),
                          ),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: const Icon(
                              Icons.more_horiz,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Progress Section
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.check_circle,
                          color: AppColors.success,
                          size: 20,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Completed: 3/5',
                          style: AppTypography.bodySmall.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const Icon(
                          Icons.hourglass_top,
                          color: AppColors.primary,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Pending: 2',
                          style: AppTypography.caption.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: LinearProgressIndicator(
                    minHeight: 10,
                    value: 0.6,
                    backgroundColor: Colors.white.withOpacity(0.1),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: AppColors.glassSlateBorder),

          // Assignees List
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Column(
              children: _assignees
                  .map((assignee) => _buildAssigneeRow(assignee))
                  .toList(),
            ),
          ),

          // View Full Report Button
          GestureDetector(
            onTap: () {}, // Add functionality
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(24),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'View Full Report',
                    style: AppTypography.buttonMedium.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.arrow_forward,
                    size: 18,
                    color: AppColors.primary,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssigneeRow(Map<String, dynamic> assignee) {
    final bool isDone = assignee['isDone'];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Stack(
                children: [
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isDone ? AppColors.success : AppColors.primary,
                        width: 2,
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 20,
                      backgroundImage: NetworkImage(assignee['avatar']),
                    ),
                  ),
                  if (!isDone)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: AppColors.background,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.hourglass_top,
                          color: AppColors.primary,
                          size: 14,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    assignee['name'],
                    style: AppTypography.bodySmall.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    isDone ? 'Done' : 'Pending',
                    style: AppTypography.caption.copyWith(
                      color: isDone ? AppColors.success : AppColors.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (isDone)
            Text(
              assignee['time'],
              style: AppTypography.caption.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNewAssignmentCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      height: 96,
      decoration: BoxDecoration(
        color: AppColors.glassSlateSoft,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.glassSlateBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_circle, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Text(
              'New Region Assignment',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingNavBar() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.glassSlateStrong,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: AppColors.glassSlateBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildNavItem(Icons.home_outlined, false),
              _buildNavItem(Icons.task_alt, true),
              _buildNavItem(Icons.chat_bubble_outline, false),
              _buildNavItem(Icons.person_outline, false),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, bool isActive) {
    if (isActive) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.primary,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.4),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 24),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Icon(icon, color: AppColors.textSecondary, size: 24),
    );
  }
}
