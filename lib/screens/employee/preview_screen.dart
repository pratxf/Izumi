import 'dart:io';
import 'dart:async';
import 'dart:ui';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:izumi/core/ui/app_icons.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_shadows.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_typography.dart';
import '../../models/customer_suggestion_model.dart';
import '../../models/chat_group_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/group_provider.dart';
import '../../providers/photo_provider.dart';
import '../../providers/session_provider.dart';
import '../../repositories/photo_repository.dart';
import '../../widgets/glass/gradient_background.dart';
import '../../widgets/glass/glass_chip.dart';
import '../../widgets/navigation/app_header.dart';

/// Preview Screen
/// Photo preview with metadata entry form
class PreviewScreen extends StatefulWidget {
  final String location;
  final DateTime timestamp;
  final String? imagePath;

  const PreviewScreen({
    super.key,
    required this.location,
    required this.timestamp,
    this.imagePath,
  });

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  final PhotoRepository _photoRepository = PhotoRepository();
  String _category = 'distributor';
  String _customerType = 'new';
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _notesController = TextEditingController();
  final FocusNode _nameFocusNode = FocusNode();
  bool _shareToGroupChats = false;
  bool _createFollowUp = false;
  DateTime? _dueDate;
  bool _isSaving = false;
  final Set<String> _selectedGroupIds = {};
  List<ChatGroupModel> _fallbackChatGroups = const [];
  String _loadedLinkedGroupIdsKey = '';
  bool _initialDialogShown = false;
  Timer? _suggestionDebounce;
  bool _isLoadingSuggestions = false;
  bool _hasSearchedSuggestions = false;
  List<CustomerSuggestionModel> _nameSuggestions = const [];
  final Map<String, List<CustomerSuggestionModel>> _suggestionCache = {};
  String? _preparedImagePath;
  bool _isPreparingImage = false;
  String? _imagePreparationError;
  bool _shouldDeletePreparedImage = false;

