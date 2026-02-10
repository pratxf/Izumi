import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/daily_summary_model.dart';
import '../services/firestore_service.dart';

class DailySummaryRepository {
  final FirestoreService _firestoreService = FirestoreService();
  static const String _collection = 'dailySummaries';

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
}
