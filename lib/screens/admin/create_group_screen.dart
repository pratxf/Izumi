import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';
import '../../widgets/glass/gradient_background.dart';
import '../../widgets/inputs/text_input_field.dart';
import '../../widgets/navigation/app_header.dart';

/// Create Group Screen - Form to create a new team group
class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _groupNameController = TextEditingController();
  final _teamLeadSearchController = TextEditingController();
  String? _selectedTeamLead;
  final List<String> _selectedMembers = [];

  final List<Map<String, String>> _employees = [
    {'id': '1', 'name': 'Sarah Jenkins'},
    {'id': '2', 'name': 'Marcus Chen'},
    {'id': '3', 'name': 'Elena Rodriguez'},
    {'id': '4', 'name': 'David Okafor'},
    {'id': '5', 'name': 'Priya Sharma'},
  ];

  List<Map<String, String>> get _sortedEmployees {
    final list = List<Map<String, String>>.from(_employees);
    list.sort((a, b) => a['name']!.compareTo(b['name']!));
    return list;
  }

  @override
  void dispose() {
    _groupNameController.dispose();
    _teamLeadSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              const AppHeader(
                title: 'New Group',
                type: AppHeaderType.secondary,
                showAvatar: false,
              ),

              // Form Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Group Name Input
                      _buildGlassCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Group Name',
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            GlassInputField(
                              controller: _groupNameController,
                              hint: 'e.g., West Region - Team Alpha',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Team Lead Picker
                      _buildGlassCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Assign Team Lead',
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _buildTeamLeadPicker(),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Add Members
                      _buildGlassCard(
                        onTap: _showMemberSelector,
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Icon(
                                Iconsax.user_add,
                                color: AppColors.primary,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Add Members',
                                    style: AppTypography.bodyMedium.copyWith(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _selectedMembers.isEmpty
                                        ? 'Tap to select members'
                                        : '${_selectedMembers.length} members selected',
                                    style: AppTypography.caption.copyWith(
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.chevron_right,
                              color: AppColors.textSecondary,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // Sticky Footer Button
        bottomSheet: Container(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            bottom: MediaQuery.of(context).padding.bottom + 16,
            top: 16,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                AppColors.glassStrong,
                AppColors.glassStrong.withValues(alpha: 0),
              ],
            ),
          ),
          child: GestureDetector(
            onTap: _createGroup,
            child: Container(
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.4),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  'Create Group',
                  style: AppTypography.headline.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGlassCard({required Widget child, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.glassPrimary,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildDropdown() {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.glassPrimary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedTeamLead,
          isExpanded: true,
          isDense: true,
          alignment: Alignment.centerLeft,
          hint: Text(
            'Select an employee',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
          icon: const Icon(Icons.unfold_more, color: AppColors.textSecondary),
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.textPrimary,
          ),
          dropdownColor: AppColors.glassNav,
          borderRadius: BorderRadius.circular(16),
          items: _sortedEmployees.map((emp) {
            return DropdownMenuItem(
              value: emp['id'],
              child: Text(
                emp['name']!,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            );
          }).toList(),
          onChanged: (value) {
            setState(() => _selectedTeamLead = value);
          },
        ),
      ),
    );
  }

  Widget _buildTeamLeadPicker() {
    final selectedName = _selectedTeamLead == null
        ? null
        : _sortedEmployees
            .firstWhere(
              (emp) => emp['id'] == _selectedTeamLead,
              orElse: () => _sortedEmployees.first,
            )['name'];
    return GestureDetector(
      onTap: _openTeamLeadPicker,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.glassPrimary,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                selectedName ?? 'Select an employee',
                style: AppTypography.bodyMedium.copyWith(
                  color: selectedName == null
                      ? AppColors.textTertiary
                      : AppColors.textPrimary,
                ),
              ),
            ),
            const Icon(Icons.search, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  void _showMemberSelector() {
    showModalBottomSheet(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.6,
          decoration: BoxDecoration(
            color: AppColors.glassStrong.withValues(alpha: 0.94),
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
                padding: const EdgeInsets.all(20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Select Members', style: AppTypography.h3),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        'Done',
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: _sortedEmployees.length,
                  itemBuilder: (context, index) {
                    final emp = _sortedEmployees[index];
                    final isSelected = _selectedMembers.contains(emp['id']);
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppColors.glassPrimary,
                        child: Text(
                          emp['name']!
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
                      title: Text(
                        emp['name']!,
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                      trailing: Checkbox(
                        value: isSelected,
                        activeColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                        onChanged: (value) {
                          setModalState(() {
                          if (value == true) {
                            _selectedMembers.add(emp['id']!);
                          } else {
                            _selectedMembers.remove(emp['id']);
                          }
                          });
                          setState(() {}); // Update parent
                        },
                      ),
                      onTap: () {
                        setModalState(() {
                          if (isSelected) {
                            _selectedMembers.remove(emp['id']);
                          } else {
                            _selectedMembers.add(emp['id']!);
                          }
                        });
                        setState(() {}); // Update parent
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openTeamLeadPicker() {
    showModalBottomSheet(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildSearchSheet(
        title: 'Assign Team Lead',
        controller: _teamLeadSearchController,
        items: _sortedEmployees.map((emp) => emp['name']!).toList(),
        onSelected: (value) {
          final match = _sortedEmployees.firstWhere(
            (emp) => emp['name'] == value,
            orElse: () => _sortedEmployees.first,
          );
          setState(() => _selectedTeamLead = match['id']);
        },
      ),
    );
  }

  Widget _buildSearchSheet({
    required String title,
    required TextEditingController controller,
    required List<String> items,
    required ValueChanged<String> onSelected,
  }) {
    return StatefulBuilder(
      builder: (context, setModalState) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
        decoration: BoxDecoration(
          color: AppColors.glassNav,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(title, style: AppTypography.h3),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Done',
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: controller,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textPrimary,
                ),
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.search, color: AppColors.textSecondary),
                  hintText: 'Search...',
                  hintStyle: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textTertiary,
                  ),
                  filled: true,
                  fillColor: AppColors.glassPrimary,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: AppColors.glassBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: AppColors.glassBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: AppColors.primary),
                  ),
                ),
                onChanged: (_) => setModalState(() {}),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: items
                    .where((item) => item
                        .toLowerCase()
                        .contains(controller.text.toLowerCase()))
                    .map(
                      (item) => ListTile(
                        title: Text(
                          item,
                          style: AppTypography.bodyMedium.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          onSelected(item);
                        },
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _createGroup() {
    if (_groupNameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please enter a group name'),
          backgroundColor: AppColors.critical,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      return;
    }

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Group "${_groupNameController.text}" created!'),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

