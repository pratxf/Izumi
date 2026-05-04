import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../offline_queue/offline_job.dart';
import '../offline_queue/offline_job_store.dart';
import '../offline_queue/offline_queue_manager.dart';
import '../models/chat_group_model.dart';
import '../models/chat_message_model.dart';
import '../models/upload_status.dart';
import '../repositories/chat_repository.dart';
import '../services/location_service.dart';

class ChatProvider extends ChangeNotifier {
  final ChatRepository _chatRepo = ChatRepository();
  final LocationService _locationService = LocationService();
  final OfflineJobStore _offlineJobStore = OfflineJobStore.instance;
  final OfflineQueueManager _offlineQueueManager = OfflineQueueManager.instance;

  List<ChatGroupModel> _chatGroups = [];
  List<ChatMessageModel> _messages = [];
  bool _isLoading = false;
  bool _isSending = false;
  bool _hasMoreMessages = true;
  String? _error;
  String? _activeChatGroupId;
  StreamSubscription? _groupsSubscription;
  StreamSubscription? _messagesSubscription;
  String? _streamingEnterpriseId;
  String? _streamingUserId;
  final Map<String, ChatMessageModel> _optimisticMessagesByRequestId = {};
  final Map<String, String> _optimisticMessageGroupIds = {};
  StreamSubscription<OfflineQueueJobEvent>? _queueEventsSubscription;

  ChatProvider() {
    unawaited(_initializeOfflineQueue());
  }

  // Public getters
  List<ChatGroupModel> get chatGroups => _chatGroups;
  List<ChatMessageModel> get messages => _messages;
  bool get isLoading => _isLoading;
  bool get isSending => _isSending;
  bool get hasMoreMessages => _hasMoreMessages;
  String? get error => _error;
  String? get activeChatGroupId => _activeChatGroupId;

  ChatGroupModel? get activeChatGroup {
    if (_activeChatGroupId == null) return null;
    try {
      return _chatGroups.firstWhere((g) => g.id == _activeChatGroupId);
    } catch (_) {
      return null;
    }
  }

  Future<void> _initializeOfflineQueue() async {
    await _offlineQueueManager.start();
    await _queueEventsSubscription?.cancel();
    _queueEventsSubscription = _offlineQueueManager.events.listen(
      _handleQueueEvent,
    );
  }

  int totalUnreadCount(String userId) {
    int count = 0;
    for (final group in _chatGroups) {
      count += group.unreadCount(userId);
    }
    return count;
  }

