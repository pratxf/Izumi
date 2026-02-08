import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';
import '../../widgets/glass/gradient_background.dart';
import '../../widgets/inputs/text_input_field.dart';
import '../../widgets/navigation/app_header.dart';

/// Create Task Screen - Standard Dark Glass Design
/// Admin screen for creating and assigning tasks
class CreateTaskScreen extends StatefulWidget {
  final String? initialAssigneeName;
  final bool isTeamLead;

  const CreateTaskScreen({
    super.key,
    this.initialAssigneeName,
    this.isTeamLead = false,
  });

  @override
  State<CreateTaskScreen> createState() => _CreateTaskScreenState();
}

class _CreateTaskScreenState extends State<CreateTaskScreen> {
  final _taskTitleController = TextEditingController(
    text: 'Regional survey Q1 2026',
  );
  final _descriptionController = TextEditingController();
  final _assignedEmployeeController = TextEditingController();

  String _assignType = 'individual'; // 'individual', 'team_lead', 'group'
  String _priority = 'high'; // 'high', 'medium', 'low'
  bool _sendNotification = true;

  final List<String> _employees = [
    'Rajesh Kumar',
    'Priya Sharma',
    'Amit Patel',
    'David Kim',
  ];

  final List<String> _groups = [
    'North Zone',
    'South Zone',
    'Central District',
  ];

  String _selectedEmployee = 'Rajesh Kumar';
  String _selectedGroup = 'North Zone';

  @override
  void initState() {
    super.initState();
    if (widget.initialAssigneeName != null &&
        widget.initialAssigneeName!.isNotEmpty) {
      _assignType = 'individual';
      _assignedEmployeeController.text = widget.initialAssigneeName!;
      _selectedEmployee = widget.initialAssigneeName!;
    }
  }

  @override
  void dispose() {
    _taskTitleController.dispose();
    _descriptionController.dispose();
    _assignedEmployeeController.dispose();
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
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              // Header
              const AppHeader(
                title: 'Create Task',
                type: AppHeaderType.secondary,
                showAvatar: false,
              ),

              // Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
                  child: Column(
                    children: [
                      // Task Title
                      _buildInputLabel('Task Title'),
                      GlassInputField(
                        controller: _taskTitleController,
                      ),
                      const SizedBox(height: 24),

                      // Description
                      _buildInputLabel('Description'),
                      GlassInputField(
                        controller: _descriptionController,
                        hint: 'Enter task details...',
                        maxLines: 4,
                        contentPadding: const EdgeInsets.all(20),
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
                          if (!widget.isTeamLead) ...[
                            const SizedBox(height: 12),
                            _buildRadioCard(
                              title: 'Team Lead',
                              icon: Icons.supervisor_account_outlined,
                              value: 'team_lead',
                              isPrimary: true,
                              showVerified: true,
                            ),
                            const SizedBox(height: 12),
                          ] else
                            const SizedBox(height: 12),
                          _buildRadioCard(
                            title: 'Entire Group',
                            icon: Icons.groups_outlined,
                            value: 'group',
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Assigned Employee (when individual)
                      if (_assignType == 'individual') ...[
                        _buildInputLabel(
                          widget.isTeamLead
                              ? 'Choose Employee'
                              : 'Assigned Employee',
                        ),
                        widget.isTeamLead
                            ? _buildEmployeeSelector()
                            : GlassInputField(
                                controller: _assignedEmployeeController,
                                enabled: false,
                                prefixIcon: Icons.person_outline,
                              ),
                        const SizedBox(height: 24),
                      ],

                      // Select Team Lead Dropdown
                      if (_assignType == 'team_lead' &&
                          !widget.isTeamLead) ...[
                        _buildInputLabel('Select Team Lead'),
                        _buildTeamLeadSelector(),
                        const SizedBox(height: 24),
                      ],

                      // Group Selector (team lead)
                      if (_assignType == 'group' && widget.isTeamLead) ...[
                        _buildInputLabel('Choose Group'),
                        _buildGroupSelector(),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'All employees in the selected group will be assigned.',
                            style: AppTypography.caption.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],

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
                  const Icon(
                    Icons.add_task,
                    color: AppColors.textPrimary,
                    size: 24,
                  ),
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
              : AppColors.glassPrimary,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.glassBorder,
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
                      : AppColors.glassBorder,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: AppColors.textPrimary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 16),
            Icon(
              icon,
              color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: AppTypography.bodyMedium.copyWith(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
              ),
            ),
            if (isSelected) ...[
              const Spacer(),
              const Icon(Icons.check_circle, color: AppColors.primary, size: 20),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDueDateCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.glassPrimary,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '15 Feb 2026',
            style: AppTypography.bodyMedium.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const Icon(Icons.calendar_today, color: AppColors.primary, size: 20),
        ],
      ),
    );
  }

  Widget _buildTeamLeadSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.glassPrimary,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.glassBorder),
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
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Rajesh Kumar',
            style: AppTypography.bodyMedium.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          Icon(Icons.expand_more, color: AppColors.textSecondary),
        ],
      ),
    );
  }

  Widget _buildEmployeeSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.glassPrimary,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.glassBorder),
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
                _selectedEmployee
                    .split(' ')
                    .map((e) => e[0])
                    .take(2)
                    .join(),
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _selectedEmployee,
              style: AppTypography.bodyMedium.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          PopupMenuButton<String>(
            color: AppColors.glassStrong,
            icon: Icon(Icons.expand_more, color: AppColors.textSecondary),
            onSelected: (value) => setState(() => _selectedEmployee = value),
            itemBuilder: (context) {
              return _employees
                  .map(
                    (employee) => PopupMenuItem(
                      value: employee,
                      child: Text(
                        employee,
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  )
                  .toList();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildGroupSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.glassPrimary,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.glassBorder),
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
            child: const Icon(
              Icons.groups_outlined,
              size: 18,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _selectedGroup,
              style: AppTypography.bodyMedium.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          PopupMenuButton<String>(
            color: AppColors.glassStrong,
            icon: Icon(Icons.expand_more, color: AppColors.textSecondary),
            onSelected: (value) => setState(() => _selectedGroup = value),
            itemBuilder: (context) {
              return _groups
                  .map(
                    (group) => PopupMenuItem(
                      value: group,
                      child: Text(
                        group,
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  )
                  .toList();
            },
          ),
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
          color: isSelected ? AppColors.primary : AppColors.glassPrimary,
          borderRadius: BorderRadius.circular(24),
          border: isSelected
              ? null
              : Border.all(color: AppColors.glassBorder),
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
                color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
              ),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: AppTypography.bodySmall.copyWith(
                fontWeight: FontWeight.bold,
                color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
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
        color: AppColors.glassPrimary,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.glassBorder),
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
                  color: AppColors.textPrimary,
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

