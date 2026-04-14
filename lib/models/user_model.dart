import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String id;
  final String name;
  final String phone;
  final String? email;
  final List<String> roles;
  final String activeRole;
  final String enterpriseId;
  final String? groupId;
  final String? migratedFrom;
  /// Additional pre-migration UIDs linked to this user beyond [migratedFrom].
  /// Used when a user has multiple historical UIDs (migration happened twice
  /// or territory-owner had prior orphaned UIDs). Null / empty list = none.
  final List<String>? migratedFromChain;
  final String? profileImageUrl;
  final String? fcmToken;
  final DateTime createdAt;
  final DateTime updatedAt;

  const UserModel({
    required this.id,
    required this.name,
    required this.phone,
    this.email,
    required this.roles,
    required this.activeRole,
    required this.enterpriseId,
    this.groupId,
    this.migratedFrom,
    this.migratedFromChain,
    this.profileImageUrl,
    this.fcmToken,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isAdmin => roles.contains('admin');
  bool get isTeamLead => roles.contains('team_lead');
  bool get isEmployee => roles.contains('employee');

  String get initials {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  String get displayRole {
    switch (activeRole) {
      case 'admin':
        return 'Enterprise Admin';
      case 'team_lead':
        return 'Team Lead';
      case 'employee':
        return 'Field Employee';
      default:
        return activeRole;
    }
  }

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserModel(
      id: doc.id,
      name: data['name'] ?? '',
      phone: data['phone'] ?? '',
      email: data['email'],
      roles: data['roles'] != null
          ? List<String>.from(data['roles'])
          : [data['role'] ?? 'employee'],
      activeRole: data['activeRole'] ?? data['role'] ?? 'employee',
      enterpriseId: data['enterpriseId'] ?? '',
      groupId: data['groupId'],
      migratedFrom: data['migratedFrom'],
      migratedFromChain: data['migratedFromChain'] is List
          ? List<String>.from(
              (data['migratedFromChain'] as List).whereType<String>(),
            )
          : null,
      profileImageUrl: data['profileImageUrl'],
      fcmToken: data['fcmToken'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'phone': phone,
      'email': email,
      'roles': roles,
      'activeRole': activeRole,
      'role': activeRole, // backward compat
      'enterpriseId': enterpriseId,
      'groupId': groupId,
      'migratedFrom': migratedFrom,
      'migratedFromChain': migratedFromChain,
      'profileImageUrl': profileImageUrl,
      'fcmToken': fcmToken,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  UserModel copyWith({
    String? id,
    String? name,
    String? phone,
    String? email,
    List<String>? roles,
    String? activeRole,
    String? enterpriseId,
    String? groupId,
    String? migratedFrom,
    List<String>? migratedFromChain,
    String? profileImageUrl,
    String? fcmToken,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserModel(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      roles: roles ?? this.roles,
      activeRole: activeRole ?? this.activeRole,
      enterpriseId: enterpriseId ?? this.enterpriseId,
      groupId: groupId ?? this.groupId,
      migratedFrom: migratedFrom ?? this.migratedFrom,
      migratedFromChain: migratedFromChain ?? this.migratedFromChain,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      fcmToken: fcmToken ?? this.fcmToken,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
