import 'package:cloud_firestore/cloud_firestore.dart';

class ActivityLogModel {
  final String id;
  final String enterpriseId;
  final String employeeId;
  final String? sessionId;
  final String type; // 'location_update' | 'task_started' | 'task_completed' | 'photo_captured' | 'session_started' | 'session_ended' | 'break'
  final String title;
  final String detail;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;

  const ActivityLogModel({
    required this.id,
    required this.enterpriseId,
    required this.employeeId,
    this.sessionId,
    required this.type,
    required this.title,
    required this.detail,
    required this.timestamp,
    this.metadata,
  });

  String get formattedTime {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String get timeAgo {
    final now = DateTime.now();
    final diff = now.difference(timestamp);

    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
  }

  factory ActivityLogModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ActivityLogModel(
      id: doc.id,
      enterpriseId: data['enterpriseId'] ?? '',
      employeeId: data['employeeId'] ?? '',
      sessionId: data['sessionId'],
      type: data['type'] ?? '',
      title: data['title'] ?? '',
      detail: data['detail'] ?? '',
      timestamp:
          (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      metadata: data['metadata'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'enterpriseId': enterpriseId,
      'employeeId': employeeId,
      'sessionId': sessionId,
      'type': type,
      'title': title,
      'detail': detail,
      'timestamp': Timestamp.fromDate(timestamp),
      'metadata': metadata,
    };
  }

  ActivityLogModel copyWith({
    String? id,
    String? enterpriseId,
    String? employeeId,
    String? sessionId,
    String? type,
    String? title,
    String? detail,
    DateTime? timestamp,
    Map<String, dynamic>? metadata,
  }) {
    return ActivityLogModel(
      id: id ?? this.id,
      enterpriseId: enterpriseId ?? this.enterpriseId,
      employeeId: employeeId ?? this.employeeId,
      sessionId: sessionId ?? this.sessionId,
      type: type ?? this.type,
      title: title ?? this.title,
      detail: detail ?? this.detail,
      timestamp: timestamp ?? this.timestamp,
      metadata: metadata ?? this.metadata,
    );
  }
}
