import 'package:cloud_firestore/cloud_firestore.dart';

class SessionModel {
  final String id;
  final String enterpriseId;
  final String employeeId;
  final DateTime startTime;
  final DateTime? endTime;
  final String status; // 'active' | 'completed' | 'auto_ended'
  final int totalDuration; // seconds
  final double totalDistance; // km
  final int photosCount;
  final int tasksCompleted;
  final String? notes;
  final String? autoEndReason;
  final DateTime? locationLostAt;
  final DateTime createdAt;

  const SessionModel({
    required this.id,
    required this.enterpriseId,
    required this.employeeId,
    required this.startTime,
    this.endTime,
    required this.status,
    this.totalDuration = 0,
    this.totalDistance = 0.0,
    this.photosCount = 0,
    this.tasksCompleted = 0,
    this.notes,
    this.autoEndReason,
    this.locationLostAt,
    required this.createdAt,
  });

  bool get isActive => status == 'active';
  bool get isCompleted => status == 'completed';
  bool get isAutoEnded => status == 'auto_ended';

  Duration get duration => Duration(seconds: totalDuration);

  String get formattedDuration {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }

  factory SessionModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return SessionModel(
      id: doc.id,
      enterpriseId: data['enterpriseId'] ?? '',
      employeeId: data['employeeId'] ?? '',
      startTime: (data['startTime'] as Timestamp?)?.toDate() ?? DateTime.now(),
      endTime: (data['endTime'] as Timestamp?)?.toDate(),
      status: data['status'] ?? 'active',
      totalDuration: data['totalDuration'] ?? 0,
      totalDistance: (data['totalDistance'] ?? 0.0).toDouble(),
      photosCount: data['photosCount'] ?? 0,
      tasksCompleted: data['tasksCompleted'] ?? 0,
      notes: data['notes'],
      autoEndReason: data['autoEndReason'],
      locationLostAt: (data['locationLostAt'] as Timestamp?)?.toDate(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'enterpriseId': enterpriseId,
      'employeeId': employeeId,
      'startTime': Timestamp.fromDate(startTime),
      'endTime': endTime != null ? Timestamp.fromDate(endTime!) : null,
      'status': status,
      'totalDuration': totalDuration,
      'totalDistance': totalDistance,
      'photosCount': photosCount,
      'tasksCompleted': tasksCompleted,
      'notes': notes,
      'autoEndReason': autoEndReason,
      'locationLostAt': locationLostAt != null ? Timestamp.fromDate(locationLostAt!) : null,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  SessionModel copyWith({
    String? id,
    String? enterpriseId,
    String? employeeId,
    DateTime? startTime,
    DateTime? endTime,
    String? status,
    int? totalDuration,
    double? totalDistance,
    int? photosCount,
    int? tasksCompleted,
    String? notes,
    String? autoEndReason,
    DateTime? locationLostAt,
    DateTime? createdAt,
  }) {
    return SessionModel(
      id: id ?? this.id,
      enterpriseId: enterpriseId ?? this.enterpriseId,
      employeeId: employeeId ?? this.employeeId,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      status: status ?? this.status,
      totalDuration: totalDuration ?? this.totalDuration,
      totalDistance: totalDistance ?? this.totalDistance,
      photosCount: photosCount ?? this.photosCount,
      tasksCompleted: tasksCompleted ?? this.tasksCompleted,
      notes: notes ?? this.notes,
      autoEndReason: autoEndReason ?? this.autoEndReason,
      locationLostAt: locationLostAt ?? this.locationLostAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
