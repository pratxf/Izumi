import '../models/activity_log_model.dart';
import '../services/firestore_service.dart';

class ActivityLogRepository {
  final FirestoreService _firestoreService = FirestoreService();
  static const String _collection = 'activityLogs';

  Future<void> createLog(ActivityLogModel log) async {
    await _firestoreService.addDocument(_collection, log.toFirestore());
  }

  Future<List<ActivityLogModel>> getLogsByEmployee(
    String employeeId, {
    int? limit,
  }) async {
    final snapshot = await _firestoreService.getCollection(
      _collection,
      filters: [
        QueryFilter('employeeId', FilterOp.isEqualTo, employeeId),
      ],
      orderBy: 'timestamp',
      descending: true,
      limit: limit,
    );

    return snapshot.docs
        .map((doc) => ActivityLogModel.fromFirestore(doc))
        .toList();
  }

  Future<List<ActivityLogModel>> getLogsByEnterprise(
    String enterpriseId, {
    int? limit,
  }) async {
    final snapshot = await _firestoreService.getCollection(
      _collection,
      filters: [
        QueryFilter('enterpriseId', FilterOp.isEqualTo, enterpriseId),
      ],
      orderBy: 'timestamp',
      descending: true,
      limit: limit,
    );

    return snapshot.docs
        .map((doc) => ActivityLogModel.fromFirestore(doc))
        .toList();
  }

  Stream<List<ActivityLogModel>> streamLogsByEmployee(String employeeId) {
    return _firestoreService
        .streamCollection(
          _collection,
          filters: [
            QueryFilter('employeeId', FilterOp.isEqualTo, employeeId),
          ],
          orderBy: 'timestamp',
          descending: true,
          limit: 50,
        )
        .map((snapshot) => snapshot.docs
            .map((doc) => ActivityLogModel.fromFirestore(doc))
            .toList());
  }

  Stream<List<ActivityLogModel>> streamLogsByEnterprise(String enterpriseId) {
    return _firestoreService
        .streamCollection(
          _collection,
          filters: [
            QueryFilter('enterpriseId', FilterOp.isEqualTo, enterpriseId),
          ],
          orderBy: 'timestamp',
          descending: true,
          limit: 100,
        )
        .map((snapshot) => snapshot.docs
            .map((doc) => ActivityLogModel.fromFirestore(doc))
            .toList());
  }
}