  /// Returns true if both group lists represent the same visible state,
  /// so we can skip unnecessary notifyListeners calls.
  bool _chatGroupsEqual(List<ChatGroupModel> a, List<ChatGroupModel> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].name != b[i].name ||
          a[i].lastMessageAt != b[i].lastMessageAt ||
          a[i].lastMessage?['text'] != b[i].lastMessage?['text'] ||
          a[i].memberIds.length != b[i].memberIds.length) {
        return false;
      }
    }
    return true;
  }

  // ── Chat Groups ─────────────────────────────────────────────────────

  void streamChatGroups(String enterpriseId, String userId,
      {bool isAdmin = false}) {
    // Skip if already streaming for the same enterprise/user
    if (_streamingEnterpriseId == enterpriseId &&
        _streamingUserId == userId &&
        _groupsSubscription != null) {
      return;
    }
    _streamingEnterpriseId = enterpriseId;
    _streamingUserId = userId;
    _groupsSubscription?.cancel();
    _groupsSubscription = _chatRepo
        .streamChatGroups(enterpriseId, userId, isAdmin: isAdmin)
        .listen(
      (groups) {
        if (_chatGroupsEqual(_chatGroups, groups)) return;
        _chatGroups = groups;
        _error = null;
        notifyListeners();
      },
      onError: (e) {
        debugPrint('[ChatProvider] streamChatGroups error: $e');
        _chatGroups = [];
        _error = e.toString();
        notifyListeners();
      },
    );
  }

  Future<String?> createChatGroup(ChatGroupModel group) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final groupId = await _chatRepo.createChatGroup(group);
      _isLoading = false;
      notifyListeners();
      return groupId;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  Future<bool> updateChatGroup(
      String groupId, Map<String, dynamic> data) async {
    _error = null;
    try {
      await _chatRepo.updateChatGroup(groupId, data);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteChatGroup(String groupId) async {
    _error = null;
    try {
      await _chatRepo.deleteChatGroup(groupId);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> syncMembersForLinkedGroup({
    required String linkedGroupId,
    required List<String> memberIds,
    List<String> extraMemberIds = const [],
    String? enterpriseId,
    String? groupName,
  }) async {
    try {
      var chatGroup =
          await _chatRepo.getChatGroupByLinkedGroupId(linkedGroupId);
      if (chatGroup == null &&
          enterpriseId != null &&
          groupName != null &&
          groupName.trim().isNotEmpty) {
        // Backfill older chat groups created before linkedGroupId existed.
        chatGroup = await _chatRepo.getChatGroupByEnterpriseAndName(
          enterpriseId: enterpriseId,
          name: groupName,
        );
      }
      if (chatGroup == null) return false;

      final normalizedMembers = <String>{
        ...memberIds.where((id) => id.trim().isNotEmpty),
        ...extraMemberIds.where((id) => id.trim().isNotEmpty),
        if (chatGroup.createdBy.trim().isNotEmpty) chatGroup.createdBy,
      }.toList();
      final alreadyLinked = chatGroup.linkedGroupId == linkedGroupId;
      if (alreadyLinked && listEquals(chatGroup.memberIds, normalizedMembers)) {
        return true;
      }

      await _chatRepo.updateChatGroup(chatGroup.id, {
        'linkedGroupId': linkedGroupId,
        'memberIds': normalizedMembers,
      });
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<List<ChatGroupModel>> getLinkedChatGroups({
    required String enterpriseId,
    required List<String> linkedGroupIds,
  }) async {
    try {
      return await _chatRepo.getChatGroupsByLinkedGroupIds(
        enterpriseId: enterpriseId,
        linkedGroupIds: linkedGroupIds,
      );
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return const [];
    }
  }

  // ── Messages ────────────────────────────────────────────────────────

  /// Older messages fetched via pagination, kept separate so the
  /// real-time stream doesn't wipe them out.
  List<ChatMessageModel> _paginatedMessages = [];

  void openChat(String groupId) {
    // Skip if already streaming this group (prevents flicker on re-tap)
    if (_activeChatGroupId == groupId && _messagesSubscription != null) {
      return;
    }

    _activeChatGroupId = groupId;
    _messages = [];
    _paginatedMessages = [];
    _hasMoreMessages = true;
    _error = null;
    _messagesSubscription?.cancel();

    _messagesSubscription = _chatRepo.streamMessages(groupId).listen(
      (streamMessages) {
        _error = null;
        final streamedRequestIds = streamMessages
            .map((message) => message.clientRequestId)
            .whereType<String>()
            .toSet();
        _optimisticMessagesByRequestId.removeWhere(
          (requestId, _) {
            final shouldRemove = streamedRequestIds.contains(requestId);
            if (shouldRemove) {
              _optimisticMessageGroupIds.remove(requestId);
            }
            return shouldRemove;
          },
        );
        if (streamMessages.length < 50) {
          _hasMoreMessages = _paginatedMessages.isNotEmpty;
        }

        // Merge: stream messages (newest 50) + paginated older messages.
        // Remove any paginated messages that now appear in the stream
        // (e.g., user sent a message that just crossed the 50-boundary).
        final mergedMessages = _paginatedMessages.isNotEmpty
            ? [
                ...streamMessages,
                ..._paginatedMessages.where(
                  (message) => !streamMessages.any((m) => m.id == message.id),
                ),
              ]
            : [...streamMessages];

        final optimisticMessages = _optimisticMessagesByRequestId.values
            .where(
              (message) =>
                  message.clientRequestId != null &&
                  _optimisticMessageGroupIds[message.clientRequestId!] ==
                      groupId,
            )
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

        if (mergedMessages.isNotEmpty) {
          final mergedIds = mergedMessages.map((m) => m.id).toSet();
          final mergedRequestIds = mergedMessages
              .map((m) => m.clientRequestId)
              .whereType<String>()
              .toSet();
          final pendingOptimistic = optimisticMessages.where(
            (message) =>
                !mergedIds.contains(message.id) &&
                (message.clientRequestId == null ||
                    !mergedRequestIds.contains(message.clientRequestId)),
          );
          _messages = [...pendingOptimistic, ...mergedMessages]
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        } else {
          _messages = optimisticMessages;
        }
        notifyListeners();
      },
      onError: (e) {
        debugPrint('[ChatProvider] streamMessages error: $e');
        _error = e.toString();
        // Don't clear messages on transient errors — keep showing what we have
        notifyListeners();
      },
    );

    unawaited(_hydrateQueuedMessages(groupId));
  }

  void closeChat() {
    _messagesSubscription?.cancel();
    _messagesSubscription = null;
    _activeChatGroupId = null;
    _messages = [];
    _paginatedMessages = [];
    _hasMoreMessages = true;
  }

  Future<void> _hydrateQueuedMessages(String groupId) async {
    final queuedJobs = await _offlineJobStore.getJobsByStatuses(
      const [
        OfflineJobStatus.pending,
        OfflineJobStatus.processing,
        OfflineJobStatus.error,
      ],
    );

    for (final job in queuedJobs) {
      if (job.type != OfflineJobType.chat) {
        continue;
      }
      final payloadGroupId = job.payload['groupId']?.toString();
      if (payloadGroupId != groupId) {
        continue;
      }
      _optimisticMessageGroupIds[job.id] = groupId;
      _optimisticMessagesByRequestId[job.id] = _queuedMessageFromJob(job);
    }

    final streamedIds = _messages.map((message) => message.id).toSet();
    final streamedRequestIds = _messages
        .map((message) => message.clientRequestId)
        .whereType<String>()
        .toSet();
    final queuedMessages = _optimisticMessagesByRequestId.values
        .where(
          (message) =>
              message.clientRequestId != null &&
              _optimisticMessageGroupIds[message.clientRequestId!] == groupId &&
              !streamedIds.contains(message.id) &&
              !streamedRequestIds.contains(message.clientRequestId),
        )
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    _messages = [...queuedMessages, ..._messages]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    notifyListeners();
  }

  Future<void> loadMoreMessages() async {
    if (!_hasMoreMessages || _isLoading || _messages.isEmpty) return;

    _isLoading = true;
    notifyListeners();

    try {
      final oldestMessage = _messages.last;
      final olderMessages = await _chatRepo.loadMoreMessages(
        _activeChatGroupId!,
        beforeTimestamp: oldestMessage.createdAt,
      );

      if (olderMessages.isEmpty) {
        _hasMoreMessages = false;
      } else {
        _paginatedMessages = [..._paginatedMessages, ...olderMessages];
        _messages = [..._messages, ...olderMessages];
      }
    } catch (e) {
      debugPrint('[ChatProvider] loadMoreMessages error: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  // ── Reply State ─────────────────────────────────────────────────────

  ChatMessageModel? _replyingTo;
  ChatMessageModel? get replyingTo => _replyingTo;

  void setReplyTo(ChatMessageModel message) {
    _replyingTo = message;
    notifyListeners();
  }

  void clearReply() {
    _replyingTo = null;
    notifyListeners();
  }

  // ── Delete Message ─────────────────────────────────────────────────

  Future<bool> deleteMessage(String groupId, String messageId) async {
    try {
      await _chatRepo.deleteMessage(groupId, messageId);
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  // ── Send Messages ───────────────────────────────────────────────────

  Future<bool> sendTextMessage({
    required String groupId,
    required String text,
    required String senderId,
    required String senderName,
  }) async {
    final reply = _replyingTo;
    final trimmedText = text.trim();
    final clientRequestId = _nextClientRequestId();
    final message = ChatMessageModel(
      id: 'local-$clientRequestId',
      clientRequestId: clientRequestId,
      senderId: senderId,
      senderName: senderName,
      type: 'text',
      text: trimmedText,
      createdAt: DateTime.now(),
      replyToId: reply?.id,
      replyToSenderName: reply?.senderName,
      replyToText: reply?.isImage == true ? null : reply?.text,
      replyToType: reply?.type,
      replyToImageUrl: reply?.isImage == true ? reply?.imageUrl : null,
      uploadStatus: UploadStatus.pending,
    );

    _optimisticMessagesByRequestId[clientRequestId] = message;
    _optimisticMessageGroupIds[clientRequestId] = groupId;
    _replyingTo = null;
    _messages = [message, ..._messages];
    notifyListeners();

    try {
      await _offlineJobStore.insertIfAbsent(
        OfflineJob(
          id: clientRequestId,
          type: OfflineJobType.chat,
          payload: {
            'groupId': groupId,
            'senderId': senderId,
            'senderName': senderName,
            'type': 'text',
            'text': trimmedText,
            'createdAtMs': message.createdAt.millisecondsSinceEpoch,
            if (reply?.id != null) 'replyToId': reply!.id,
            if (reply?.senderName != null)
              'replyToSenderName': reply!.senderName,
            if (reply?.isImage == true) 'replyToImageUrl': reply!.imageUrl,
            if (reply?.isImage != true && reply?.text != null)
              'replyToText': reply!.text,
            if (reply?.type != null) 'replyToType': reply!.type,
          },
          status: OfflineJobStatus.pending,
          retryCount: 0,
          createdAtMs: message.createdAt.millisecondsSinceEpoch,
          idempotencyKey: 'chat_$clientRequestId',
        ),
      );
      unawaited(_offlineQueueManager.processQueue(reason: 'chat_send'));
      return true;
    } catch (e) {
      _error = e.toString();
      _updateOptimisticMessageStatus(clientRequestId, UploadStatus.error);
      return false;
    }
  }

  Future<bool> sendImageMessage({
    required String groupId,
    required String enterpriseId,
    required File imageFile,
    required String senderId,
    required String senderName,
    String? caption,
    double? latitude,
    double? longitude,
    String? address,
  }) async {
    _isSending = true;
    notifyListeners();

    try {
      final reply = _replyingTo;
      final imageUrl = await _chatRepo.uploadChatImage(
        enterpriseId: enterpriseId,
        groupId: groupId,
        file: imageFile,
      );

      final message = ChatMessageModel(
        id: '',
        senderId: senderId,
        senderName: senderName,
        type: 'image',
        imageUrl: imageUrl,
        caption: caption,
        latitude: (latitude != null && latitude != 0.0) ? latitude : null,
        longitude: (longitude != null && longitude != 0.0) ? longitude : null,
        address: (address?.isNotEmpty == true) ? address : null,
        createdAt: DateTime.now(),
        replyToId: reply?.id,
        replyToSenderName: reply?.senderName,
        replyToText: reply?.isImage == true ? null : reply?.text,
        replyToType: reply?.type,
        replyToImageUrl: reply?.isImage == true ? reply?.imageUrl : null,
      );
      _replyingTo = null;
      await _chatRepo.sendMessage(groupId, message);
      _isSending = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _isSending = false;
      notifyListeners();
      return false;
    }
  }

  void retryTextMessage(String groupId, String clientRequestId) {
    final message = _optimisticMessagesByRequestId[clientRequestId];
    if (message == null) {
      return;
    }

    _optimisticMessageGroupIds[clientRequestId] = groupId;
    _updateOptimisticMessageStatus(clientRequestId, UploadStatus.pending);
    unawaited(_offlineQueueManager.retryJob(clientRequestId));
  }

  /// Send an image message using an already-uploaded URL (no re-upload).
  /// Used by "Share to Groups" on the preview screen.
  Future<bool> sendImageMessageFromUrl({
    required String groupId,
    required String imageUrl,
    String? thumbnailUrl,
    required String senderId,
    required String senderName,
    String? caption,
  }) async {
    try {
      final message = ChatMessageModel(
        id: '',
        senderId: senderId,
        senderName: senderName,
        type: 'image',
        imageUrl: imageUrl,
        thumbnailUrl: thumbnailUrl,
        caption: caption,
        createdAt: DateTime.now(),
      );
      await _chatRepo.sendMessage(groupId, message);
      return true;
    } catch (e) {
      debugPrint('[ChatProvider] sendImageMessageFromUrl error: $e');
      return false;
    }
  }

  Future<bool> sendLocationMessage({
    required String groupId,
    required String senderId,
    required String senderName,
  }) async {
    _isSending = true;
    notifyListeners();

    try {
      final position = await _locationService.getCurrentPosition();
      final address = await _locationService.getAddressFromCoordinates(
        position.latitude,
        position.longitude,
      );

      final message = ChatMessageModel(
        id: '',
        senderId: senderId,
        senderName: senderName,
        type: 'location',
        latitude: position.latitude,
        longitude: position.longitude,
        address: address,
        createdAt: DateTime.now(),
      );
      await _chatRepo.sendMessage(groupId, message);
      _isSending = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _isSending = false;
      notifyListeners();
      return false;
    }
  }

  // ── Read Tracking ───────────────────────────────────────────────────

  Future<void> markAsRead(String groupId, String userId) async {
    // Optimistic local update — blue dot disappears instantly
    final idx = _chatGroups.indexWhere((g) => g.id == groupId);
    if (idx != -1) {
      _chatGroups[idx] = _chatGroups[idx].copyWith(
        lastReadAt: {..._chatGroups[idx].lastReadAt, userId: DateTime.now()},
      );
      notifyListeners();
    }

    try {
      await _chatRepo.updateLastRead(groupId, userId);
    } catch (e) {
      debugPrint('[ChatProvider] markAsRead error: $e');
    }
  }

  // ── Cleanup ─────────────────────────────────────────────────────────

  @override
  void dispose() {
    _groupsSubscription?.cancel();
    _messagesSubscription?.cancel();
    _queueEventsSubscription?.cancel();
    super.dispose();
  }

  void _updateOptimisticMessageStatus(
    String clientRequestId,
    UploadStatus status,
  ) {
    final existing = _optimisticMessagesByRequestId[clientRequestId];
    if (existing == null) {
      return;
    }

    final updated = existing.copyWith(uploadStatus: status);
    _optimisticMessagesByRequestId[clientRequestId] = updated;
    _messages = _messages.map((message) {
      if (message.clientRequestId == clientRequestId) {
        return updated;
      }
      return message;
    }).toList();
    notifyListeners();
  }

  void _handleQueueEvent(OfflineQueueJobEvent event) {
    if (event.type != OfflineJobType.chat) {
      return;
    }

    final errorText = event.error?.toString();
    if (event.status == UploadStatus.error) {
      _error = errorText;
    }

    final existing = _optimisticMessagesByRequestId[event.jobId];
    final message = event.chatMessage;
    final alreadyMerged = _messages.any(
      (entry) => entry.clientRequestId == event.jobId,
    );
    if (message != null && (existing != null || !alreadyMerged)) {
      _optimisticMessagesByRequestId[event.jobId] = existing?.copyWith(
            uploadStatus: event.status,
            errorMessage: errorText,
          ) ??
          message.copyWith(
            uploadStatus: event.status,
            errorMessage: errorText,
          );
    }

    _updateOptimisticMessageStatus(event.jobId, event.status);
  }

  ChatMessageModel _queuedMessageFromJob(OfflineJob job) {
    final payload = job.payload;
    return ChatMessageModel(
      id: 'local-${job.id}',
      clientRequestId: job.id,
      senderId: payload['senderId']?.toString() ?? '',
      senderName: payload['senderName']?.toString() ?? '',
      type: payload['type']?.toString() ?? 'text',
      text: payload['text']?.toString(),
      imageUrl: payload['imageUrl']?.toString(),
      thumbnailUrl: payload['thumbnailUrl']?.toString(),
      latitude: (payload['latitude'] as num?)?.toDouble(),
      longitude: (payload['longitude'] as num?)?.toDouble(),
      address: payload['address']?.toString(),
      caption: payload['caption']?.toString(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (payload['createdAtMs'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
      ),
      replyToId: payload['replyToId']?.toString(),
      replyToSenderName: payload['replyToSenderName']?.toString(),
      replyToText: payload['replyToText']?.toString(),
      replyToType: payload['replyToType']?.toString(),
      replyToImageUrl: payload['replyToImageUrl']?.toString(),
      uploadStatus: job.status == OfflineJobStatus.error
          ? UploadStatus.error
          : UploadStatus.pending,
    );
  }

  String _nextClientRequestId() {
    return DateTime.now().microsecondsSinceEpoch.toString();
  }
}
