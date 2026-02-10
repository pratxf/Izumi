import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/session_model.dart';
import '../models/session_location_model.dart';
import '../services/firestore_service.dart';

class SessionRepository {
  final FirestoreService _firestoreService = FirestoreService();
  static const String _collection = 'sessions';
  static const String _locationsSubcollection = 'locations';

  Future<String> createSession(SessionModel session) async {
    final docRef = await _firestoreService.addDocument(
      _collection,
      session.toFirestore(),
    );
    return docRef.id;
  }

  Future<SessionModel?> getSession(String sessionId) async {
    final doc = await _firestoreService.getDocument(_collection, sessionId);
    if (!doc.exists) return null;
    return SessionModel.fromFirestore(doc);
  }

  Future<SessionModel?> getActiveSession(String employeeId) async {
    final snapshot = await _firestoreService.getCollection(
      _collection,
      filters: [
        QueryFilter('employeeId', FilterOp.isEqualTo, employeeId),
        QueryFilter('status', FilterOp.isEqualTo, 'active'),
      ],
      limit: 1,
    );
    if (snapshot.docs.isEmpty) return null;
    return SessionModel.fromFirestore(snapshot.docs.first);
  }

  Future<void> updateSession(String sessionId, Map<String, dynamic> data) async {
    await _firestoreService.updateDocument(_collection, sessionId, data);
  }

  Future<void> endSession({
    required String sessionId,
    required int totalDuration,
    required double totalDistance,
    required int photosCount,
    required int tasksCompleted,
    String? notes,
  }) async {
    await _firestoreService.updateDocument(_collection, sessionId, {
      'endTime': Timestamp.fromDate(DateTime.now()),
      'status': 'completed',
      'totalDuration': totalDuration,
      'totalDistance': totalDistance,
      'photosCount': photosCount,
      'tasksCompleted': tasksCompleted,
      'notes': notes,
    });
  }

  Future<List<SessionModel>> getSessionHistory(
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
        'startTime',
        FilterOp.isGreaterThanOrEqualTo,
        Timestamp.fromDate(startDate),
      ));
    }

    if (endDate != null) {
      filters.add(QueryFilter(
        'startTime',
        FilterOp.isLessThanOrEqualTo,
        Timestamp.fromDate(endDate),
      ));
    }

    final snapshot = await _firestoreService.getCollection(
      _collection,
      filters: filters,
      orderBy: 'startTime',
      descending: true,
      limit: limit,
    );

    return snapshot.docs
        .map((doc) => SessionModel.fromFirestore(doc))
        .toList();
  }

  Future<List<SessionModel>> getSessionsByEnterprise(
    String enterpriseId, {
    String? status,
  }) async {
    final filters = <QueryFilter>[
      QueryFilter('enterpriseId', FilterOp.isEqualTo, enterpriseId),
    ];

    if (status != null) {
      filters.add(QueryFilter('status', FilterOp.isEqualTo, status));
    }

    final snapshot = await _firestoreService.getCollection(
      _collection,
      filters: filters,
      orderBy: 'startTime',
      descending: true,
    );

    return snapshot.docs
        .map((doc) => SessionModel.fromFirestore(doc))
        .toList();
  }

  // ── Location subcollection ──

  Future<void> addSessionLocation(
    String sessionId,
    SessionLocationModel location,
  ) async {
    await _firestoreService.addToSubcollection(
      _collection,
      sessionId,
      _locationsSubcollection,
      location.toFirestore(),
    );
  }

  Future<List<SessionLocationModel>> getSessionLocations(
      String sessionId) async {
    final snapshot = await _firestoreService.getSubcollection(
      _collection,
      sessionId,
      _locationsSubcollection,
      orderBy: 'timestamp',
    );

    return snapshot.docs
        .map((doc) => SessionLocationModel.fromFirestore(doc))
        .toList();
  }

  Stream<SessionModel?> streamActiveSession(String employeeId) {
    return _firestoreService
        .streamCollection(
          _collection,
          filters: [
            QueryFilter('employeeId', FilterOp.isEqualTo, employeeId),
            QueryFilter('status', FilterOp.isEqualTo, 'active'),
          ],
          limit: 1,
        )
        .map((snapshot) => snapshot.docs.isEmpty
            ? null
            : SessionModel.fromFirestore(snapshot.docs.first));
  }
}
