import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';
import '../../widgets/glass/gradient_background.dart';
import '../../widgets/glass/glass_chip.dart';
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
  final GlobalKey _employeeSelectorKey = GlobalKey();
  final GlobalKey _teamLeadSelectorKey = GlobalKey();
  final GlobalKey _groupSelectorKey = GlobalKey();

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
  DateTime _dueDate = DateTime(2026, 2, 15);

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
                      if (widget.isTeamLead) ...[
                        _buildTeamLeadForm(),
                      ] else ...[
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
                        widget.isTeamLead
                            ? _buildEmployeeSelector()
                            : GlassInputField(
                                controller: _assignedEmployeeController,
                                enabled: false,
                                prefixIcon: Iconsax.user,
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
                    Iconsax.task_square,
                    color: AppColors.textPrimary,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    widget.isTeamLead ? 'Assign Task' : 'Assign Task',
                    style: AppTypography.buttonLarge,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime(2035, 12, 31),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.dark(
              primary: AppColors.primary,
              onPrimary: AppColors.textPrimary,
              surface: AppColors.glassNav,
              onSurface: AppColors.textPrimary,
            ),
            dialogBackgroundColor: AppColors.glassNav,
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
                  WidgetStateProperty.all(AppColors.primary.withOpacity(0.2)),
              actionsPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              actionBarHeight: 48,
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

  Widget _buildTeamLeadForm() {
    return Column(
      children: [
        _buildTeamLeadCard(
          title: 'Task Details',
          icon: Iconsax.document,
          child: Column(
            children: [
              _buildTeamLeadField(
                label: 'Task Name',
                child: GlassInputField(
                  controller: _taskTitleController,
                  hint: 'e.g. Monthly Inventory Audit',
                ),
              ),
              const SizedBox(height: 16),
              _buildTeamLeadField(
                label: 'Description',
                child: GlassInputField(
                  controller: _descriptionController,
                  hint: 'Enter task details, requirements, and instructions...',
                  maxLines: 4,
                  contentPadding: const EdgeInsets.all(20),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildTeamLeadCard(
          title: 'Assignee',
          icon: Iconsax.user_add,
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: GlassChip(
                      label: 'Individual',
                      selected: _assignType == 'individual',
                      onTap: () => setState(() => _assignType = 'individual'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GlassChip(
                      label: 'Entire Group',
                      selected: _assignType == 'group',
                      onTap: () => setState(() => _assignType = 'group'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_assignType == 'group')
                _buildGroupSelector()
              else
                _buildEmployeeSelector(),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildTeamLeadCard(
          title: 'Scheduling',
          icon: Iconsax.calendar_1,
          child: Column(
            children: [
              _buildTeamLeadField(
                label: 'Due Date',
                child: _buildDueDateCard(),
              ),
              const SizedBox(height: 16),
              _buildTeamLeadField(
                label: 'Priority Level',
                child: _buildPrioritySelector(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildNotificationToggle(),
      ],
    );
  }

  Widget _buildTeamLeadCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.glassPrimary,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.textSecondary, size: 20),
              const SizedBox(width: 8),
              Text(
                title.toUpperCase(),
                style: AppTypography.caption.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildTeamLeadField({
    required String label,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
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
              const Icon(Iconsax.check, color: AppColors.primary, size: 20),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDueDateCard() {
    final formattedDate =
        '${_dueDate.day.toString().padLeft(2, '0')} '
        '${_monthLabel(_dueDate.month)} '
        '${_dueDate.year}';
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
                formattedDate,
                style: AppTypography.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const Icon(
                Iconsax.calendar,
                color: AppColors.primary,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _monthLabel(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }

  Widget _buildTeamLeadSelector() {
    return GestureDetector(
      onTap: () => _showFullWidthMenu(
        key: _teamLeadSelectorKey,
        items: _employees,
        onSelected: (value) => setState(() => _selectedEmployee = value),
      ),
      child: Container(
        key: _teamLeadSelectorKey,
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
            Expanded(
              child: Text(
                _selectedEmployee,
                style: AppTypography.bodyMedium.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Icon(Iconsax.arrow_down_1, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _buildEmployeeSelector() {
    return GestureDetector(
      onTap: () => _showFullWidthMenu(
        key: _employeeSelectorKey,
        items: _employees,
        onSelected: (value) => setState(() => _selectedEmployee = value),
      ),
      child: Container(
        key: _employeeSelectorKey,
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
            Icon(Iconsax.arrow_down_1, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupSelector() {
    return GestureDetector(
      onTap: () => _showFullWidthMenu(
        key: _groupSelectorKey,
        items: _groups,
        onSelected: (value) => setState(() => _selectedGroup = value),
      ),
      child: Container(
        key: _groupSelectorKey,
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
                Iconsax.people,
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
            Icon(Iconsax.arrow_down_1, color: AppColors.textSecondary),
          ],
        ),
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
            activeColor: AppColors.primary,
            activeTrackColor: AppColors.primary.withOpacity(0.2),
          ),
        ],
      ),
    );
  }

  Future<void> _showFullWidthMenu({
    required GlobalKey key,
    required List<String> items,
    required ValueChanged<String> onSelected,
  }) async {
    final RenderBox renderBox =
        key.currentContext?.findRenderObject() as RenderBox;
    final Offset offset = renderBox.localToGlobal(Offset.zero);
    final Size size = renderBox.size;

    final sortedItems = List<String>.from(items)
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final selected = await showMenu<String>(
      context: context,
      color: AppColors.glassNav,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.glassBorder),
      ),
      constraints: BoxConstraints.tightFor(width: size.width),
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + size.height,
        offset.dx + size.width,
        0,
      ),
      items: sortedItems
          .map(
            (item) => PopupMenuItem<String>(
              value: item,
              child: SizedBox(
                width: size.width,
                child: Text(
                  item,
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );

    if (selected != null) {
      onSelected(selected);
    }
  }
}

