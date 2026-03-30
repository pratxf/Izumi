import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/chat_group_model.dart';
import '../models/chat_message_model.dart';
import '../services/firestore_service.dart';
import '../services/storage_service.dart';

class ChatRepository {
  final FirestoreService _firestoreService = FirestoreService();
  final StorageService _storageService = StorageService();
  static const String _collection = 'chatGroups';
  static const String _messagesSubcollection = 'messages';
  static const int _messagePageSize = 50;

  // ── Chat Group CRUD ─────────────────────────────────────────────────

  Future<String> createChatGroup(ChatGroupModel group) async {
    final docRef = await _firestoreService.addDocument(
      _collection,
      group.toFirestore(),
    );
    return docRef.id;
  }

  Future<void> updateChatGroup(
      String groupId, Map<String, dynamic> data) async {
    data['updatedAt'] = Timestamp.fromDate(DateTime.now());
    await _firestoreService.updateDocument(_collection, groupId, data);
  }

  Future<void> deleteChatGroup(String groupId) async {
    await _firestoreService.deleteDocument(_collection, groupId);
  }

  Future<ChatGroupModel?> getChatGroup(String groupId) async {
    final doc = await _firestoreService.getDocument(_collection, groupId);
    if (!doc.exists) return null;
    return ChatGroupModel.fromFirestore(doc);
  }

  Future<ChatGroupModel?> getChatGroupByLinkedGroupId(String linkedGroupId) async {
    final snapshot = await _firestoreService.getCollection(
      _collection,
      filters: [
        QueryFilter('linkedGroupId', FilterOp.isEqualTo, linkedGroupId),
      ],
      limit: 1,
    );
    if (snapshot.docs.isEmpty) return null;
    return ChatGroupModel.fromFirestore(snapshot.docs.first);
  }

  Future<ChatGroupModel?> getChatGroupByEnterpriseAndName({
    required String enterpriseId,
    required String name,
  }) async {
    final snapshot = await _firestoreService.getCollection(
      _collection,
      filters: [
        QueryFilter('enterpriseId', FilterOp.isEqualTo, enterpriseId),
        QueryFilter('name', FilterOp.isEqualTo, name),
      ],
      limit: 1,
    );
    if (snapshot.docs.isEmpty) return null;
    return ChatGroupModel.fromFirestore(snapshot.docs.first);
  }

