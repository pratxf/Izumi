import 'package:cloud_firestore/cloud_firestore.dart';
import 'upload_status.dart';

class TaskModel {
  final String id;
  final String enterpriseId;
  final String title;
  final String? description;
  final String type; // 'task' | 'followup'
  final String priority; // 'high' | 'medium' | 'low'
  final String status; // 'pending' | 'completed'
  final String assignedTo;
  final String assignedBy;
  final String? assignedByName;
  final String? assignedToName;
  final String? groupId;
  final DateTime dueDate;
  final String? contactType;
  final String? contactPhone;
  final DateTime? completedAt;
  final bool sendNotification;
  final DateTime createdAt;
  final DateTime updatedAt;
  final UploadStatus uploadStatus;

  const TaskModel({
    required this.id,
    required this.enterpriseId,
    required this.title,
    this.description,
    required this.type,
    required this.priority,
    required this.status,
    required this.assignedTo,
    required this.assignedBy,
    this.assignedByName,
    this.assignedToName,
    this.groupId,
    required this.dueDate,
    this.contactType,
    this.contactPhone,
    this.completedAt,
    this.sendNotification = true,
    required this.createdAt,
    required this.updatedAt,
    this.uploadStatus = UploadStatus.success,
  });

  bool get isPending => status == 'pending';
  bool get isCompleted => status == 'completed';
  bool get isTask => type == 'task';
  bool get isFollowup => type == 'followup';
  bool get isHighPriority => priority == 'high';

  bool get isDueToday {
    final now = DateTime.now();
    return dueDate.year == now.year &&
        dueDate.month == now.month &&
        dueDate.day == now.day;
  }

  String get priorityEmoji {
    switch (priority) {
      case 'high':
        return '\u26A0\uFE0F';
      case 'medium':
        return '\uD83D\uDCCB';
      case 'low':
        return '\uD83D\uDCCC';
      default:
        return '\uD83D\uDCCB';
    }
  }

  factory TaskModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return TaskModel(
      id: doc.id,
      enterpriseId: data['enterpriseId'] ?? '',
      title: data['title'] ?? '',
      description: data['description'],
      type: data['type'] ?? 'task',
      priority: data['priority'] ?? 'medium',
      status: data['status'] ?? 'pending',
      assignedTo: data['assignedTo'] ?? '',
      assignedBy: data['assignedBy'] ?? '',
      assignedByName: data['assignedByName'],
      assignedToName: data['assignedToName'],
      groupId: data['groupId'],
      dueDate: (data['dueDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      contactType: data['contactType'],
      contactPhone: data['contactPhone'],
      completedAt: (data['completedAt'] as Timestamp?)?.toDate(),
      sendNotification: data['sendNotification'] ?? true,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      uploadStatus: UploadStatus.success,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'enterpriseId': enterpriseId,
      'title': title,
      'description': description,
      'type': type,
      'priority': priority,
      'status': status,
      'assignedTo': assignedTo,
      'assignedBy': assignedBy,
      'assignedByName': assignedByName,
      'assignedToName': assignedToName,
      'groupId': groupId,
      'dueDate': Timestamp.fromDate(dueDate),
      'contactType': contactType,
      'contactPhone': contactPhone,
      'completedAt':
          completedAt != null ? Timestamp.fromDate(completedAt!) : null,
      'sendNotification': sendNotification,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  TaskModel copyWith({
    String? id,
    String? enterpriseId,
    String? title,
    String? description,
    String? type,
    String? priority,
    String? status,
    String? assignedTo,
    String? assignedBy,
    String? assignedByName,
    String? assignedToName,
    String? groupId,
    DateTime? dueDate,
    String? contactType,
    String? contactPhone,
    DateTime? completedAt,
    bool? sendNotification,
    DateTime? createdAt,
    DateTime? updatedAt,
    UploadStatus? uploadStatus,
  }) {
    return TaskModel(
      id: id ?? this.id,
      enterpriseId: enterpriseId ?? this.enterpriseId,
      title: title ?? this.title,
      description: description ?? this.description,
      type: type ?? this.type,
      priority: priority ?? this.priority,
      status: status ?? this.status,
      assignedTo: assignedTo ?? this.assignedTo,
      assignedBy: assignedBy ?? this.assignedBy,
      assignedByName: assignedByName ?? this.assignedByName,
      assignedToName: assignedToName ?? this.assignedToName,
      groupId: groupId ?? this.groupId,
      dueDate: dueDate ?? this.dueDate,
      contactType: contactType ?? this.contactType,
      contactPhone: contactPhone ?? this.contactPhone,
      completedAt: completedAt ?? this.completedAt,
      sendNotification: sendNotification ?? this.sendNotification,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      uploadStatus: uploadStatus ?? this.uploadStatus,
    );
  }
}
