import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';
import '../../models/task_model.dart';
import '../../models/user_model.dart';
import '../../models/group_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/group_provider.dart';
import '../../providers/task_provider.dart';
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
  final _taskTitleController = TextEditingController();
  final _descriptionController = TextEditingController();

  String _assignType = 'individual'; // 'individual', 'team_lead', 'group'
  String _priority = 'high'; // 'high', 'medium', 'low'
  bool _sendNotification = true;
  DateTime _dueDate = DateTime.now().add(const Duration(days: 7));
  bool _isCreating = false;

  String? _selectedEmployeeId;
  String? _selectedGroupId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  void _loadData() {
    final authProvider = context.read<AuthProvider>();
    final enterpriseId = authProvider.enterpriseId;
    if (enterpriseId == null) return;

    final dashboardProvider = context.read<DashboardProvider>();
    if (dashboardProvider.employees.isEmpty) {
      dashboardProvider.initDashboard(enterpriseId);
    } else {
      dashboardProvider.refreshEmployees(enterpriseId);
    }

    final groupProvider = context.read<GroupProvider>();
    if (groupProvider.groups.isEmpty) {
      groupProvider.loadGroups(enterpriseId);
    } else {
      groupProvider.loadGroups(enterpriseId);
    }

    // Pre-select employee if initialAssigneeName is provided
    if (widget.initialAssigneeName != null &&
        widget.initialAssigneeName!.isNotEmpty) {
      _assignType = 'individual';
      final match = dashboardProvider.employees
          .where((e) => e.name == widget.initialAssigneeName)
          .toList();
      if (match.isNotEmpty) {
        _selectedEmployeeId = match.first.id;
      }
    }
  }

  @override
  void dispose() {
    _taskTitleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.primary,
              onPrimary: AppColors.textPrimary,
              surface: Color(0xFF1E1E2E),
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _dueDate = picked);
    }
  }

  Future<void> _createTask() async {
    final title = _taskTitleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please enter a task title'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final authProvider = context.read<AuthProvider>();
    final enterpriseId = authProvider.enterpriseId;
    final assignedBy = authProvider.currentUser?.id ?? '';

    if (enterpriseId == null) return;

    // Determine assignedTo based on assign type
    String assignedTo = '';
    String? groupId;

    if (_assignType == 'individual' || _assignType == 'team_lead') {
      if (_selectedEmployeeId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Please select an employee'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      assignedTo = _selectedEmployeeId!;
    } else if (_assignType == 'group') {
      if (_selectedGroupId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Please select a group'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      groupId = _selectedGroupId;
      // Assign to group lead or first member
      final groupProvider = context.read<GroupProvider>();
      final group = groupProvider.getGroupById(_selectedGroupId!);
      assignedTo = group?.leadId ?? '';
    }

    setState(() => _isCreating = true);

    // Resolve display names for assignedBy and assignedTo
    final assignedByName = authProvider.currentUser?.name ?? 'Admin';
    final employees = context.read<DashboardProvider>().employees;
    final assigneeMatch = employees.where((e) => e.id == assignedTo).toList();
    final assignedToName = assigneeMatch.isNotEmpty ? assigneeMatch.first.name : null;

    final now = DateTime.now();
    final task = TaskModel(
      id: '',
      enterpriseId: enterpriseId,
      title: title,
      description: _descriptionController.text.trim().isNotEmpty
          ? _descriptionController.text.trim()
          : null,
      type: 'task',
      priority: _priority,
      status: 'pending',
      assignedTo: assignedTo,
      assignedBy: assignedBy,
      assignedByName: assignedByName,
      assignedToName: assignedToName,
      groupId: groupId,
      dueDate: _dueDate,
      sendNotification: _sendNotification,
      createdAt: now,
      updatedAt: now,
    );

    final taskId = await context.read<TaskProvider>().createTask(task);

    setState(() => _isCreating = false);

    if (!mounted) return;

    if (taskId != null) {
      context.pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Task created successfully'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to create task'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final employees = context.watch<DashboardProvider>().employees;
    final groups = context.watch<GroupProvider>().groups;

    // Filter employees by role for team_lead assign type
    final teamLeads =
        employees.where((e) => e.activeRole == 'team_lead').toList();

    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              // Header
              AppHeader(
                title: widget.isTeamLead ? 'Assign New Task' : 'Assign Task',
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
                        hint: 'Enter task title...',
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
                            icon: Iconsax.user,
                            value: 'individual',
                          ),
                          if (!widget.isTeamLead) ...[
                            const SizedBox(height: 12),
                            _buildRadioCard(
                              title: 'Team Lead',
                              icon: Iconsax.people,
                              value: 'team_lead',
                              isPrimary: true,
                              showVerified: true,
                            ),
                            const SizedBox(height: 12),
                          ] else
                            const SizedBox(height: 12),
                          _buildRadioCard(
                            title: 'Entire Group',
                            icon: Iconsax.people,
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
                        _buildEmployeeSelector(employees),
                        const SizedBox(height: 24),
                      ],

                      // Select Team Lead Dropdown
                      if (_assignType == 'team_lead' &&
                          !widget.isTeamLead) ...[
                        _buildInputLabel('Select Team Lead'),
                        _buildEmployeeSelector(teamLeads),
                        const SizedBox(height: 24),
                      ],

                      // Group Selector
                      if (_assignType == 'group') ...[
                        _buildInputLabel('Choose Group'),
                        _buildGroupSelector(groups),
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
                  color: AppColors.primary.withValues(alpha: 0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: _isCreating ? null : _createTask,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(32),
                ),
                elevation: 0,
              ),
              child: _isCreating
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: AppColors.textPrimary,
                        strokeWidth: 2,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Iconsax.task_square,
                          color: AppColors.textPrimary,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Text('Assign Task', style: AppTypography.buttonLarge),
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
              ? AppColors.primary.withValues(alpha: 0.2)
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
                  color:
                      isSelected ? AppColors.primary : AppColors.glassBorder,
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
              color: isSelected
                  ? AppColors.textPrimary
                  : AppColors.textSecondary,
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: AppTypography.bodyMedium.copyWith(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                color: isSelected
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
              ),
            ),
            if (isSelected) ...[
              const Spacer(),
              const Icon(Iconsax.check,
                  color: AppColors.primary, size: 20),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDueDateCard() {
    return GestureDetector(
      onTap: _pickDueDate,
      child: Container(
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
              DateFormat('dd MMM yyyy').format(_dueDate),
              style: AppTypography.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const Icon(Iconsax.calendar,
                color: AppColors.primary, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildEmployeeSelector(List<UserModel> employeeList) {
    final selectedEmployee = _selectedEmployeeId != null
        ? employeeList
            .where((e) => e.id == _selectedEmployeeId)
            .toList()
        : [];
    final displayName = selectedEmployee.isNotEmpty
        ? selectedEmployee.first.name
        : (employeeList.isNotEmpty ? 'Select employee...' : 'Loading...');
    final displayInitials = selectedEmployee.isNotEmpty
        ? selectedEmployee.first.initials
        : '?';

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
              color: AppColors.primary.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                displayInitials,
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
              displayName,
              style: AppTypography.bodyMedium.copyWith(
                fontWeight: FontWeight.bold,
                color: selectedEmployee.isNotEmpty
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
              ),
            ),
          ),
          PopupMenuButton<String>(
            color: AppColors.glassStrong,
            icon:
                Icon(Iconsax.arrow_down_1, color: AppColors.textSecondary),
            onSelected: (value) =>
                setState(() => _selectedEmployeeId = value),
            itemBuilder: (context) {
              return employeeList
                  .map(
                    (employee) => PopupMenuItem(
                      value: employee.id,
                      child: Text(
                        employee.name,
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

  Widget _buildGroupSelector(List<GroupModel> groupList) {
    final selectedGroup = _selectedGroupId != null
        ? groupList
            .where((g) => g.id == _selectedGroupId)
            .toList()
        : [];
    final displayName = selectedGroup.isNotEmpty
        ? selectedGroup.first.name
        : (groupList.isNotEmpty ? 'Select group...' : 'Loading...');

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
              color: AppColors.primary.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Iconsax.people,
              size: 18,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              displayName,
              style: AppTypography.bodyMedium.copyWith(
                fontWeight: FontWeight.bold,
                color: selectedGroup.isNotEmpty
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
              ),
            ),
          ),
          PopupMenuButton<String>(
            color: AppColors.glassStrong,
            icon:
                Icon(Iconsax.arrow_down_1, color: AppColors.textSecondary),
            onSelected: (value) =>
                setState(() => _selectedGroupId = value),
            itemBuilder: (context) {
              return groupList
                  .map(
                    (group) => PopupMenuItem(
                      value: group.id,
                      child: Text(
                        group.name,
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
        Expanded(child: _buildPriorityPill('High', 'high', Iconsax.flag)),
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
                    color: AppColors.primary.withValues(alpha: 0.2),
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
                color: isSelected
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
              ),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: AppTypography.bodySmall.copyWith(
                fontWeight: FontWeight.bold,
                color: isSelected
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
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
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Iconsax.notification,
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
            activeThumbColor: AppColors.primary,
            activeTrackColor: AppColors.primary.withValues(alpha: 0.2),
          ),
        ],
      ),
    );
  }
}