  Future<List<ChatGroupModel>> getChatGroupsByLinkedGroupIds({
    required String enterpriseId,
    required List<String> linkedGroupIds,
  }) async {
    final normalizedIds = linkedGroupIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (normalizedIds.isEmpty) return const [];

    final results = <ChatGroupModel>[];
    for (var i = 0; i < normalizedIds.length; i += 10) {
      final batch = normalizedIds.sublist(
        i,
        i + 10 > normalizedIds.length ? normalizedIds.length : i + 10,
      );
      final snapshot = await _firestoreService.getCollection(
        _collection,
        filters: [
          QueryFilter('enterpriseId', FilterOp.isEqualTo, enterpriseId),
          QueryFilter('linkedGroupId', FilterOp.whereIn, batch),
        ],
      );
      results.addAll(
        snapshot.docs.map((doc) => ChatGroupModel.fromFirestore(doc)).toList(),
      );
    }

    final uniqueById = <String, ChatGroupModel>{};
    for (final group in results) {
      uniqueById[group.id] = group;
    }
    return uniqueById.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  // ── Chat Group Streams ──────────────────────────────────────────────

  Stream<List<ChatGroupModel>> streamChatGroups(
      String enterpriseId, String userId, {bool isAdmin = false}) {
    final filters = <QueryFilter>[
      QueryFilter('enterpriseId', FilterOp.isEqualTo, enterpriseId),
    ];
    if (!isAdmin) {
      filters.add(QueryFilter('memberIds', FilterOp.arrayContains, userId));
    }
    return _firestoreService
        .streamCollection(
          _collection,
          filters: filters,
          orderBy: 'updatedAt',
          descending: true,
        )
        .map((snapshot) => snapshot.docs
            .map((doc) => ChatGroupModel.fromFirestore(doc))
            .toList());
  }

  // ── Messages ────────────────────────────────────────────────────────

  Stream<List<ChatMessageModel>> streamMessages(String groupId,
      {int limit = _messagePageSize}) {
    final db = _firestoreService.instance;
    return db
        .collection(_collection)
        .doc(groupId)
        .collection(_messagesSubcollection)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => ChatMessageModel.fromFirestore(doc))
            .toList());
  }

  Future<List<ChatMessageModel>> loadMoreMessages(
    String groupId, {
    required DateTime beforeTimestamp,
    int limit = _messagePageSize,
  }) async {
    final db = _firestoreService.instance;
    final snapshot = await db
        .collection(_collection)
        .doc(groupId)
        .collection(_messagesSubcollection)
        .orderBy('createdAt', descending: true)
        .startAfter([Timestamp.fromDate(beforeTimestamp)])
        .limit(limit)
        .get();

    return snapshot.docs
        .map((doc) => ChatMessageModel.fromFirestore(doc))
        .toList();
  }

  Future<void> sendMessage(
    String groupId,
    ChatMessageModel message, {
    String? documentId,
  }) async {
    final db = _firestoreService.instance;
    final messagesRef = db
        .collection(_collection)
        .doc(groupId)
        .collection(_messagesSubcollection);
    if (documentId != null) {
      await messagesRef.doc(documentId).set(message.toFirestore());
    } else {
      await messagesRef.add(message.toFirestore());
    }
  }

  // ── Delete Message ──────────────────────────────────────────────────

  Future<void> deleteMessage(String groupId, String messageId) async {
    final db = _firestoreService.instance;
    await db
        .collection(_collection)
        .doc(groupId)
        .collection(_messagesSubcollection)
        .doc(messageId)
        .update({
      'isDeleted': true,
      'text': null,
      'imageUrl': null,
      'thumbnailUrl': null,
      'caption': null,
    });

    await _refreshLastMessage(groupId);
  }

  Future<void> _refreshLastMessage(String groupId) async {
    final db = _firestoreService.instance;
    final recentMessages = await db
        .collection(_collection)
        .doc(groupId)
        .collection(_messagesSubcollection)
        .orderBy('createdAt', descending: true)
        .limit(25)
        .get();

    QueryDocumentSnapshot<Map<String, dynamic>>? latestVisibleDoc;
    for (final doc in recentMessages.docs) {
      if ((doc.data()['isDeleted'] as bool?) != true) {
        latestVisibleDoc = doc;
        break;
      }
    }

    if (latestVisibleDoc == null) {
      await db.collection(_collection).doc(groupId).update({
        'lastMessage': null,
        'lastMessageAt': null,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
      return;
    }

    final data = latestVisibleDoc.data();
    final type = data['type'] as String? ?? 'text';
    String previewText;
    switch (type) {
      case 'image':
        previewText = 'Sent a photo';
        break;
      case 'location':
        previewText = 'Shared a location';
        break;
      default:
        previewText = data['text'] as String? ?? '';
        break;
    }

    final createdAt = data['createdAt'] as Timestamp?;
    await db.collection(_collection).doc(groupId).update({
      'lastMessage': {
        'text': previewText,
        'senderId': data['senderId'],
        'senderName': data['senderName'],
        'type': type,
        if (createdAt != null) 'timestamp': createdAt,
      },
      'lastMessageAt': createdAt,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  // ── Read Tracking ───────────────────────────────────────────────────

  Future<void> updateLastRead(String groupId, String userId) async {
    await _firestoreService.updateDocument(_collection, groupId, {
      'lastReadAt.$userId': Timestamp.fromDate(DateTime.now()),
    });
  }

  // ── Image Upload ────────────────────────────────────────────────────

  Future<String> uploadChatImage({
    required String enterpriseId,
    required String groupId,
    required File file,
  }) async {
    return await _storageService.uploadChatImage(
      enterpriseId: enterpriseId,
      groupId: groupId,
      file: file,
    );
  }
}
