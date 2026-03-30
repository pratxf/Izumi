import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:izumi/core/ui/app_icons.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';
import '../../models/chat_group_model.dart';
import '../../models/group_model.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/group_provider.dart';
import '../../providers/user_provider.dart';
import '../../utils/alphabet_filter_utils.dart';
import '../../widgets/glass/gradient_background.dart';
import '../../widgets/inputs/alphabet_filter.dart';
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
  final List<String> _selectedTeamLeads = [];
  final List<String> _selectedMembers = [];
  bool _createChatGroup = false;
  String _chatMode = 'open';
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    // Safety net: ensure UserProvider has data even if navigated here directly
    final userProvider = context.read<UserProvider>();
    if (userProvider.employees.isEmpty) {
      final authProvider = context.read<AuthProvider>();
      final enterpriseId = authProvider.enterpriseId ?? '';
      if (enterpriseId.isNotEmpty) {
        userProvider.streamUsers(enterpriseId);
      }
    }
  }

  @override
  void dispose() {
    _groupNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();
    final employees = userProvider.employees;

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

                      // Team Lead Selector
                      _buildGlassCard(
                        onTap: () => _showTeamLeadSelector(employees),
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
                                AppIcons.crown_1,
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
                                    'Assign Team Leads',
                                    style: AppTypography.bodyMedium.copyWith(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _selectedTeamLeads.isEmpty
                                        ? 'Tap to select team leads'
                                        : '${_selectedTeamLeads.length} team lead${_selectedTeamLeads.length == 1 ? '' : 's'} selected',
                                    style: AppTypography.caption.copyWith(
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              AppIcons.arrow_right_2,
                              color: AppColors.textSecondary,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Add Members
                      _buildGlassCard(
                        onTap: () => _showMemberSelector(employees),
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
                                AppIcons.user_add,
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
                              AppIcons.arrow_right_2,
                              color: AppColors.textSecondary,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Create Chat Group Toggle
                      _buildGlassCard(
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Icon(
                                    AppIcons.message,
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
                                        'Create Chat Group',
                                        style: AppTypography.bodyMedium.copyWith(
                                          color: AppColors.textPrimary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Auto-create a chat for this group',
                                        style: AppTypography.caption.copyWith(
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Switch(
                                  value: _createChatGroup,
                                  onChanged: (v) => setState(() => _createChatGroup = v),
                                  activeThumbColor: AppColors.primary,
                                  activeTrackColor: AppColors.primary.withValues(alpha: 0.3),
                                ),
                              ],
                            ),
                            if (_createChatGroup) ...[
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  _buildModeChip('Open', 'open'),
                                  const SizedBox(width: 10),
                                  _buildModeChip('Broadcast', 'broadcast'),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
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
            onTap: _isCreating ? null : _createGroup,
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
                child: _isCreating
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        'Create Group',
                        style: AppTypography.headline.copyWith(
                          color: Colors.white,
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

  void _showTeamLeadSelector(List<UserModel> employees) {
    String searchQuery = '';
    bool sortAscending = true;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          var filtered = searchQuery.isEmpty
              ? employees
              : employees
                  .where((e) => e.name
                      .toLowerCase()
                      .contains(searchQuery.toLowerCase()))
                  .toList();
          filtered = sortUsersByName(filtered, sortAscending);
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
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Select Team Leads', style: AppTypography.h3),
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
                // Search bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.glassPrimary,
                      borderRadius: BorderRadius.circular(12),
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
                        prefixIcon: Icon(
                          AppIcons.search_normal_1,
                          color: AppColors.textTertiary,
                          size: 18,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onChanged: (value) {
                        setModalState(() => searchQuery = value);
                      },
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AlphabetFilter(
                    isAscending: sortAscending,
                    onToggle: (val) =>
                        setModalState(() => sortAscending = val),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final emp = filtered[index];
                      final isSelected = _selectedTeamLeads.contains(emp.id);
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppColors.surfaceMuted,
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
                                _selectedTeamLeads.add(emp.id);
                              } else {
                                _selectedTeamLeads.remove(emp.id);
                              }
                            });
                            setState(() {});
                          },
                        ),
                        onTap: () {
                          setModalState(() {
                            if (isSelected) {
                              _selectedTeamLeads.remove(emp.id);
                            } else {
                              _selectedTeamLeads.add(emp.id);
                            }
                          });
                          setState(() {});
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

  void _showMemberSelector(List<UserModel> employees) {
    String searchQuery = '';
    bool sortAscending = true;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          var filtered = searchQuery.isEmpty
              ? employees
              : employees
                  .where((e) => e.name
                      .toLowerCase()
                      .contains(searchQuery.toLowerCase()))
                  .toList();
          filtered = sortUsersByName(filtered, sortAscending);
          return Container(
          height: MediaQuery.of(context).size.height * 0.6,
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
              // Search bar
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.glassPrimary,
                    borderRadius: BorderRadius.circular(12),
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
                      prefixIcon: Icon(
                        AppIcons.search_normal_1,
                        color: AppColors.textTertiary,
                        size: 18,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onChanged: (value) {
                      setModalState(() => searchQuery = value);
                    },
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AlphabetFilter(
                  isAscending: sortAscending,
                  onToggle: (val) =>
                      setModalState(() => sortAscending = val),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final emp = filtered[index];
                    final isSelected = _selectedMembers.contains(emp.id);
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppColors.surfaceMuted,
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
                              _selectedMembers.add(emp.id);
                            } else {
                              _selectedMembers.remove(emp.id);
                            }
                          });
                          setState(() {}); // Update parent
                        },
                      ),
                      onTap: () {
                        setModalState(() {
                          if (isSelected) {
                            _selectedMembers.remove(emp.id);
                          } else {
                            _selectedMembers.add(emp.id);
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
        );
        },
      ),
    );
  }

  Widget _buildModeChip(String label, String value) {
    final isSelected = _chatMode == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _chatMode = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : AppColors.glassPrimary,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.glassBorder,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: AppTypography.bodySmall.copyWith(
                color: isSelected ? Colors.white : AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showValidationError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.critical,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _createGroup() async {
    if (_groupNameController.text.trim().isEmpty) {
      _showValidationError('Please enter a group name');
      return;
    }
    if (_selectedTeamLeads.isEmpty) {
      _showValidationError('Please select at least one team lead');
      return;
    }
    if (_selectedMembers.isEmpty) {
      _showValidationError('Please add at least one member');
      return;
    }

    setState(() => _isCreating = true);

    final authProvider = context.read<AuthProvider>();
    final groupProvider = context.read<GroupProvider>();
    final enterpriseId = authProvider.enterpriseId ?? '';

    final group = GroupModel(
      id: '',
      enterpriseId: enterpriseId,
      name: _groupNameController.text.trim(),
      leadIds: _selectedTeamLeads,
      color: '#6366F1',
      memberIds: _selectedMembers,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final groupId = await groupProvider.createGroup(group);

    if (!mounted) return;

    if (groupId != null) {
      // Auto-create chat group if toggled on
      String successMsg = 'Group "${_groupNameController.text}" created!';
      if (_createChatGroup) {
        final chatProvider = context.read<ChatProvider>();
        final adminId = authProvider.currentUser?.id ?? '';
        final chatMemberIds = <String>{
          ..._selectedTeamLeads,
          ..._selectedMembers,
          if (adminId.isNotEmpty) adminId,
        }.toList();

        final now = DateTime.now();
        final chatGroup = ChatGroupModel(
          id: '',
          enterpriseId: enterpriseId,
          name: _groupNameController.text.trim(),
          description: '',
          linkedGroupId: groupId,
          createdBy: adminId,
          memberIds: chatMemberIds,
          mode: _chatMode,
          lastMessage: null,
          lastMessageAt: null,
          lastReadAt: const {},
          createdAt: now,
          updatedAt: now,
        );

        final chatGroupId = await chatProvider.createChatGroup(chatGroup);
        if (chatGroupId != null) {
          successMsg = 'Group & chat group created!';
        }
        if (!mounted) return;
      }

      context.pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(successMsg),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } else {
      setState(() => _isCreating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(groupProvider.error ?? 'Failed to create group'),
          backgroundColor: AppColors.critical,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }
}
