import 'package:cloud_firestore/cloud_firestore.dart';

class DailySummaryModel {
  final String id;
  final String enterpriseId;
  final String employeeId;
  final DateTime date;
  final int totalDuration; // seconds
  final double totalDistance; // km
  final int photosCount;
  final int tasksCompleted;
  final List<String> locationsVisited;
  final List<String> sessionIds;
  final bool isOffDuty;

  const DailySummaryModel({
    required this.id,
    required this.enterpriseId,
    required this.employeeId,
    required this.date,
    this.totalDuration = 0,
    this.totalDistance = 0.0,
    this.photosCount = 0,
    this.tasksCompleted = 0,
    this.locationsVisited = const [],
    this.sessionIds = const [],
    this.isOffDuty = false,
  });

  Duration get duration => Duration(seconds: totalDuration);

  int get hours => duration.inHours;
  int get minutes => duration.inMinutes.remainder(60);

  String get formattedDuration {
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }

  String get dayName {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final thisDate = DateTime(date.year, date.month, date.day);

    if (thisDate == today) return 'Today';
    if (thisDate == today.subtract(const Duration(days: 1))) return 'Yesterday';

    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[date.weekday - 1];
  }

  bool get isToday {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  factory DailySummaryModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return DailySummaryModel(
      id: doc.id,
      enterpriseId: data['enterpriseId'] ?? '',
      employeeId: data['employeeId'] ?? '',
      date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      totalDuration: data['totalDuration'] ?? 0,
      totalDistance: (data['totalDistance'] ?? 0.0).toDouble(),
      photosCount: data['photosCount'] ?? 0,
      tasksCompleted: data['tasksCompleted'] ?? 0,
      locationsVisited: List<String>.from(data['locationsVisited'] ?? []),
      sessionIds: List<String>.from(data['sessionIds'] ?? []),
      isOffDuty: data['isOffDuty'] ?? false,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'enterpriseId': enterpriseId,
      'employeeId': employeeId,
      'date': Timestamp.fromDate(date),
      'totalDuration': totalDuration,
      'totalDistance': totalDistance,
      'photosCount': photosCount,
      'tasksCompleted': tasksCompleted,
      'locationsVisited': locationsVisited,
      'sessionIds': sessionIds,
      'isOffDuty': isOffDuty,
    };
  }

  DailySummaryModel copyWith({
    String? id,
    String? enterpriseId,
    String? employeeId,
    DateTime? date,
    int? totalDuration,
    double? totalDistance,
    int? photosCount,
    int? tasksCompleted,
    List<String>? locationsVisited,
    List<String>? sessionIds,
    bool? isOffDuty,
  }) {
    return DailySummaryModel(
      id: id ?? this.id,
      enterpriseId: enterpriseId ?? this.enterpriseId,
      employeeId: employeeId ?? this.employeeId,
      date: date ?? this.date,
      totalDuration: totalDuration ?? this.totalDuration,
      totalDistance: totalDistance ?? this.totalDistance,
      photosCount: photosCount ?? this.photosCount,
      tasksCompleted: tasksCompleted ?? this.tasksCompleted,
      locationsVisited: locationsVisited ?? this.locationsVisited,
      sessionIds: sessionIds ?? this.sessionIds,
      isOffDuty: isOffDuty ?? this.isOffDuty,
    );
  }
}
