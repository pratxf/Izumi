import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:izumi/core/ui/app_icons.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_typography.dart';
import '../../models/chat_group_model.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/user_provider.dart';
import '../../repositories/group_repository.dart';
import '../../utils/alphabet_filter_utils.dart';
import '../../widgets/glass/gradient_background.dart';
import '../../widgets/inputs/alphabet_filter.dart';
import '../../widgets/inputs/text_input_field.dart';
import '../../widgets/navigation/app_header.dart';

class EditChatGroupScreen extends StatefulWidget {
  final ChatGroupModel group;

  const EditChatGroupScreen({super.key, required this.group});

  @override
  State<EditChatGroupScreen> createState() => _EditChatGroupScreenState();
}

class _EditChatGroupScreenState extends State<EditChatGroupScreen> {
  final GroupRepository _groupRepo = GroupRepository();
  late final TextEditingController _nameController;
  late final List<String> _selectedMembers;
  late String _mode;
  bool _isSaving = false;
  int? _linkedGroupMemberCount;
  List<String> _linkedGroupMemberIds = const [];
  String? _resolvedLinkedGroupId;

  bool get _isLinkedGroup =>
      _resolvedLinkedGroupId != null && _resolvedLinkedGroupId!.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.group.name);
    _selectedMembers = List<String>.from(widget.group.memberIds);
    _mode = widget.group.mode;

    final userProvider = context.read<UserProvider>();
    if (userProvider.users.isEmpty) {
      final authProvider = context.read<AuthProvider>();
      final enterpriseId = authProvider.enterpriseId ?? '';
      if (enterpriseId.isNotEmpty) {
        userProvider.streamUsers(enterpriseId);
      }
    }

    _loadLinkedGroupMemberCount();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadLinkedGroupMemberCount() async {
    String? linkedGroupId = widget.group.linkedGroupId;
    if (linkedGroupId == null || linkedGroupId.trim().isEmpty) {
      final enterpriseId = context.read<AuthProvider>().enterpriseId ?? '';
      if (enterpriseId.isNotEmpty && widget.group.name.trim().isNotEmpty) {
        try {
          final groups = await _groupRepo.getGroupsByEnterprise(enterpriseId);
          final matchedGroup = groups
              .where((group) => group.name.trim() == widget.group.name.trim())
              .firstOrNull;
          linkedGroupId = matchedGroup?.id;
        } catch (_) {
          // Best-effort UI lookup only.
        }
      }
    }
    if (linkedGroupId == null || linkedGroupId.trim().isEmpty) return;

    try {
      final linkedGroup = await _groupRepo.getGroup(linkedGroupId);
      if (!mounted || linkedGroup == null) return;
      setState(() {
        _resolvedLinkedGroupId = linkedGroup.id;
        _linkedGroupMemberCount = linkedGroup.memberIds.length;
        _linkedGroupMemberIds = List<String>.from(linkedGroup.memberIds);
      });
    } catch (_) {
      // Best-effort UI hint only.
    }
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();
    final allUsers = userProvider.users;

    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              const AppHeader(
                title: 'Edit Chat Group',
                type: AppHeaderType.secondary,
                showAvatar: false,
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Group Name
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
                              controller: _nameController,
                              hint: 'e.g., Project Updates',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Mode Selector
                      _buildGlassCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Chat Mode',
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                _buildModeChip(
                                  label: 'Open',
                                  icon: AppIcons.message,
                                  isSelected: _mode == 'open',
                                  onTap: () =>
                                      setState(() => _mode = 'open'),
                                ),
                                const SizedBox(width: 12),
                                _buildModeChip(
                                  label: 'Broadcast',
                                  icon: AppIcons.volume_high,
                                  isSelected: _mode == 'broadcast',
                                  onTap: () =>
                                      setState(() => _mode = 'broadcast'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _mode == 'open'
                                  ? 'All members can send messages.'
                                  : 'Only admins and team leads can send messages.',
                              style: AppTypography.caption.copyWith(
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Member Selector
                      _buildGlassCard(
                        onTap: _isLinkedGroup
                            ? () => _showLinkedGroupMembers(allUsers)
                            : () => _showMemberSelector(allUsers),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color:
                                    AppColors.primary.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(
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
                                    'Members',
                                    style:
                                        AppTypography.bodyMedium.copyWith(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _isLinkedGroup
                                        ? _linkedGroupMemberCount == null
                                            ? 'Tap to view linked group members'
                                            : '$_linkedGroupMemberCount members from linked group'
                                        : '${_selectedMembers.length} members selected',
                                    style: AppTypography.caption.copyWith(
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              AppIcons.arrow_right_2,
                              color: AppColors.textSecondary,
                            ),
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
            onTap: _isSaving ? null : _saveChanges,
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
                child: _isSaving
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        'Save Changes',
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

  Widget _buildModeChip({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primary.withValues(alpha: 0.2)
                : AppColors.glassPrimary,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(
              color: isSelected
                  ? AppColors.primary.withValues(alpha: 0.6)
                  : AppColors.glassBorder,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected
                    ? AppColors.primaryLight
                    : AppColors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                label,
                style: AppTypography.bodySmall.copyWith(
                  color: isSelected
                      ? AppColors.primaryLight
                      : AppColors.textSecondary,
                  fontWeight:
                      isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMemberSelector(List<UserModel> users) {
    String searchQuery = '';
    bool sortAscending = true;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          var filtered = searchQuery.isEmpty
              ? users
              : users
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
                    borderRadius: BorderRadius.circular(17),
                    border: Border.all(color: AppColors.glassBorder),
                  ),
                  child: TextField(
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search members...',
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
                    final user = filtered[index];
                    final isSelected = _selectedMembers.contains(user.id);
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppColors.surfaceMuted,
                        child: Text(
                          user.initials,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(
                        user.name,
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        user.activeRole,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textTertiary,
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
                              _selectedMembers.add(user.id);
                            } else {
                              _selectedMembers.remove(user.id);
                            }
                          });
                          setState(() {});
                        },
                      ),
                      onTap: () {
                        setModalState(() {
                          if (isSelected) {
                            _selectedMembers.remove(user.id);
                          } else {
                            _selectedMembers.add(user.id);
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

  void _showLinkedGroupMembers(List<UserModel> users) {
    bool sortAscending = true;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final linkedMembers = users
              .where((user) => _linkedGroupMemberIds.contains(user.id))
              .toList();
          final filteredMembers = sortUsersByName(linkedMembers, sortAscending);
          final missingIds = _linkedGroupMemberIds
              .where((id) => !linkedMembers.any((user) => user.id == id))
              .toList();

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
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Linked Group Members', style: AppTypography.h3),
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
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AlphabetFilter(
                    isAscending: sortAscending,
                    onToggle: (val) =>
                        setModalState(() => sortAscending = val),
                  ),
                ),
                Expanded(
                  child: filteredMembers.isEmpty && missingIds.isEmpty
                      ? Center(
                          child: Text(
                            'No members found',
                            style: AppTypography.bodyMedium.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        )
                      : ListView(
                          children: [
                            for (final user in filteredMembers)
                              ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: AppColors.surfaceMuted,
                                  child: Text(
                                    user.initials,
                                    style: AppTypography.bodySmall.copyWith(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  user.name,
                                  style: AppTypography.bodyMedium.copyWith(
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                subtitle: Text(
                                  user.activeRole,
                                  style: AppTypography.caption.copyWith(
                                    color: AppColors.textTertiary,
                                  ),
                                ),
                              ),
                            for (final userId in missingIds)
                              ListTile(
                                leading: const CircleAvatar(
                                  backgroundColor: AppColors.surfaceMuted,
                                  child: Icon(
                                    AppIcons.user,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                title: Text(
                                  'Unknown user',
                                  style: AppTypography.bodyMedium.copyWith(
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                subtitle: Text(
                                  userId,
                                  style: AppTypography.caption.copyWith(
                                    color: AppColors.textTertiary,
                                  ),
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          );
        },
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

  Future<void> _saveChanges() async {
    if (_nameController.text.trim().isEmpty) {
      _showValidationError('Please enter a group name');
      return;
    }
    if (_selectedMembers.isEmpty) {
      _showValidationError('Please add at least one member');
      return;
    }

    setState(() => _isSaving = true);

    final authProvider = context.read<AuthProvider>();
    final chatProvider = context.read<ChatProvider>();
    final data = <String, dynamic>{
      'name': _nameController.text.trim(),
      'mode': _mode,
    };

    if (!_isLinkedGroup) {
      final memberIds = <String>{
        ..._selectedMembers.where((id) => id.trim().isNotEmpty),
        if (widget.group.createdBy.trim().isNotEmpty) widget.group.createdBy,
        if ((authProvider.currentUser?.id ?? '').trim().isNotEmpty)
          authProvider.currentUser!.id,
      }.toList();
      data['memberIds'] = memberIds;
    }

    final success = await chatProvider.updateChatGroup(
      widget.group.id,
      data,
    );

    if (!mounted) return;

    if (success) {
      context.pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Group updated'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } else {
      setState(() => _isSaving = false);
      _showValidationError(chatProvider.error ?? 'Failed to update group');
    }
  }
}
