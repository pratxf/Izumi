import 'package:cloud_firestore/cloud_firestore.dart';

class GroupModel {
  final String id;
  final String enterpriseId;
  final String name;
  final String leadId;
  final String color; // hex color string
  final List<String> memberIds;
  final DateTime createdAt;
  final DateTime updatedAt;

  const GroupModel({
    required this.id,
    required this.enterpriseId,
    required this.name,
    required this.leadId,
    required this.color,
    required this.memberIds,
    required this.createdAt,
    required this.updatedAt,
  });

  int get memberCount => memberIds.length;

  factory GroupModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return GroupModel(
      id: doc.id,
      enterpriseId: data['enterpriseId'] ?? '',
      name: data['name'] ?? '',
      leadId: data['leadId'] ?? '',
      color: data['color'] ?? '#6366F1',
      memberIds: List<String>.from(data['memberIds'] ?? []),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'enterpriseId': enterpriseId,
      'name': name,
      'leadId': leadId,
      'color': color,
      'memberIds': memberIds,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  GroupModel copyWith({
    String? id,
    String? enterpriseId,
    String? name,
    String? leadId,
    String? color,
    List<String>? memberIds,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return GroupModel(
      id: id ?? this.id,
      enterpriseId: enterpriseId ?? this.enterpriseId,
      name: name ?? this.name,
      leadId: leadId ?? this.leadId,
      color: color ?? this.color,
      memberIds: memberIds ?? this.memberIds,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
