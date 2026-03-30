import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:izumi/core/ui/app_icons.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/group_provider.dart';
import '../../providers/user_provider.dart';
import '../../utils/alphabet_filter_utils.dart';
import '../../widgets/glass/gradient_background.dart';
import '../../widgets/inputs/alphabet_filter.dart';

/// Edit Group Screen - Glassmorphism Design
/// Edit existing group with member management
class EditGroupScreen extends StatefulWidget {
  final String groupId;
  final String groupName;
  final List<String> teamLeadIds;
  final List<Map<String, dynamic>> members;

  const EditGroupScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.teamLeadIds,
    required this.members,
  });

  @override
  State<EditGroupScreen> createState() => _EditGroupScreenState();
}

class _EditGroupScreenState extends State<EditGroupScreen> {
  late TextEditingController _nameController;
  late List<String> _selectedTeamLeads;
  late List<Map<String, dynamic>> _members;
  final _memberSearchController = TextEditingController();
  String _memberSearchQuery = '';
  bool _memberSortAscending = true;
  bool _isSaving = false;
  bool _isResolvingMissingUsers = false;
  final Map<String, UserModel> _resolvedUsersByLookupId = {};

  UserModel? _employeeById(List<UserModel> employees, String id) {
    final cached = _resolvedUsersByLookupId[id];
    if (cached != null) return cached;
    return employees.where((e) => e.id == id || e.migratedFrom == id).firstOrNull;
  }

  Future<UserModel?> _lookupUserByIdInFirestore(String id) async {
    if (id.isEmpty) return null;

    final directDoc =
        await FirebaseFirestore.instance.collection('users').doc(id).get();
    if (directDoc.exists) {
      return UserModel.fromFirestore(directDoc);
    }

    final migratedQuery = await FirebaseFirestore.instance
        .collection('users')
        .where('migratedFrom', isEqualTo: id)
        .limit(1)
        .get();
    if (migratedQuery.docs.isEmpty) return null;
    return UserModel.fromFirestore(migratedQuery.docs.first);
  }

  Future<void> _resolveMissingUsers(List<UserModel> employees) async {
    if (_isResolvingMissingUsers) return;

    final idsToResolve = <String>{
      ..._selectedTeamLeads,
      ..._members.map((m) => m['id'] as String),
    }.where((id) {
      if (id.isEmpty) return false;
      if (_resolvedUsersByLookupId.containsKey(id)) return false;
      return _employeeById(employees, id) == null;
    }).toList();

    if (idsToResolve.isEmpty) return;

    _isResolvingMissingUsers = true;
    final resolved = <String, UserModel>{};
    try {
      for (final id in idsToResolve) {
        final user = await _lookupUserByIdInFirestore(id);
        if (user != null) {
          resolved[id] = user;
          resolved[user.id] = user;
          if (user.migratedFrom != null && user.migratedFrom!.isNotEmpty) {
            resolved[user.migratedFrom!] = user;
          }
        }
      }
    } catch (_) {
      // Best-effort fallback only; keep UI functional even if lookup fails.
    } finally {
      _isResolvingMissingUsers = false;
      if (resolved.isNotEmpty && mounted) {
        setState(() {
          _resolvedUsersByLookupId.addAll(resolved);
        });
      }
    }
  }

  String _resolveMemberName(Map<String, dynamic> member, List<UserModel> employees) {
    final id = member['id'] as String? ?? '';
    final emp = id.isEmpty ? null : _employeeById(employees, id);
    if (emp != null && emp.name.trim().isNotEmpty) return emp.name;
    final fallback = (member['name'] as String?)?.trim() ?? '';
    if (fallback.isNotEmpty && fallback.toLowerCase() != 'unknown') return fallback;
    return 'Unknown';
  }