  @override
  void initState() {
    super.initState();
    _prepareImageForPreview();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initStreams();
    });
    _nameFocusNode.addListener(_handleNameFocusChange);
  }

  @override
  void dispose() {
    _suggestionDebounce?.cancel();
    _nameController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
    _nameFocusNode
      ..removeListener(_handleNameFocusChange)
      ..dispose();
    unawaited(_cleanupPreparedImageIfNeeded());
    super.dispose();
  }

  void _handleNameFocusChange() {
    if (!_nameFocusNode.hasFocus && mounted) {
      setState(() => _nameSuggestions = const []);
    }
  }

  Future<void> _prepareImageForPreview() async {
    final sourcePath = widget.imagePath?.trim();
    if (sourcePath == null || sourcePath.isEmpty) return;

    if (mounted) {
      setState(() {
        _isPreparingImage = true;
        _imagePreparationError = null;
      });
    }

    try {
      final sourceFile = File(sourcePath);
      final sourceExists = await sourceFile.exists();
      debugPrint(
        '[PreviewScreen] Preparing image source path=$sourcePath exists=$sourceExists',
      );

      if (!sourceExists) {
        throw const FileSystemException(
          'Captured image is missing before preview.',
        );
      }

      final appSupportDir = await getApplicationSupportDirectory();
      final uploadDir = Directory(
        path.join(appSupportDir.path, 'captured_photos'),
      );
      if (!await uploadDir.exists()) {
        await uploadDir.create(recursive: true);
      }

      final extension = path.extension(sourceFile.path);
      final safeExtension = extension.isNotEmpty ? extension : '.jpg';
      final preparedPath = path.join(
        uploadDir.path,
        'capture_${DateTime.now().microsecondsSinceEpoch}$safeExtension',
      );

      final copiedFile = await sourceFile.copy(preparedPath);
      debugPrint(
        '[PreviewScreen] Prepared stable image copy source=$sourcePath target=${copiedFile.path}',
      );

      if (!mounted) return;
      setState(() {
        _preparedImagePath = copiedFile.path;
        _isPreparingImage = false;
        _shouldDeletePreparedImage = true;
      });
    } catch (e) {
      debugPrint(
          '[PreviewScreen] Failed to prepare image path=${widget.imagePath}: $e');
      if (!mounted) return;
      setState(() {
        _preparedImagePath = null;
        _isPreparingImage = false;
        _imagePreparationError =
            'This photo is no longer available. Please retake it and try again.';
      });
    }
  }

  Future<void> _cleanupPreparedImageIfNeeded() async {
    if (!_shouldDeletePreparedImage) return;
    final preparedPath = _preparedImagePath;
    if (preparedPath == null || preparedPath.isEmpty) return;

    try {
      final file = File(preparedPath);
      if (await file.exists()) {
        await file.delete();
        debugPrint('[PreviewScreen] Deleted prepared image $preparedPath');
      }
    } catch (e) {
      debugPrint(
          '[PreviewScreen] Failed to delete prepared image $preparedPath: $e');
    } finally {
      _shouldDeletePreparedImage = false;
    }
  }

  void _initStreams() {
    final authProvider = context.read<AuthProvider>();
    final enterpriseId = authProvider.enterpriseId ?? '';
    final userId = authProvider.currentUser?.id ?? '';
    if (enterpriseId.isEmpty || userId.isEmpty) return;

    context.read<GroupProvider>().streamGroups(enterpriseId);
    context
        .read<ChatProvider>()
        .streamChatGroups(enterpriseId, userId, isAdmin: authProvider.isAdmin);
    _refreshFallbackChatGroups();
  }

  Future<void> _refreshFallbackChatGroups() async {
    final authProvider = context.read<AuthProvider>();
    final enterpriseId = authProvider.enterpriseId ?? '';
    if (enterpriseId.isEmpty) return;

    final linkedGroupIds = _currentUserGroupIds(
      authProvider,
      context.read<GroupProvider>(),
    )..sort();
    final nextKey = '$enterpriseId|${linkedGroupIds.join(',')}';
    if (nextKey == _loadedLinkedGroupIdsKey) return;

    _loadedLinkedGroupIdsKey = nextKey;
    final groups = await context.read<ChatProvider>().getLinkedChatGroups(
          enterpriseId: enterpriseId,
          linkedGroupIds: linkedGroupIds,
        );
    if (!mounted) return;
    setState(() {
      _fallbackChatGroups = groups;
    });
    final chatProvider = context.read<ChatProvider>();
    final groupProvider = context.read<GroupProvider>();
    final sendableGroups =
        _sendableChatGroups(chatProvider, authProvider, groupProvider);
    _scheduleInitialShareDialogIfNeeded(sendableGroups);
  }

  List<String> _currentUserGroupIds(
    AuthProvider authProvider,
    GroupProvider groupProvider,
  ) {
    final userId = authProvider.currentUser?.id ?? '';
    final primaryGroupId = authProvider.currentUser?.groupId;
    if (userId.isEmpty) return const [];

    final groupIds = <String>{
      if (primaryGroupId != null && primaryGroupId.isNotEmpty) primaryGroupId,
      ...groupProvider.groups
          .where((group) =>
              group.memberIds.contains(userId) ||
              group.leadIds.contains(userId))
          .map((group) => group.id),
    };
    return groupIds.toList();
  }

  String? _defaultOperationalGroupId(
    AuthProvider authProvider,
    GroupProvider groupProvider,
  ) {
    final primaryGroupId = authProvider.currentUser?.groupId;
    if (primaryGroupId != null && primaryGroupId.isNotEmpty) {
      return primaryGroupId;
    }
    final groupIds = _currentUserGroupIds(authProvider, groupProvider);
    return groupIds.isNotEmpty ? groupIds.first : null;
  }

  List<ChatGroupModel> _sendableChatGroups(
    ChatProvider chatProvider,
    AuthProvider authProvider,
    GroupProvider groupProvider,
  ) {
    final allowedGroupIds =
        _currentUserGroupIds(authProvider, groupProvider).toSet();
    final currentUserId = authProvider.currentUser?.id ?? '';
    final currentEnterpriseId = authProvider.enterpriseId ?? '';
    final allCandidateGroups = <String, ChatGroupModel>{
      for (final group in chatProvider.chatGroups) group.id: group,
      for (final group in _fallbackChatGroups) group.id: group,
    };

    return allCandidateGroups.values.where((group) {
      if (_isManualShareableChat(
        group,
        currentUserId: currentUserId,
        currentEnterpriseId: currentEnterpriseId,
        isAdmin: authProvider.isAdmin,
      )) {
        return true;
      }

      if (group.linkedGroupId == null ||
          !allowedGroupIds.contains(group.linkedGroupId)) {
        return false;
      }
      if (!group.isBroadcast) return true;
      return authProvider.isAdmin || authProvider.isTeamLead;
    }).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  bool _isManualShareableChat(
    ChatGroupModel group, {
    required String currentUserId,
    required String currentEnterpriseId,
    required bool isAdmin,
  }) {
    if (group.linkedGroupId != null && group.linkedGroupId!.trim().isNotEmpty) {
      return false;
    }
    if (currentEnterpriseId.isEmpty ||
        group.enterpriseId != currentEnterpriseId) {
      return false;
    }

    final isMember =
        currentUserId.isNotEmpty && group.memberIds.contains(currentUserId);
    if (!(isAdmin || isMember)) {
      return false;
    }

    // Also allow manually-created enterprise chat groups that are not tied to an
    // operational group, so user-created team chats can be selected in the share
    // popup without affecting linked group behavior.
    return true;
  }

  void _selectDueDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 7)),
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
            dialogTheme:
                const DialogThemeData(backgroundColor: AppColors.glassNav),
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
              todayBackgroundColor: WidgetStateProperty.all(
                  AppColors.primary.withValues(alpha: 0.2)),
            ),
          ),
          child: child!,
        );
      },
    );
    if (date != null) {
      setState(() => _dueDate = date);
    }
  }

  void _scheduleInitialShareDialogIfNeeded(
    List<ChatGroupModel> sendableGroups,
  ) {
    if (_initialDialogShown ||
        sendableGroups.isEmpty ||
        _isPreparingImage ||
        _imagePreparationError != null) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _initialDialogShown) return;
      final route = ModalRoute.of(context);
      if (route != null && !route.isCurrent) return;

      _initialDialogShown = true;
      _showInitialShareDialog(sendableGroups);
    });
  }

  void _showInitialShareDialog(List<ChatGroupModel> sendableGroups) {
    showDialog(
      context: context,
      builder: (ctx) => Theme(
        data: Theme.of(context).copyWith(
          dialogTheme: const DialogThemeData(
            backgroundColor: AppColors.glassNav,
          ),
        ),
        child: AlertDialog(
          backgroundColor: AppColors.glassNav,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: AppColors.glassBorder),
          ),
          title: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  AppIcons.share,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Share Photo',
                style: AppTypography.bodyLarge.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          content: Text(
            'Would you also like to share this photo to your group chats?',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
              },
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: AppColors.glassBorder),
                ),
              ),
              child: Text(
                'Save Only',
                style: AppTypography.buttonMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () {
                setState(() {
                  _shareToGroupChats = true;
                  _selectedGroupIds.addAll(
                    sendableGroups.map((g) => g.id),
                  );
                });
                Navigator.of(ctx).pop();
              },
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                'Save & Share',
                style: AppTypography.buttonMedium.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _savePhoto({bool share = false}) async {
    if (_isSaving || _isPreparingImage) return;
    setState(() => _isSaving = true);

    final authProvider = context.read<AuthProvider>();
    final photoProvider = context.read<PhotoProvider>();
    final sessionProvider = context.read<SessionProvider>();
    final groupProvider = context.read<GroupProvider>();

    // Use Firebase Auth UID directly as fallback — always available when authenticated
    final userId = authProvider.currentUser?.id ??
        FirebaseAuth.instance.currentUser?.uid ??
        '';
    final enterpriseId = authProvider.enterpriseId ?? '';
    final sessionId = sessionProvider.activeSession?.id ?? '';

    debugPrint(
        '[PreviewScreen] _savePhoto: userId=$userId, enterpriseId=$enterpriseId, sessionId=$sessionId');

    if (userId.isEmpty || enterpriseId.isEmpty) {
      debugPrint(
          '[PreviewScreen] ERROR: userId or enterpriseId is empty, cannot upload');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
                'Upload failed: user session not ready. Please try again.'),
            backgroundColor: AppColors.critical,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
      setState(() => _isSaving = false);
      return;
    }

    final nameText = _nameController.text.trim();
    final phoneText = _phoneController.text.trim();
    final notesText = _notesController.text.trim();
    final defaultGroupId =
        _defaultOperationalGroupId(authProvider, groupProvider);

    final preparedImagePath = _preparedImagePath;
    if (preparedImagePath != null && preparedImagePath.isNotEmpty) {
      final preparedImageFile = File(preparedImagePath);
      final imageExists = await preparedImageFile.exists();
      debugPrint(
        '[PreviewScreen] Upload image path=$preparedImagePath exists=$imageExists',
      );

      if (!imageExists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'This photo is no longer available. Please retake it and try again.',
              ),
              backgroundColor: AppColors.critical,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
        setState(() => _isSaving = false);
        return;
      }

      final photo = await photoProvider.uploadPhoto(
        imageFile: preparedImageFile,
        enterpriseId: enterpriseId,
        employeeId: userId,
        sessionId: sessionId,
        location: widget.location,
        latitude: sessionProvider.currentLat,
        longitude: sessionProvider.currentLng,
        category: _category,
        customerType: _customerType,
        customerName: nameText.isNotEmpty ? nameText : null,
        customerPhone: phoneText.isNotEmpty ? phoneText : null,
        notes: notesText.isNotEmpty ? notesText : null,
        groupId: defaultGroupId,
        hasFollowUp: _createFollowUp,
        shareToGroupIds: share ? _selectedGroupIds.toList() : const <String>[],
        shareCaption: _buildQueuedShareCaption(
          groupProvider: groupProvider,
          defaultGroupId: defaultGroupId,
          nameText: nameText,
          phoneText: phoneText,
          notesText: notesText,
        ),
        shareSenderId: userId,
        shareSenderName: authProvider.currentUser?.name,
        followUpTask: _buildQueuedFollowUpTask(
          authProvider: authProvider,
          enterpriseId: enterpriseId,
          userId: userId,
          nameText: nameText,
          phoneText: phoneText,
          notesText: notesText,
        ),
      );

      if (!mounted) return;

      if (photo != null) {
        final selectedChatGroupIds =
            share ? _selectedGroupIds.toList() : const <String>[];

        final groupCount = selectedChatGroupIds.length;
        final successMsg = groupCount > 0
            ? 'Photo queued. It will share to $groupCount group${groupCount > 1 ? 's' : ''} after upload.'
            : 'Photo upload started.';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(successMsg),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
        await _cleanupPreparedImageIfNeeded();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(photoProvider.error ?? 'Failed to save photo'),
            backgroundColor: AppColors.critical,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
        setState(() => _isSaving = false);
        return;
      }
    } else {
      // No image file (camera not yet integrated)
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _imagePreparationError ??
                'This photo is no longer available. Please retake it and try again.',
          ),
          backgroundColor: AppColors.critical,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      setState(() => _isSaving = false);
      return;
    }

    if (mounted) {
      // Pop both preview and camera to return directly to gallery
      final navigator = Navigator.of(context, rootNavigator: true);
      navigator.pop(); // Pop preview
      navigator.pop(); // Pop camera → reveals gallery shell
    }
  }

  Map<String, dynamic>? _buildQueuedFollowUpTask({
    required AuthProvider authProvider,
    required String enterpriseId,
    required String userId,
    required String nameText,
    required String phoneText,
    required String notesText,
  }) {
    if (!_createFollowUp || _dueDate == null) {
      return null;
    }

    final now = DateTime.now();
    return {
      'enterpriseId': enterpriseId,
      'title': 'Follow-up: ${nameText.isNotEmpty ? nameText : _category}',
      'description': notesText.isNotEmpty ? notesText : null,
      'type': 'followup',
      'priority': 'medium',
      'status': 'pending',
      'assignedTo': userId,
      'assignedBy': userId,
      'assignedByName': authProvider.currentUser?.name,
      'dueDateMs': _dueDate!.millisecondsSinceEpoch,
      'contactType': '$_customerType $_category',
      'contactPhone': phoneText.isNotEmpty ? phoneText : null,
      'sendNotification': true,
      'createdAtMs': now.millisecondsSinceEpoch,
      'updatedAtMs': now.millisecondsSinceEpoch,
    };
  }

  String? _buildQueuedShareCaption({
    required GroupProvider groupProvider,
    required String? defaultGroupId,
    required String nameText,
    required String phoneText,
    required String notesText,
  }) {
    if (!_shareToGroupChats || _selectedGroupIds.isEmpty) {
      return null;
    }

    final captionParts = <String>[];
    if (_category.isNotEmpty) {
      captionParts.add(
        'Category: ${_category[0].toUpperCase()}${_category.substring(1)}',
      );
    }
    if (_customerType.isNotEmpty) {
      captionParts.add(
        'Customer: ${_customerType[0].toUpperCase()}${_customerType.substring(1)}',
      );
    }
    if (nameText.isNotEmpty) captionParts.add('Name: $nameText');
    if (phoneText.isNotEmpty) captionParts.add('Phone: $phoneText');
    if (widget.location.isNotEmpty) {
      captionParts.add('Location: ${widget.location}');
    }
    if (defaultGroupId != null) {
      final groupName = groupProvider.groups
          .where((g) => g.id == defaultGroupId)
          .map((g) => g.name)
          .firstOrNull;
      if (groupName != null) captionParts.add('Group: $groupName');
    }
    if (notesText.isNotEmpty) captionParts.add('Notes: $notesText');

    return captionParts.isNotEmpty ? captionParts.join('\n') : null;
  }

  String _formatDate(DateTime date) {
    final months = [
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
    return '${date.day} ${months[date.month - 1]}';
  }

  String _formatFullPreviewTimestamp(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString().substring(2);
    final hour =
        date.hour > 12 ? date.hour - 12 : (date.hour == 0 ? 12 : date.hour);
    final hourStr = hour.toString().padLeft(2, '0');
    final min = date.minute.toString().padLeft(2, '0');
    final amPm = date.hour >= 12 ? 'PM' : 'AM';
    final offset = date.timeZoneOffset;
    final offsetHours = offset.inHours.abs().toString().padLeft(2, '0');
    final offsetMins =
        (offset.inMinutes.remainder(60)).abs().toString().padLeft(2, '0');
    final sign = offset.isNegative ? '-' : '+';
    return '$day/$month/$year $hourStr:$min $amPm GMT $sign$offsetHours:$offsetMins';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              const AppHeader(
                title: 'Photo Preview',
                type: AppHeaderType.secondary,
                showAvatar: false,
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.lg,
                    140,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildPhotoPreview(),
                      const SizedBox(height: AppSpacing.xxl),
                      _buildMetadataCard(),
                      const SizedBox(height: AppSpacing.lg),
                      _buildFollowUpCard(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomSheet: _buildBottomActions(),
    );
  }

  Widget _buildPhotoPreview() {
    final preparedImagePath = _preparedImagePath;
    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: Container(
        height: 360,
        decoration: BoxDecoration(
          color: AppColors.glassStrong,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: AppColors.glassBorder),
          boxShadow: AppShadows.glass,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_isPreparingImage)
              Container(
                color: AppColors.glassPrimary,
                child: const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.primary,
                  ),
                ),
              )
            else if (preparedImagePath != null && preparedImagePath.isNotEmpty)
              Image.file(
                File(preparedImagePath),
                fit: BoxFit.cover,
                alignment: Alignment.bottomCenter,
              )
            else
              Container(
                color: AppColors.glassPrimary,
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          AppIcons.image,
                          color: AppColors.textTertiary,
                          size: 48,
                        ),
                        SizedBox(height: 12),
                        Text(
                          _imagePreparationError ??
                              'Photo preview unavailable.',
                          textAlign: TextAlign.center,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    AppColors.gradientStart.withValues(alpha: 0.8),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 28,
              child: _buildPreviewGeoTagCard(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewGeoTagCard() {
    final sessionProvider = context.watch<SessionProvider>();
    final latitude = sessionProvider.currentLat;
    final longitude = sessionProvider.currentLng;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 320),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  AppIcons.location,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.location,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodyMedium.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Lat ${latitude.toStringAsFixed(5)}  •  Lng ${longitude.toStringAsFixed(5)}',
                      style: AppTypography.small.copyWith(
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _formatFullPreviewTimestamp(widget.timestamp),
                      style: AppTypography.small.copyWith(
                        color: Colors.white.withValues(alpha: 0.72),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetadataCard() {
    final chatProvider = context.watch<ChatProvider>();
    final authProvider = context.watch<AuthProvider>();
    final groupProvider = context.watch<GroupProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _refreshFallbackChatGroups();
      }
    });
    final sendableGroups =
        _sendableChatGroups(chatProvider, authProvider, groupProvider);
    _scheduleInitialShareDialogIfNeeded(sendableGroups);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.glassBorder.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Photo Details',
            style: AppTypography.bodyLarge.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Keep the photo front and center, then add only what matters.',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
          Text('Customer Type', style: AppTypography.label),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildToggleChip('New', 'new'),
              const SizedBox(width: 10),
              _buildToggleChip('Old', 'old'),
            ],
          ),
          const SizedBox(height: 16),
          Text('Category', style: AppTypography.label),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildCategoryChip('Distributor', 'distributor'),
              const SizedBox(width: 10),
              _buildCategoryChip('Farmer', 'farmer'),
            ],
          ),
          const SizedBox(height: 16),
          _buildFilledTextField(
            label: 'Full Name',
            hint: 'Enter name',
            controller: _nameController,
            prefixIcon: AppIcons.user,
            focusNode: _nameFocusNode,
            onChanged: _onNameChanged,
          ),
          if (_isLoadingSuggestions ||
              (_nameFocusNode.hasFocus &&
                  _nameController.text.trim().isNotEmpty &&
                  (_nameSuggestions.isNotEmpty ||
                      _hasSearchedSuggestions))) ...[
            const SizedBox(height: 8),
            _buildNameSuggestions(),
          ],
          const SizedBox(height: 14),
          _buildFilledTextField(
            label: 'Phone Number',
            hint: '00000 00000',
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            prefixIcon: AppIcons.call,
          ),
          const SizedBox(height: 14),
          _buildFilledTextField(
            label: 'Notes',
            hint: 'Add field observations...',
            controller: _notesController,
            prefixIcon: AppIcons.note,
            maxLines: 3,
          ),
          if (sendableGroups.isNotEmpty) ...[
            const SizedBox(height: 18),
            _buildShareToGroupsSection(sendableGroups),
          ],
        ],
      ),
    );
  }

  Widget _buildFollowUpCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: AppColors.glassBorder.withValues(alpha: 0.45)),
      ),
      child: Column(
        children: [
          SwitchListTile.adaptive(
            value: _createFollowUp,
            onChanged: (v) => setState(() => _createFollowUp = v),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            activeThumbColor: AppColors.primary,
            activeTrackColor: AppColors.primary.withValues(alpha: 0.3),
            title: Text(
              'Schedule Follow-up',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: Text(
              'Add a task for this customer after the photo syncs.',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          if (_createFollowUp) ...[
            Divider(
              height: 1,
              color: AppColors.glassBorder.withValues(alpha: 0.55),
            ),
            GestureDetector(
              onTap: _selectDueDate,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Icon(
                      AppIcons.calendar,
                      color: AppColors.textSecondary,
                      size: 18,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Text(
                      _dueDate != null ? _formatDate(_dueDate!) : 'Select date',
                      style: AppTypography.bodyMedium.copyWith(
                        color: _dueDate != null
                            ? AppColors.textPrimary
                            : AppColors.textTertiary,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      AppIcons.arrow_right_2,
                      color: AppColors.textTertiary,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildShareToGroupsSection(List<ChatGroupModel> sendableGroups) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: AppColors.glassBorder.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile.adaptive(
            value: _shareToGroupChats,
            onChanged: (value) {
              setState(() {
                _shareToGroupChats = value;
                if (!value) {
                  _selectedGroupIds.clear();
                }
              });
            },
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            activeThumbColor: AppColors.primary,
            activeTrackColor: AppColors.primary.withValues(alpha: 0.3),
            title: Text(
              'Also Share in Group Chat',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: Text(
              _selectedGroupIds.isEmpty
                  ? 'Optional'
                  : '${_selectedGroupIds.length} groups selected',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          if (_shareToGroupChats) ...[
            Divider(
              height: 1,
              color: AppColors.glassBorder.withValues(alpha: 0.55),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: sendableGroups.map((group) {
                  final isSelected = _selectedGroupIds.contains(group.id);
                  return GlassChip(
                    label: group.name,
                    selected: isSelected,
                    icon: group.isBroadcast
                        ? AppIcons.volume_high
                        : AppIcons.people,
                    onTap: () {
                      setState(() {
                        if (isSelected) {
                          _selectedGroupIds.remove(group.id);
                        } else {
                          _selectedGroupIds.add(group.id);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilledTextField({
    required String label,
    required String hint,
    required TextEditingController controller,
    required IconData prefixIcon,
    TextInputType? keyboardType,
    FocusNode? focusNode,
    ValueChanged<String>? onChanged,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.label),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          focusNode: focusNode,
          onChanged: onChanged,
          keyboardType: keyboardType,
          maxLines: maxLines,
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: AppTypography.bodySmall.copyWith(
              color: AppColors.textTertiary,
            ),
            prefixIcon: Icon(
              prefixIcon,
              size: 18,
              color: AppColors.textSecondary,
            ),
            filled: true,
            fillColor: const Color(0xFFF5F6FA),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: AppColors.primary.withValues(alpha: 0.18),
              ),
            ),
            contentPadding: EdgeInsets.symmetric(
              horizontal: 16,
              vertical: maxLines > 1 ? 16 : 14,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomActions() {
    return Container(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        bottom: MediaQuery.of(context).padding.bottom + AppSpacing.md,
        top: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.glassNav,
        border: Border(top: BorderSide(color: AppColors.glassBorder)),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => context.pop(),
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.glassPrimary,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: AppColors.glassBorder),
                ),
                child: Center(
                  child: Text(
                    'Retake',
                    style: AppTypography.buttonMedium.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: _isSaving || _isPreparingImage
                  ? null
                  : () => _savePhoto(
                        share:
                            _shareToGroupChats && _selectedGroupIds.isNotEmpty,
                      ),
              child: Opacity(
                opacity: (_isSaving || _isPreparingImage) ? 0.6 : 1.0,
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.35),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_isSaving)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      else ...[
                        const Icon(
                          AppIcons.cloud_add,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Upload',
                          style: AppTypography.buttonMedium.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleChip(String label, String value) {
    final isSelected = _customerType == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _customerType = value),
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

  Widget _buildCategoryChip(String label, String value) {
    final isSelected = _category == value;
    return GlassChip(
      label: label,
      selected: isSelected,
      onTap: () {
        if (_category == value) return;
        setState(() {
          _category = value;
          _nameSuggestions = const [];
          _hasSearchedSuggestions = false;
        });
        if (_nameController.text.trim().isNotEmpty) {
          _scheduleSuggestionSearch(_nameController.text);
        }
      },
    );
  }

  void _onNameChanged(String value) {
    _scheduleSuggestionSearch(value);
  }

  void _scheduleSuggestionSearch(String rawQuery) {
    _suggestionDebounce?.cancel();
    final query = rawQuery.trim();

    if (query.isEmpty) {
      if (mounted) {
        setState(() {
          _nameSuggestions = const [];
          _hasSearchedSuggestions = false;
          _isLoadingSuggestions = false;
        });
      }
      return;
    }

    _suggestionDebounce = Timer(const Duration(milliseconds: 220), () {
      _loadSuggestions(query);
    });
  }

  Future<void> _loadSuggestions(String query) async {
    final authProvider = context.read<AuthProvider>();
    final employeeId = authProvider.currentUser?.id ?? '';
    if (employeeId.isEmpty) return;

    if (mounted) {
      setState(() {
        _isLoadingSuggestions = true;
        _hasSearchedSuggestions = true;
      });
    }

    final cacheKey = '$employeeId|$_category';
    var candidates = _suggestionCache[cacheKey];
    if (candidates == null) {
      candidates = await _photoRepository.getRecentCustomerSuggestions(
        employeeId: employeeId,
        category: _category,
      );
      _suggestionCache[cacheKey] = candidates;
    }

    final normalizedQuery = _normalizeSearch(query);
    final filtered = candidates
        .where((candidate) {
          return candidate.normalizedName.contains(normalizedQuery) ||
              candidate.normalizedPhone.contains(normalizedQuery);
        })
        .take(6)
        .toList();

    if (!mounted) return;
    if (_normalizeSearch(_nameController.text) != normalizedQuery ||
        !_nameFocusNode.hasFocus) {
      return;
    }

    setState(() {
      _nameSuggestions = filtered;
      _isLoadingSuggestions = false;
    });
  }

  String _normalizeSearch(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  Widget _buildNameSuggestions() {
    if (_isLoadingSuggestions) {
      return _buildSuggestionContainer(
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primary,
              ),
            ),
          ),
        ),
      );
    }

    if (_nameSuggestions.isEmpty) {
      return _buildSuggestionContainer(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Text(
            'No previous ${_category == 'farmer' ? 'farmers' : 'distributors'} found for this name yet.',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
        ),
      );
    }

    return _buildSuggestionContainer(
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _nameSuggestions.length,
        separatorBuilder: (_, __) => Divider(
          height: 1,
          color: AppColors.glassBorder.withValues(alpha: 0.7),
        ),
        itemBuilder: (context, index) {
          final suggestion = _nameSuggestions[index];
          final subtitleParts = <String>[
            if (suggestion.customerPhone?.isNotEmpty == true)
              suggestion.customerPhone!,
            if (suggestion.location?.isNotEmpty == true) suggestion.location!,
            'Last seen ${_formatDate(suggestion.lastSeenAt)}',
          ];

          return ListTile(
            dense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            leading: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                AppIcons.user,
                size: 16,
                color: AppColors.primary,
              ),
            ),
            title: Text(
              suggestion.customerName,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              subtitleParts.join(' • '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.small.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            trailing: suggestion.customerType != null
                ? Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      suggestion.customerType![0].toUpperCase() +
                          suggestion.customerType!.substring(1),
                      style: AppTypography.small.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                : null,
            onTap: () => _applySuggestion(suggestion),
          );
        },
      ),
    );
  }

  Widget _buildSuggestionContainer({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.glassStrong,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.glassBorder),
          boxShadow: AppShadows.glass,
        ),
        child: child,
      ),
    );
  }

  void _applySuggestion(CustomerSuggestionModel suggestion) {
    setState(() {
      _nameController.text = suggestion.customerName;
      _nameController.selection = TextSelection.fromPosition(
        TextPosition(offset: _nameController.text.length),
      );
      if (suggestion.customerPhone?.isNotEmpty == true) {
        _phoneController.text = suggestion.customerPhone!;
      }
      if (suggestion.customerType?.isNotEmpty == true) {
        _customerType = suggestion.customerType!;
      }
      if (_notesController.text.trim().isEmpty &&
          suggestion.notes?.isNotEmpty == true) {
        _notesController.text = suggestion.notes!;
      }
      _nameSuggestions = const [];
      _hasSearchedSuggestions = false;
    });
    _nameFocusNode.unfocus();
  }
}
