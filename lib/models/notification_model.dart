import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationModel {
  final String id;
  final String title;
  final String body;
  final String type; // 'task', 'location', 'system', 'report', 'alert'
  final bool isRead;
  final DateTime createdAt;
  final Map<String, dynamic> data; // deep-link metadata (action, taskId, etc.)

  const NotificationModel({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    this.isRead = false,
    required this.createdAt,
    this.data = const {},
  });

  factory NotificationModel.fromFirestore(DocumentSnapshot doc) {
    final raw = doc.data() as Map<String, dynamic>;
    return NotificationModel(
      id: doc.id,
      title: raw['title'] ?? '',
      body: raw['body'] ?? '',
      type: raw['type'] ?? 'system',
      isRead: raw['isRead'] ?? false,
      createdAt:
          (raw['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      data: (raw['data'] as Map<String, dynamic>?) ?? const {},
    );
  }

  bool get isToday {
    final now = DateTime.now();
    return createdAt.year == now.year &&
        createdAt.month == now.month &&
        createdAt.day == now.day;
  }

  String get timeAgo {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    return '${diff.inDays}d ago';
  }

  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'body': body,
      'type': type,
      'isRead': isRead,
      'data': data,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
