import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:izumi/core/ui/app_icons.dart';
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
import '../../providers/team_provider.dart';
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

  Future<void> _loadData() async {
    final authProvider = context.read<AuthProvider>();
    final enterpriseId = authProvider.enterpriseId;
    if (enterpriseId == null) return;

    if (widget.isTeamLead) {
      // Team leads only need their own team data
      final teamProvider = context.read<TeamProvider>();
      final userId = authProvider.currentUser?.id;
      if (userId != null && teamProvider.group == null) {
        await teamProvider.initTeam(enterpriseId, userId);
      }
    } else {
      final dashboardProvider = context.read<DashboardProvider>();
      final groupProvider = context.read<GroupProvider>();
      if (dashboardProvider.employees.isEmpty) {
        await dashboardProvider.initDashboard(enterpriseId);
      } else {
        await dashboardProvider.refreshEmployees(enterpriseId);
      }

      groupProvider.loadGroups(enterpriseId);
    }

    if (!mounted) return;

    // Pre-select employee if initialAssigneeName is provided
    if (widget.initialAssigneeName != null &&
        widget.initialAssigneeName!.isNotEmpty) {
      _assignType = 'individual';
      final employees = widget.isTeamLead
          ? context.read<TeamProvider>().teamMembers
          : context.read<DashboardProvider>().employees;
      final match = employees
          .where((e) => e.name == widget.initialAssigneeName)
          .toList();
      if (match.isNotEmpty) {
        setState(() => _selectedEmployeeId = match.first.id);
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
            colorScheme: ColorScheme.dark(
              primary: AppColors.primary,
              onPrimary: AppColors.textPrimary,
              surface: AppColors.glassNav,
              onSurface: AppColors.textPrimary,
            ),
            visualDensity: VisualDensity.compact,
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                textStyle: AppTypography.bodySmall.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            datePickerTheme: DatePickerThemeData(
              backgroundColor: AppColors.glassNav,
              headerBackgroundColor: AppColors.glassStrong,
              headerForegroundColor: AppColors.textPrimary,
              dayForegroundColor:
                  WidgetStateProperty.all(AppColors.textPrimary),
              weekdayStyle: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
              dayStyle: AppTypography.bodySmall.copyWith(
                color: AppColors.textPrimary,
              ),
              todayForegroundColor:
                  WidgetStateProperty.all(AppColors.textPrimary),
              todayBackgroundColor:
                  WidgetStateProperty.all(AppColors.primary.withValues(alpha: 0.2)),
            ), dialogTheme: DialogThemeData(backgroundColor: AppColors.glassNav),
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
    final taskProvider = context.read<TaskProvider>();
    final messenger = ScaffoldMessenger.of(context);

    // Force-refresh the ID token so Firestore gets latest custom claims
    await authProvider.refreshTokenAndClaims();
    if (!mounted) return;

    final enterpriseId = authProvider.enterpriseId;
    final assignedBy = authProvider.currentUser?.id ?? '';

    if (enterpriseId == null) {
      messenger.showSnackBar(
        SnackBar(
          content: const Text('Enterprise not found. Please log out and log in again.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Determine assignedTo based on assign type
    String assignedTo = '';
    String? groupId;

    if (_assignType == 'individual' || _assignType == 'team_lead') {
      if (_selectedEmployeeId == null) {
        messenger.showSnackBar(
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
      // Team lead: auto-use their own group, create one task per member
      if (widget.isTeamLead) {
        final teamProvider = context.read<TeamProvider>();
        final teamGroup = teamProvider.group;
        if (teamGroup == null) {
          messenger.showSnackBar(
            SnackBar(
              content: const Text('Group not found'),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }

        final currentUserId = authProvider.currentUser?.id;
        final members = teamProvider.teamMembers
            .where((m) => m.id != currentUserId)
            .toList();

        if (members.isEmpty) {
          messenger.showSnackBar(
            SnackBar(
              content: const Text('No members in your group to assign'),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }

        setState(() => _isCreating = true);

        final assignedByName = authProvider.currentUser?.name ?? 'Team Lead';
        final now = DateTime.now();
        final description = _descriptionController.text.trim().isNotEmpty
            ? _descriptionController.text.trim()
            : null;
        int successCount = 0;

        for (final member in members) {
          final task = TaskModel(
            id: '',
            enterpriseId: enterpriseId,
            title: title,
            description: description,
            type: 'task',
            priority: _priority,
            status: 'pending',
            assignedTo: member.id,
            assignedBy: assignedBy,
            assignedByName: assignedByName,
            assignedToName: member.name,
            groupId: teamGroup.id,
            dueDate: _dueDate,
            sendNotification: _sendNotification,
            createdAt: now,
            updatedAt: now,
          );
          final taskId = await taskProvider.createTask(task);
          if (taskId != null) successCount++;
        }

        if (!mounted) return;
        setState(() => _isCreating = false);

        if (successCount > 0) {
          context.pop();
          messenger.showSnackBar(
            SnackBar(
              content: Text('Task assigned to $successCount member${successCount > 1 ? 's' : ''}'),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          messenger.showSnackBar(
            SnackBar(
              content: const Text('Failed to create tasks'),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      // Admin flow: requires group selection
      if (_selectedGroupId == null) {
        messenger.showSnackBar(
          SnackBar(
            content: const Text('Please select a group'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      groupId = _selectedGroupId;
      final group = context.read<GroupProvider>().getGroupById(_selectedGroupId!);
      assignedTo = group?.leadId ?? '';
    }

    setState(() => _isCreating = true);

    // Resolve display names for assignedBy and assignedTo
    final assignedByName = authProvider.currentUser?.name ?? (widget.isTeamLead ? 'Team Lead' : 'Admin');
    final employees = widget.isTeamLead
        ? context.read<TeamProvider>().teamMembers
        : context.read<DashboardProvider>().employees;
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

    final taskId = await taskProvider.createTask(task);

    if (!mounted) return;
    setState(() => _isCreating = false);

    if (taskId != null) {
      context.pop();
      messenger.showSnackBar(
        SnackBar(
          content: const Text('Task created successfully'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      final errorMsg = taskProvider.error ?? 'Unknown error';
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to create task: $errorMsg'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final teamProvider = widget.isTeamLead ? context.watch<TeamProvider>() : null;
    final employees = widget.isTeamLead
        ? (teamProvider?.teamMembers ?? [])
        : context.watch<DashboardProvider>().employees;
    final groups = widget.isTeamLead
        ? [if (teamProvider?.group != null) teamProvider!.group!]
        : context.watch<GroupProvider>().groups;

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
                            icon: AppIcons.user,
                            value: 'individual',
                          ),
                          if (!widget.isTeamLead) ...[
                            const SizedBox(height: 12),
                            _buildRadioCard(
                              title: 'Team Lead',
                              icon: AppIcons.people,
                              value: 'team_lead',
                              isPrimary: true,
                              showVerified: true,
                            ),
                            const SizedBox(height: 12),
                          ] else
                            const SizedBox(height: 12),
                          _buildRadioCard(
                            title: 'Entire Group',
                            icon: AppIcons.people,
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
                        if (widget.isTeamLead && teamProvider?.group != null) ...[
                          // Team leads have one group — show it as a static label
                          _buildInputLabel('Group'),
                          _buildStaticGroupCard(teamProvider!.group!.name),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'All members in your group will be assigned (excluding you).',
                              style: AppTypography.caption.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ] else ...[
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
                        ],
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
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          AppIcons.task_square,
                          color: Colors.white,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Text('Assign Task', style: AppTypography.buttonLarge.copyWith(color: Colors.white)),
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
              const Icon(AppIcons.check,
                  color: AppColors.primary, size: 20),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDueDateCard() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _pickDueDate,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
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
              const Icon(
                AppIcons.calendar,
                color: AppColors.primary,
                size: 20,
              ),
            ],
          ),
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

    return GestureDetector(
      onTap: () => _showEmployeePicker(employeeList),
      child: Container(
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
            Icon(AppIcons.arrow_down_1, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  void _showEmployeePicker(List<UserModel> employeeList) {
    String searchQuery = '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final filtered = searchQuery.isEmpty
              ? employeeList
              : employeeList
                  .where((e) => e.name
                      .toLowerCase()
                      .contains(searchQuery.toLowerCase()))
                  .toList();
          return Container(
            height: MediaQuery.of(context).size.height * 0.55,
            decoration: const BoxDecoration(
              color: AppColors.glassStrong,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Text('Select Employee', style: AppTypography.h3),
                ),
                // Search bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.glassPrimary,
                      borderRadius: BorderRadius.circular(17),
                      border: Border.all(color: AppColors.glassBorder),
                    ),
                    child: TextField(
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search employees...',
                        hintStyle: AppTypography.bodySmall.copyWith(
                          color: AppColors.textTertiary,
                        ),
                        prefixIcon: Padding(
                          padding: const EdgeInsets.only(left: 12, right: 8),
                          child: Icon(
                            AppIcons.search_normal_1,
                            color: AppColors.textTertiary,
                            size: 18,
                          ),
                        ),
                        prefixIconConstraints: const BoxConstraints(
                          minWidth: 0,
                          minHeight: 0,
                        ),
                        border: InputBorder.none,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onChanged: (value) {
                        setModalState(() => searchQuery = value);
                      },
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final emp = filtered[index];
                      final isSelected = _selectedEmployeeId == emp.id;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isSelected
                              ? AppColors.primary.withValues(alpha: 0.3)
                              : AppColors.surfaceMuted,
                          child: Text(
                            emp.initials,
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          emp.name,
                          style: AppTypography.bodyMedium.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight:
                                isSelected ? FontWeight.bold : FontWeight.w500,
                          ),
                        ),
                        trailing: isSelected
                            ? const Icon(AppIcons.tick_circle,
                                color: AppColors.primary, size: 20)
                            : null,
                        onTap: () {
                          setState(() => _selectedEmployeeId = emp.id);
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
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

    return GestureDetector(
      onTap: () => _showGroupPicker(groupList),
      child: Container(
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
                AppIcons.people,
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
            Icon(AppIcons.arrow_down_1, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  void _showGroupPicker(List<GroupModel> groupList) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.4,
        decoration: const BoxDecoration(
          color: AppColors.glassStrong,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text('Select Group', style: AppTypography.h3),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: groupList.length,
                itemBuilder: (context, index) {
                  final group = groupList[index];
                  final isSelected = _selectedGroupId == group.id;
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isSelected
                          ? AppColors.primary.withValues(alpha: 0.3)
                          : AppColors.surfaceMuted,
                      child: const Icon(
                        AppIcons.people,
                        size: 18,
                        color: AppColors.primary,
                      ),
                    ),
                    title: Text(
                      group.name,
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(AppIcons.tick_circle,
                            color: AppColors.primary, size: 20)
                        : null,
                    onTap: () {
                      setState(() => _selectedGroupId = group.id);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStaticGroupCard(String groupName) {
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
              AppIcons.people,
              size: 18,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              groupName,
              style: AppTypography.bodyMedium.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrioritySelector() {
    return Row(
      children: [
        Expanded(child: _buildPriorityPill('High', 'high', AppIcons.flag)),
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
                    ? Colors.white
                    : AppColors.textSecondary,
              ),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: AppTypography.bodySmall.copyWith(
                fontWeight: FontWeight.bold,
                color: isSelected
                    ? Colors.white
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
                  AppIcons.notification,
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
