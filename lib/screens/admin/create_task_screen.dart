import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';
import '../../widgets/glass/gradient_background.dart';

/// Create Task Screen - Standard Dark Glass Design
/// Admin screen for creating and assigning tasks
class CreateTaskScreen extends StatefulWidget {
  const CreateTaskScreen({super.key});

  @override
  State<CreateTaskScreen> createState() => _CreateTaskScreenState();
}

class _CreateTaskScreenState extends State<CreateTaskScreen> {
  final _taskTitleController = TextEditingController(
    text: 'Regional survey Q1 2026',
  );
  final _descriptionController = TextEditingController();

  String _assignType = 'team_lead'; // 'individual', 'team_lead', 'group'
  String _priority = 'high'; // 'high', 'medium', 'low'
  bool _sendNotification = true;

  @override
  void dispose() {
    _taskTitleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _createTask() {
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Task created successfully'),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      isDark: true,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              // Header
              _buildHeader(),

              // Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
                  child: Column(
                    children: [
                      // Task Title
                      _buildInputLabel('Task Title'),
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.glassSlateSoft,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: AppColors.glassSlateBorder),
                        ),
                        child: TextField(
                          controller: _taskTitleController,
                          style: AppTypography.bodyMedium.copyWith(
                            color: Colors.white,
                          ),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 16,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Description
                      _buildInputLabel('Description'),
                      Container(
                        height: 120,
                        decoration: BoxDecoration(
                          color: AppColors.glassSlateSoft,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: AppColors.glassSlateBorder),
                        ),
                        child: TextField(
                          controller: _descriptionController,
                          maxLines: null,
                          style: AppTypography.bodyMedium.copyWith(
                            color: Colors.white,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Enter task details...',
                            hintStyle: AppTypography.bodyMedium.copyWith(
                              color: Colors.white.withOpacity(0.5),
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.all(20),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Assign To
                      _buildInputLabel('Assign To'),
                      Column(
                        children: [
                          _buildRadioCard(
                            title: 'Individual Employee',
                            icon: Icons.person_outline,
                            value: 'individual',
                          ),
                          const SizedBox(height: 12),
                          _buildRadioCard(
                            title: 'Team Lead',
                            icon: Icons.supervisor_account_outlined,
                            value: 'team_lead',
                            isPrimary: true,
                            showVerified: true,
                          ),
                          const SizedBox(height: 12),
                          _buildRadioCard(
                            title: 'Entire Group',
                            icon: Icons.groups_outlined,
                            value: 'group',
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Select Team Lead Dropdown
                      _buildInputLabel('Select Team Lead'),
                      _buildTeamLeadSelector(),
                      const SizedBox(height: 24),

                      // Due Date & Priority Grid
                      _buildInputLabel('Due Date'),
                      _buildDueDateCard(),
                      const SizedBox(height: 24),

                      _buildInputLabel('Priority'),
                      _buildPrioritySelector(),
                      const SizedBox(height: 24),

                      // Notification Toggle
                      _buildNotificationToggle(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // Floating Bottom Button
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        floatingActionButton: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            width: double.infinity,
            height: 64,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(32),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: _createTask,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(32),
                ),
                elevation: 0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add_task, color: Colors.white, size: 24),
                  const SizedBox(width: 12),
                  Text('Create Task', style: AppTypography.buttonLarge),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.glassSlateSoft,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.glassSlateBorder),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new,
                size: 20,
                color: Colors.white,
              ),
            ),
          ),
          Text('Create Task', style: AppTypography.h3),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildInputLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          label.toUpperCase(),
          style: AppTypography.caption.copyWith(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildRadioCard({
    required String title,
    required IconData icon,
    required String value,
    bool isPrimary = false,
    bool showVerified = false,
  }) {
    final isSelected = _assignType == value;

    return GestureDetector(
      onTap: () => setState(() => _assignType = value),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withOpacity(0.2)
              : AppColors.glassSlateSoft,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.glassSlateBorder,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            // Radio Circle
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? AppColors.primary : Colors.transparent,
                border: Border.all(
                  color: isSelected
                      ? AppColors.primary
                      : Colors.white.withOpacity(0.5),
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 16),
            Icon(
              icon,
              color: isSelected ? Colors.white : AppColors.textSecondary,
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: AppTypography.bodyMedium.copyWith(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                color: isSelected ? Colors.white : AppColors.textSecondary,
              ),
            ),
            if (showVerified) ...[
              const Spacer(),
              const Icon(Icons.verified, color: AppColors.primary, size: 20),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTeamLeadSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.glassSlateSoft,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.glassSlateBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                'RK',
                style: GoogleFonts.inter(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Rajesh Kumar',
            style: AppTypography.bodyMedium.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const Spacer(),
          Icon(Icons.expand_more, color: AppColors.textSecondary),
        ],
      ),
    );
  }

  Widget _buildDueDateCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.glassSlateSoft,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.glassSlateBorder),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '15 Feb 2026',
            style: AppTypography.bodyMedium.copyWith(
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const Icon(Icons.calendar_today, color: AppColors.primary, size: 20),
        ],
      ),
    );
  }

  Widget _buildPrioritySelector() {
    return Row(
      children: [
        Expanded(child: _buildPriorityPill('High', 'high', Icons.flag)),
        const SizedBox(width: 8),
        Expanded(child: _buildPriorityPill('Medium', 'medium', null)),
        const SizedBox(width: 8),
        Expanded(child: _buildPriorityPill('Low', 'low', null)),
      ],
    );
  }

  Widget _buildPriorityPill(String label, String value, IconData? icon) {
    final isSelected = _priority == value;
    return GestureDetector(
      onTap: () => setState(() => _priority = value),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.glassSlateSoft,
          borderRadius: BorderRadius.circular(24),
          border: isSelected
              ? null
              : Border.all(color: AppColors.glassSlateBorder),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 18,
                color: isSelected ? Colors.white : AppColors.textSecondary,
              ),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: AppTypography.bodySmall.copyWith(
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationToggle() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.glassSlateSoft,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.glassSlateBorder),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.notifications_active,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Send Notification',
                style: AppTypography.bodySmall.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          Switch(
            value: _sendNotification,
            onChanged: (v) => setState(() => _sendNotification = v),
            activeColor: AppColors.primary,
            activeTrackColor: AppColors.primary.withOpacity(0.2),
          ),
        ],
      ),
    );
  }
}
