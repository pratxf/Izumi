import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';
import '../../widgets/glass/gradient_background.dart';

/// Edit Group Screen - Glassmorphism Design
/// Edit existing group with member management
class EditGroupScreen extends StatefulWidget {
  final String groupId;
  final String groupName;
  final String teamLeadId;
  final List<Map<String, dynamic>> members;

  const EditGroupScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.teamLeadId,
    required this.members,
  });

  @override
  State<EditGroupScreen> createState() => _EditGroupScreenState();
}

class _EditGroupScreenState extends State<EditGroupScreen> {
  late TextEditingController _nameController;
  late TextEditingController _teamLeadSearchController;
  late String _selectedTeamLead;
  late List<Map<String, dynamic>> _members;

  final List<Map<String, String>> _teamLeads = [
    {'id': 'rajesh', 'name': 'Rajesh Kumar'},
    {'id': 'sarah', 'name': 'Sarah Connor'},
    {'id': 'mike', 'name': 'Mike Ross'},
  ];

  List<Map<String, String>> get _sortedTeamLeads {
    final list = List<Map<String, String>>.from(_teamLeads);
    list.sort((a, b) => a['name']!.compareTo(b['name']!));
    return list;
  }

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.groupName);
    _teamLeadSearchController = TextEditingController();
    _selectedTeamLead = widget.teamLeadId;
    _members = List.from(widget.members);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _teamLeadSearchController.dispose();
    super.dispose();
  }

  String get _selectedLeadName {
    return _teamLeads
        .firstWhere(
          (lead) => lead['id'] == _selectedTeamLead,
          orElse: () => _teamLeads.first,
        )['name']!;
  }

  void _removeMember(int index) {
    setState(() => _members.removeAt(index));
  }

  void _deleteGroup() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: AlertDialog(
          backgroundColor: AppColors.glassStrong,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Text(
            'Delete Group',
            style: AppTypography.h3.copyWith(color: AppColors.textPrimary),
          ),
          content: Text(
            'Are you sure you want to delete this group? This action cannot be undone.',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Cancel',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
                // Delete group logic
              },
              child: Text(
                'Delete',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.critical,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
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
              _buildHeader(),

              // Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 160),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Form Fields
                      _buildFormSection(),
                      const SizedBox(height: 32),

                      // Team Members
                      _buildMembersSection(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // Bottom Actions removed (icons in header)
      ),
    );
  }

  Widget _buildHeader() {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: AppColors.glassHeader,
            border: Border(
              bottom: BorderSide(color: AppColors.glassBorder),
            ),
          ),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.glassPrimary,
                  ),
                  child: const Icon(
                    Iconsax.arrow_left_2,
                    color: AppColors.textPrimary,
                    size: 22,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  'Edit Group',
                  style: AppTypography.bodyLarge.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      // Save changes
                      Navigator.pop(context);
                    },
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.glassPrimary,
                        border: Border.all(color: AppColors.glassBorder),
                      ),
                      child: const Icon(
                        Iconsax.tick_circle,
                        color: AppColors.textPrimary,
                        size: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _deleteGroup,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.glassPrimary,
                        border: Border.all(color: AppColors.glassBorder),
                      ),
                      child: const Icon(
                        Iconsax.trash,
                        color: AppColors.critical,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFormSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Group Name
        Text(
          'Group Name',
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.glassPrimary,
                borderRadius: BorderRadius.circular(16),
              ),
              child: TextField(
                controller: _nameController,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  suffixIcon: Icon(
                    Iconsax.edit,
                    color: AppColors.textTertiary,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Team Lead
        Text(
          'Assign Team Lead',
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _openTeamLeadPicker,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: AppColors.glassPrimary,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _selectedLeadName,
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Icon(
                      Iconsax.search_normal,
                      color: AppColors.textTertiary,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMembersSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Team Members (${_members.length})',
              style: AppTypography.bodyLarge.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Member List
        ...List.generate(_members.length, (index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildMemberCard(_members[index], index),
          );
        }),

        // Add Member Button
        _buildAddMemberButton(),
      ],
    );
  }

  Widget _buildMemberCard(Map<String, dynamic> member, int index) {
    final isActive = member['status'] == 'active';
    final isAway = member['status'] == 'away';

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.glassPrimary,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Row(
            children: [
              // Avatar
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withValues(alpha: 0.15),
                  border: Border.all(color: AppColors.glassBorder, width: 2),
                ),
                child: Center(
                  child: Text(
                    member['initials'] ?? member['name']![0],
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member['name'],
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isActive
                                ? AppColors.success
                                : isAway
                                ? AppColors.warning
                                : AppColors.textDisabled,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isActive
                              ? 'Active'
                              : isAway
                              ? 'Away'
                              : 'Offline',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Remove Button
              GestureDetector(
                onTap: () => _removeMember(index),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.glassPrimary,
                  ),
                  child: Icon(
                    Iconsax.close_circle,
                    size: 18,
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAddMemberButton() {
    return GestureDetector(
      onTap: _openAddMemberSheet,
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          color: AppColors.glassPrimary,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.3),
            width: 2,
            strokeAlign: BorderSide.strokeAlignCenter,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.1),
              ),
              child: Icon(Iconsax.add, size: 18, color: AppColors.primary),
            ),
            const SizedBox(width: 10),
            Text(
              'Add Member',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openTeamLeadPicker() {
    showModalBottomSheet(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        final leads = _sortedTeamLeads;
        return _buildSearchSheet(
          title: 'Assign Team Lead',
          controller: _teamLeadSearchController,
          items: leads.map((lead) => lead['name']!).toList(),
          onSelected: (value) {
            final match = leads.firstWhere(
              (lead) => lead['name'] == value,
              orElse: () => leads.first,
            );
            setState(() => _selectedTeamLead = match['id']!);
          },
        );
      },
    );
  }

  void _openAddMemberSheet() {
    showModalBottomSheet(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        final available = [
          {'name': 'Amit Patel', 'status': 'active'},
          {'name': 'Priya Sharma', 'status': 'active'},
          {'name': 'David Kim', 'status': 'away'},
          {'name': 'Neha Verma', 'status': 'offline'},
        ];
        available.sort((a, b) => a['name']!.compareTo(b['name']!));
        return _buildSearchSheet(
          title: 'Add Member',
          controller: TextEditingController(),
          items: available.map((member) => member['name']!).toList(),
          onSelected: (value) {
            final match = available.firstWhere(
              (member) => member['name'] == value,
              orElse: () => available.first,
            );
            setState(() {
              _members.add({
                'name': match['name']!,
                'initials': match['name']!
                    .split(' ')
                    .map((part) => part[0])
                    .take(2)
                    .join()
                    .toUpperCase(),
                'status': match['status'] ?? 'active',
              });
            });
          },
        );
      },
    );
  }

  Widget _buildSearchSheet({
    required String title,
    required TextEditingController controller,
    required List<String> items,
    required ValueChanged<String> onSelected,
  }) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              color: AppColors.glassNav,
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(top: 12, bottom: 16),
                    decoration: BoxDecoration(
                      color: AppColors.glassBorder,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      title,
                      style: AppTypography.h3.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: TextField(
                      controller: controller,
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textPrimary,
                      ),
                      decoration: InputDecoration(
                        prefixIcon: Icon(Iconsax.search_normal,
                            color: AppColors.textSecondary),
                        hintText: 'Search...',
                        hintStyle: AppTypography.bodyMedium.copyWith(
                          color: AppColors.textTertiary,
                        ),
                        filled: true,
                        fillColor: AppColors.glassPrimary,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide:
                              BorderSide(color: AppColors.glassBorder),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide:
                              BorderSide(color: AppColors.glassBorder),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: AppColors.primary),
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
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
          ),
        );
      },
    );
  }

}

