import 'package:cloud_firestore/cloud_firestore.dart';

class ActivityLogModel {
  final String id;
  final String enterpriseId;
  final String employeeId;
  final String? sessionId;
  final String? orgId;
  final String type; // 'location_update' | 'task_started' | 'task_completed' | 'photo_captured' | 'session_start' | 'session_end' | etc.
  final String title;
  final String detail;
  final DateTime timestamp;
  final String? date;
  final Map<String, dynamic>? metadata;
  final Map<String, dynamic>? payload;

  const ActivityLogModel({
    required this.id,
    required this.enterpriseId,
    required this.employeeId,
    this.sessionId,
    this.orgId,
    required this.type,
    required this.title,
    required this.detail,
    required this.timestamp,
    this.date,
    this.metadata,
    this.payload,
  });

  String get formattedTime {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String get formattedFeedTime {
    final hour = timestamp.hour % 12 == 0 ? 12 : timestamp.hour % 12;
    final minute = timestamp.minute.toString().padLeft(2, '0');
    final period = timestamp.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
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

  /// Normalises a raw Firestore document map to handle legacy field names
  /// and schema variations from historical migration data.
  static Map<String, dynamic> _normalise(
    String docId,
    Map<String, dynamic> data,
  ) {
    final normalised = Map<String, dynamic>.from(data);

    // Legacy field name mappings: snake_case → camelCase
    if (normalised.containsKey('employee_id') &&
        !normalised.containsKey('employeeId')) {
      normalised['employeeId'] = normalised['employee_id'];
    }
    if (normalised.containsKey('session_id') &&
        !normalised.containsKey('sessionId')) {
      normalised['sessionId'] = normalised['session_id'];
    }
    if (normalised.containsKey('enterprise_id') &&
        !normalised.containsKey('enterpriseId')) {
      normalised['enterpriseId'] = normalised['enterprise_id'];
    }
    if (normalised.containsKey('org_id') &&
        !normalised.containsKey('orgId')) {
      normalised['orgId'] = normalised['org_id'];
    }

    // Ensure orgId defaults to enterpriseId
    normalised['orgId'] ??= normalised['enterpriseId'];

    // Handle Unix ms integer timestamps → Firestore Timestamp equivalent
    final rawTs = normalised['timestamp'];
    if (rawTs is int) {
      normalised['timestamp'] =
          Timestamp.fromMillisecondsSinceEpoch(rawTs);
    } else if (rawTs is double) {
      normalised['timestamp'] =
          Timestamp.fromMillisecondsSinceEpoch(rawTs.toInt());
    }

    // Derive date field if missing
    if (normalised['date'] == null || normalised['date'] == '') {
      final ts = normalised['timestamp'];
      if (ts is Timestamp) {
        final d = ts.toDate().toLocal();
        normalised['date'] =
            '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      }
    }

    // Normalise type names: session_started → session_start, etc.
    final type = normalised['type']?.toString() ?? '';
    if (type == 'session_started') {
      normalised['type'] = 'session_start';
    } else if (type == 'session_ended' || type == 'session_auto_ended') {
      normalised['type'] = 'session_end';
    }

    return normalised;
  }

  factory ActivityLogModel.fromFirestore(DocumentSnapshot doc) {
    final raw = doc.data() as Map<String, dynamic>;
    final data = _normalise(doc.id, raw);
    return ActivityLogModel(
      id: doc.id,
      enterpriseId: data['enterpriseId'] ?? '',
      employeeId: data['employeeId'] ?? '',
      sessionId: data['sessionId'],
      orgId: data['orgId'],
      type: data['type'] ?? '',
      title: data['title'] ?? '',
      detail: data['detail'] ?? '',
      timestamp:
          (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      date: data['date']?.toString(),
      metadata: data['metadata'] as Map<String, dynamic>?,
      payload: data['payload'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'enterpriseId': enterpriseId,
      'employeeId': employeeId,
      'sessionId': sessionId,
      'orgId': orgId ?? enterpriseId,
      'type': type,
      'title': title,
      'detail': detail,
      'timestamp': Timestamp.fromDate(timestamp),
      'date': date,
      'metadata': metadata,
      'payload': payload,
    };
  }

  ActivityLogModel copyWith({
    String? id,
    String? enterpriseId,
    String? employeeId,
    String? sessionId,
    String? orgId,
    String? type,
    String? title,
    String? detail,
    DateTime? timestamp,
    String? date,
    Map<String, dynamic>? metadata,
    Map<String, dynamic>? payload,
  }) {
    return ActivityLogModel(
      id: id ?? this.id,
      enterpriseId: enterpriseId ?? this.enterpriseId,
      employeeId: employeeId ?? this.employeeId,
      sessionId: sessionId ?? this.sessionId,
      orgId: orgId ?? this.orgId,
      type: type ?? this.type,
      title: title ?? this.title,
      detail: detail ?? this.detail,
      timestamp: timestamp ?? this.timestamp,
      date: date ?? this.date,
      metadata: metadata ?? this.metadata,
      payload: payload ?? this.payload,
    );
  }
}
