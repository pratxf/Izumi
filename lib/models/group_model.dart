import 'package:cloud_firestore/cloud_firestore.dart';

class GroupModel {
  final String id;
  final String enterpriseId;
  final String name;
  final List<String> leadIds;
  final String color; // hex color string
  final List<String> memberIds;
  final DateTime createdAt;
  final DateTime updatedAt;

  const GroupModel({
    required this.id,
    required this.enterpriseId,
    required this.name,
    required this.leadIds,
    required this.color,
    required this.memberIds,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Convenience getter for backward compat (e.g. task assignment).
  String get leadId => leadIds.isNotEmpty ? leadIds.first : '';

  int get memberCount => memberIds.length;

  factory GroupModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    // Support both new `leadIds` array and legacy `leadId` string.
    // Also fall back to legacy `leadId` when `leadIds` is present but empty —
    // some older group docs have `leadIds: []` alongside a populated `leadId`.
    List<String> leadIds = List<String>.from(data['leadIds'] ?? const []);
    if (leadIds.isEmpty) {
      final legacy = data['leadId'] as String? ?? '';
      if (legacy.isNotEmpty) {
        leadIds = [legacy];
      }
    }

    return GroupModel(
      id: doc.id,
      enterpriseId: data['enterpriseId'] ?? '',
      name: data['name'] ?? '',
      leadIds: leadIds,
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
      'leadIds': leadIds,
      'leadId': leadId, // backward compat for Cloud Functions / queries
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
    List<String>? leadIds,
    String? color,
    List<String>? memberIds,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return GroupModel(
      id: id ?? this.id,
      enterpriseId: enterpriseId ?? this.enterpriseId,
      name: name ?? this.name,
      leadIds: leadIds ?? this.leadIds,
      color: color ?? this.color,
      memberIds: memberIds ?? this.memberIds,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
