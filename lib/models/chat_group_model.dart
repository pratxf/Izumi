import 'package:cloud_firestore/cloud_firestore.dart';

class ChatGroupModel {
  final String id;
  final String enterpriseId;
  final String name;
  final String description;
  final String? linkedGroupId; // optional link to operational group
  final String createdBy;
  final List<String> memberIds;
  final String mode; // "open" or "broadcast"
  final Map<String, dynamic>? lastMessage;
  final DateTime? lastMessageAt;
  final Map<String, DateTime> lastReadAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ChatGroupModel({
    required this.id,
    required this.enterpriseId,
    required this.name,
    this.description = '',
    this.linkedGroupId,
    required this.createdBy,
    required this.memberIds,
    this.mode = 'open',
    this.lastMessage,
    this.lastMessageAt,
    this.lastReadAt = const {},
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isBroadcast => mode == 'broadcast';
  int get memberCount => memberIds.length;

  String get lastMessagePreview {
    if (lastMessage == null) return 'No messages yet';
    final type = lastMessage!['type'] as String? ?? 'text';
    switch (type) {
      case 'image':
        return '📷 Photo';
      case 'location':
        return '📍 Location';
      default:
        return lastMessage!['text'] as String? ?? '';
    }
  }

  String? get lastMessageSenderName =>
      lastMessage?['senderName'] as String?;

  int unreadCount(String userId) {
    if (lastMessageAt == null) return 0;
    final userLastRead = lastReadAt[userId];
    if (userLastRead == null) return 1; // treat as unread if never read
    return lastMessageAt!.isAfter(userLastRead) ? 1 : 0;
  }

  factory ChatGroupModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    // Parse lastReadAt map of timestamps
    final rawLastRead = data['lastReadAt'] as Map<String, dynamic>? ?? {};
    final lastReadAt = <String, DateTime>{};
    for (final entry in rawLastRead.entries) {
      if (entry.value is Timestamp) {
        lastReadAt[entry.key] = (entry.value as Timestamp).toDate();
      }
    }

    return ChatGroupModel(
      id: doc.id,
      enterpriseId: data['enterpriseId'] as String? ?? '',
      name: data['name'] as String? ?? '',
      description: data['description'] as String? ?? '',
      linkedGroupId: data['linkedGroupId'] as String?,
      createdBy: data['createdBy'] as String? ?? '',
      memberIds: List<String>.from(data['memberIds'] ?? []),
      mode: data['mode'] as String? ?? 'open',
      lastMessage: data['lastMessage'] as Map<String, dynamic>?,
      lastMessageAt: data['lastMessageAt'] != null
          ? (data['lastMessageAt'] as Timestamp).toDate()
          : null,
      lastReadAt: lastReadAt,
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      updatedAt: data['updatedAt'] != null
          ? (data['updatedAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    final lastReadTimestamps = <String, Timestamp>{};
    for (final entry in lastReadAt.entries) {
      lastReadTimestamps[entry.key] = Timestamp.fromDate(entry.value);
    }

    return {
      'enterpriseId': enterpriseId,
      'name': name,
      'description': description,
      if (linkedGroupId != null) 'linkedGroupId': linkedGroupId,
      'createdBy': createdBy,
      'memberIds': memberIds,
      'mode': mode,
      if (lastMessage != null) 'lastMessage': lastMessage,
      if (lastMessageAt != null)
        'lastMessageAt': Timestamp.fromDate(lastMessageAt!),
      'lastReadAt': lastReadTimestamps,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  ChatGroupModel copyWith({
    String? id,
    String? enterpriseId,
    String? name,
    String? description,
    String? linkedGroupId,
    String? createdBy,
    List<String>? memberIds,
    String? mode,
    Map<String, dynamic>? lastMessage,
    DateTime? lastMessageAt,
    Map<String, DateTime>? lastReadAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ChatGroupModel(
      id: id ?? this.id,
      enterpriseId: enterpriseId ?? this.enterpriseId,
      name: name ?? this.name,
      description: description ?? this.description,
      linkedGroupId: linkedGroupId ?? this.linkedGroupId,
      createdBy: createdBy ?? this.createdBy,
      memberIds: memberIds ?? this.memberIds,
      mode: mode ?? this.mode,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      lastReadAt: lastReadAt ?? this.lastReadAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