  String _resolveMemberInitials(Map<String, dynamic> member, List<UserModel> employees) {
    final id = member['id'] as String? ?? '';
    final emp = id.isEmpty ? null : _employeeById(employees, id);
    if (emp != null) return emp.initials;
    final fallback = (member['initials'] as String?)?.trim() ?? '';
    if (fallback.isNotEmpty && fallback != '?') return fallback;
    final name = _resolveMemberName(member, employees);
    if (name.isNotEmpty && name != 'Unknown') return name[0].toUpperCase();
    return '?';
  }

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.groupName);
    _selectedTeamLeads = List.from(widget.teamLeadIds);
    _members = List.from(widget.members);
    // Safety net: ensure UserProvider has data even if navigated here directly
    final userProvider = context.read<UserProvider>();
    if (userProvider.employees.isEmpty) {
      final enterpriseId = context.read<AuthProvider>().enterpriseId ?? '';
      if (enterpriseId.isNotEmpty) {
        userProvider.streamUsers(enterpriseId);
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _memberSearchController.dispose();
    super.dispose();
  }

  Future<void> _removeMember(int index) async {
    final memberId = _members[index]['id'] as String;
    final groupProvider = context.read<GroupProvider>();
    final success = await groupProvider.removeMember(widget.groupId, memberId);
    if (success && mounted) {
      setState(() => _members.removeAt(index));
      await _syncLinkedChatMembersFromCurrentState();
    }
  }

  Future<void> _syncLinkedChatMembersFromCurrentState() async {
    final employees = context.read<UserProvider>().employees;
    final chatProvider = context.read<ChatProvider>();
    final authProvider = context.read<AuthProvider>();
    final enterpriseId = authProvider.enterpriseId;
    final adminId = authProvider.currentUser?.id ?? '';
    final canonicalMemberIds = <String>[];
    for (final member in _members) {
      final rawId = member['id'] as String;
      if (rawId.isEmpty) continue;
      final local = _employeeById(employees, rawId);
      if (local != null) {
        canonicalMemberIds.add(local.id);
        continue;
      }
      try {
        final remote = await _lookupUserByIdInFirestore(rawId);
        if (remote != null) {
          canonicalMemberIds.add(remote.id);
        }
      } catch (_) {
        // Skip unresolved members; save flow handles orphan cleanup.
      }
    }

    await chatProvider.syncMembersForLinkedGroup(
          linkedGroupId: widget.groupId,
          memberIds: canonicalMemberIds.toSet().toList(),
          extraMemberIds: [
            ..._selectedTeamLeads,
            if (adminId.isNotEmpty) adminId,
          ],
          enterpriseId: enterpriseId,
          groupName: widget.groupName,
        );
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
              onPressed: () async {
                Navigator.pop(ctx);
                final groupProvider = context.read<GroupProvider>();
                final success =
                    await groupProvider.deleteGroup(widget.groupId);
                if (success && mounted) {
                  context.pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Group deleted'),
                      backgroundColor: AppColors.success,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  );
                }
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

  Future<void> _saveChanges() async {
    setState(() => _isSaving = true);

    final groupProvider = context.read<GroupProvider>();
    final chatProvider = context.read<ChatProvider>();
    final authProvider = context.read<AuthProvider>();
    final enterpriseId = authProvider.enterpriseId;
    final adminId = authProvider.currentUser?.id ?? '';
    final employees = context.read<UserProvider>().employees;
    var removedInvalidCount = 0;

    Future<String?> resolveCanonicalId(String rawId) async {
      if (rawId.isEmpty) return null;
      final local = _employeeById(employees, rawId);
      if (local != null) return local.id;

      try {
        final remote = await _lookupUserByIdInFirestore(rawId);
        if (remote != null) {
          _resolvedUsersByLookupId[rawId] = remote;
          _resolvedUsersByLookupId[remote.id] = remote;
          if (remote.migratedFrom != null && remote.migratedFrom!.isNotEmpty) {
            _resolvedUsersByLookupId[remote.migratedFrom!] = remote;
          }
          return remote.id;
        }
      } catch (_) {
        // If lookup fails, treat as invalid to avoid persisting orphan IDs.
      }

      removedInvalidCount++;
      return null;
    }

    final normalizedLeadIds = <String>[];
    for (final id in _selectedTeamLeads) {
      final canonicalId = await resolveCanonicalId(id);
      if (canonicalId != null) normalizedLeadIds.add(canonicalId);
    }

    final normalizedMemberIds = <String>[];
    for (final member in _members) {
      final rawId = member['id'] as String;
      final canonicalId = await resolveCanonicalId(rawId);
      if (canonicalId != null) normalizedMemberIds.add(canonicalId);
    }

    final success = await groupProvider.updateGroup(widget.groupId, {
      'name': _nameController.text.trim(),
      'leadIds': normalizedLeadIds.toSet().toList(),
      'leadId': normalizedLeadIds.isNotEmpty ? normalizedLeadIds.first : '',
      'memberIds': normalizedMemberIds.toSet().toList(),
      'updatedAt': DateTime.now(),
    });

    if (success) {
      await chatProvider.syncMembersForLinkedGroup(
            linkedGroupId: widget.groupId,
            memberIds: normalizedMemberIds.toSet().toList(),
            extraMemberIds: [
              ...normalizedLeadIds.toSet(),
              if (adminId.isNotEmpty) adminId,
            ],
            enterpriseId: enterpriseId,
            groupName: widget.groupName,
          );
    }

    if (!mounted) return;

    if (success) {
      context.pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            removedInvalidCount > 0
                ? 'Group updated. Removed $removedInvalidCount invalid user reference(s).'
                : 'Group updated successfully',
          ),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } else {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(groupProvider.error ?? 'Failed to update group'),
          backgroundColor: AppColors.critical,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();
    final employees = userProvider.employees;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _resolveMissingUsers(employees);
    });

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
                      _buildFormSection(employees),
                      const SizedBox(height: 32),

                      // Team Members
                      _buildMembersSection(employees),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

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
                onTap: () => context.pop(),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.glassPrimary,
                  ),
                  child: const Icon(
                    AppIcons.arrow_left_2,
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
              GestureDetector(
                onTap: _isSaving ? null : _saveChanges,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.glassPrimary,
                  ),
                  child: _isSaving
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.textPrimary,
                          ),
                        )
                      : const Icon(
                          AppIcons.tick_circle,
                          color: AppColors.textPrimary,
                          size: 22,
                        ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _deleteGroup,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.critical.withValues(alpha: 0.15),
                  ),
                  child: Icon(
                    AppIcons.trash,
                    color: AppColors.critical,
                    size: 22,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFormSection(List<UserModel> employees) {
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
                    AppIcons.edit,
                    color: AppColors.textTertiary,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Team Leads
        Text(
          'Assign Team Leads',
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => _showTeamLeadSelector(employees),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                decoration: BoxDecoration(
                  color: AppColors.glassPrimary,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Icon(
                      AppIcons.crown_1,
                      color: AppColors.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _selectedTeamLeads.isEmpty
                            ? 'Tap to select team leads'
                            : _selectedTeamLeads.map((id) {
                                final emp = _employeeById(employees, id);
                                return emp?.name ?? 'Unknown';
                              }).join(', '),
                        style: AppTypography.bodyMedium.copyWith(
                          color: _selectedTeamLeads.isEmpty
                              ? AppColors.textTertiary
                              : AppColors.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      AppIcons.arrow_right_2,
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

  Widget _buildMembersSection(List<UserModel> employees) {
    var filteredMembers = _memberSearchQuery.isEmpty
        ? _members
        : _members
            .where((m) => _resolveMemberName(m, employees)
                .toLowerCase()
                .contains(_memberSearchQuery.toLowerCase()))
            .toList();

    filteredMembers.sort((a, b) {
      final nameA = _resolveMemberName(a, employees).toLowerCase();
      final nameB = _resolveMemberName(b, employees).toLowerCase();
      return _memberSortAscending
          ? nameA.compareTo(nameB)
          : nameB.compareTo(nameA);
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header
        Text(
          'Team Members (${_members.length})',
          style: AppTypography.bodyLarge.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),

        // Alphabet Filter
        AlphabetFilter(
          isAscending: _memberSortAscending,
          padding: EdgeInsets.zero,
          onToggle: (val) =>
              setState(() => _memberSortAscending = val),
        ),
        const SizedBox(height: 12),

        // Search Bar
        Container(
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.glassPrimary,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: TextField(
            controller: _memberSearchController,
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
              setState(() => _memberSearchQuery = value);
            },
          ),
        ),
        const SizedBox(height: 16),

        // Member List
        ...List.generate(filteredMembers.length, (index) {
          final member = filteredMembers[index];
          final originalIndex = _members.indexOf(member);
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildMemberCard(member, originalIndex, employees),
          );
        }),

        // Add Member Button
        _buildAddMemberButton(),
      ],
    );
  }

  Widget _buildMemberCard(
    Map<String, dynamic> member,
    int index,
    List<UserModel> employees,
  ) {
    final status = member['status'] as String? ?? 'offline';
    final isActive = status == 'active';
    final isAway = status == 'away' || status == 'break';

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
                    _resolveMemberInitials(member, employees),
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
                      _resolveMemberName(member, employees),
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
                    AppIcons.close_circle,
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
      onTap: () {
        _showAddMemberSheet();
      },
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
              child: Icon(AppIcons.add, size: 18, color: AppColors.primary),
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

  void _showAddMemberSheet() {
    final userProvider = context.read<UserProvider>();
    final allEmployees = userProvider.employees;
    final currentMemberIds =
        _members.map((m) => m['id'] as String).toSet();

    // Filter out employees already in the group
    final available =
        allEmployees.where((e) => !currentMemberIds.contains(e.id)).toList();

    String searchQuery = '';
    bool sortAscending = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          var filtered = searchQuery.isEmpty
              ? available
              : available
                  .where((e) => e.name
                      .toLowerCase()
                      .contains(searchQuery.toLowerCase()))
                  .toList();
          filtered = sortUsersByName(filtered, sortAscending);
          return Container(
        height: MediaQuery.of(ctx).size.height * 0.55,
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
              child: Text('Add Member', style: AppTypography.h3),
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
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        'No available employees',
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (ctx, index) {
                        final emp = filtered[index];
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
                          onTap: () async {
                            Navigator.pop(ctx);
                            final groupProvider =
                                context.read<GroupProvider>();
                            final success = await groupProvider.addMember(
                                widget.groupId, emp.id);
                            if (success && mounted) {
                              setState(() {
                                _members.add({
                                  'id': emp.id,
                                  'name': emp.name,
                                  'initials': emp.initials,
                                  'status': 'offline',
                                });
                              });
                              await _syncLinkedChatMembersFromCurrentState();
                            }
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

}
