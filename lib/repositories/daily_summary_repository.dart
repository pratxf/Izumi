import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/daily_summary_model.dart';
import '../services/firestore_service.dart';

class DailySummaryRepository {
  final FirestoreService _firestoreService = FirestoreService();
  static const String _collection = 'dailySummaries';

  /// Write a daily summary immediately from the client after session end.
  /// Uses FieldValue.increment + arrayUnion so multiple sessions per day
  /// aggregate correctly. The Cloud Function may later overwrite with
  /// recalculated values — that's fine.
  Future<void> upsertFromSession({
    required String employeeId,
    required String enterpriseId,
    required String sessionId,
    required int totalDuration,
    required double totalDistance,
    required int photosCount,
    required int tasksCompleted,
  }) async {
    final now = DateTime.now();
    final docId =
        '${employeeId}_${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    await FirebaseFirestore.instance
        .collection(_collection)
        .doc(docId)
        .set({
      'employeeId': employeeId,
      'enterpriseId': enterpriseId,
      'date': Timestamp.fromDate(DateTime(now.year, now.month, now.day)),
      'totalDuration': FieldValue.increment(totalDuration),
      'totalDistance': FieldValue.increment(totalDistance),
      'photosCount': FieldValue.increment(photosCount),
      'tasksCompleted': FieldValue.increment(tasksCompleted),
      'sessionIds': FieldValue.arrayUnion([sessionId]),
      'isOffDuty': false,
    }, SetOptions(merge: true));
  }

  Future<List<DailySummaryModel>> getDailySummaries(
    String employeeId, {
    DateTime? startDate,
    DateTime? endDate,
    int? limit,
  }) async {
    final filters = <QueryFilter>[
      QueryFilter('employeeId', FilterOp.isEqualTo, employeeId),
    ];

    if (startDate != null) {
      filters.add(QueryFilter(
        'date',
        FilterOp.isGreaterThanOrEqualTo,
        Timestamp.fromDate(startDate),
      ));
    }

    if (endDate != null) {
      filters.add(QueryFilter(
        'date',
        FilterOp.isLessThanOrEqualTo,
        Timestamp.fromDate(endDate),
      ));
    }

    final snapshot = await _firestoreService.getCollection(
      _collection,
      filters: filters,
      orderBy: 'date',
      descending: true,
      limit: limit,
    );

    return snapshot.docs
        .map((doc) => DailySummaryModel.fromFirestore(doc))
        .toList();
  }

  Future<DailySummaryModel?> getDailySummary(
    String employeeId,
    DateTime date,
  ) async {
    final docId =
        '${employeeId}_${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final doc = await _firestoreService.getDocument(_collection, docId);
    if (!doc.exists) return null;
    return DailySummaryModel.fromFirestore(doc);
  }

  /// Get monthly aggregated summary for an employee
  Future<Map<String, dynamic>> getMonthlySummary(
    String employeeId,
    int year,
    int month,
  ) async {
    final startDate = DateTime(year, month, 1);
    final endDate = DateTime(year, month + 1, 0, 23, 59, 59);

    final summaries = await getDailySummaries(
      employeeId,
      startDate: startDate,
      endDate: endDate,
    );

    int totalDuration = 0;
    double totalDistance = 0.0;
    int totalPhotos = 0;
    int totalTasks = 0;
    int activeDays = 0;

    for (final s in summaries) {
      if (!s.isOffDuty) {
        totalDuration += s.totalDuration;
        totalDistance += s.totalDistance;
        totalPhotos += s.photosCount;
        totalTasks += s.tasksCompleted;
        activeDays++;
      }
    }

    return {
      'totalDuration': totalDuration,
      'totalDistance': totalDistance,
      'totalPhotos': totalPhotos,
      'totalTasks': totalTasks,
      'activeDays': activeDays,
      'hours': Duration(seconds: totalDuration).inHours,
      'minutes': Duration(seconds: totalDuration).inMinutes.remainder(60),
    };
  }

  Future<List<DailySummaryModel>> getSummariesByEnterprise(
    String enterpriseId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final filters = <QueryFilter>[
      QueryFilter('enterpriseId', FilterOp.isEqualTo, enterpriseId),
    ];

    if (startDate != null) {
      filters.add(QueryFilter(
        'date',
        FilterOp.isGreaterThanOrEqualTo,
        Timestamp.fromDate(startDate),
      ));
    }

    if (endDate != null) {
      filters.add(QueryFilter(
        'date',
        FilterOp.isLessThanOrEqualTo,
        Timestamp.fromDate(endDate),
      ));
    }

    final snapshot = await _firestoreService.getCollection(
      _collection,
      filters: filters,
      orderBy: 'date',
      descending: true,
    );

    return snapshot.docs
        .map((doc) => DailySummaryModel.fromFirestore(doc))
        .toList();
  }

  Stream<List<DailySummaryModel>> streamDailySummaries(String employeeId) {
    return _firestoreService
        .streamCollection(
          _collection,
          filters: [
            QueryFilter('employeeId', FilterOp.isEqualTo, employeeId),
          ],
          orderBy: 'date',
          descending: true,
        )
        .map((snapshot) => snapshot.docs
            .map((doc) => DailySummaryModel.fromFirestore(doc))
            .toList());
  }

  Stream<List<DailySummaryModel>> streamSummariesByEnterprise(
    String enterpriseId, {
    DateTime? startDate,
    DateTime? endDate,
  }) {
    final filters = <QueryFilter>[
      QueryFilter('enterpriseId', FilterOp.isEqualTo, enterpriseId),
    ];

    if (startDate != null) {
      filters.add(QueryFilter(
        'date',
        FilterOp.isGreaterThanOrEqualTo,
        Timestamp.fromDate(startDate),
      ));
    }

    if (endDate != null) {
      filters.add(QueryFilter(
        'date',
        FilterOp.isLessThanOrEqualTo,
        Timestamp.fromDate(endDate),
      ));
    }

    return _firestoreService
        .streamCollection(
          _collection,
          filters: filters,
          orderBy: 'date',
          descending: true,
        )
        .map((snapshot) => snapshot.docs
            .map((doc) => DailySummaryModel.fromFirestore(doc))
            .toList());
  }
}
