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
    required int photosCount,
    required int tasksCompleted,
  }) async {
    // Distance is intentionally NOT written here. onSessionComplete
    // (Cloud Function) recalculates totalDistance from the raw location
    // trail and is the single source of truth for completed-session distance.
    // kickSentAt is cleared so it doesn't linger on completed sessions.
    await _firestoreService.updateDocument(_collection, sessionId, {
      'endTime': Timestamp.fromDate(DateTime.now()),
      'status': 'ended',
      'totalDuration': totalDuration,
      'photosCount': photosCount,
      'tasksCompleted': tasksCompleted,
      'kickSentAt': FieldValue.delete(),
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

  Future<List<SessionModel>> getSessionHistoryByEmployeeIds(
    List<String> employeeIds, {
    required String enterpriseId,
    DateTime? startDate,
    DateTime? endDate,
    int? limit,
  }) async {
    final normalizedIds =
        employeeIds.where((id) => id.trim().isNotEmpty).toSet().toList();
    if (normalizedIds.isEmpty) return const [];

    final results = <SessionModel>[];
    for (var i = 0; i < normalizedIds.length; i += 10) {
      final batch = normalizedIds.sublist(
        i,
        i + 10 > normalizedIds.length ? normalizedIds.length : i + 10,
      );

      final filters = <QueryFilter>[
        QueryFilter('enterpriseId', FilterOp.isEqualTo, enterpriseId),
        if (batch.length == 1)
          QueryFilter('employeeId', FilterOp.isEqualTo, batch.first)
        else
          QueryFilter('employeeId', FilterOp.whereIn, batch),
        if (startDate != null)
          QueryFilter(
            'startTime',
            FilterOp.isGreaterThanOrEqualTo,
            Timestamp.fromDate(startDate),
          ),
        if (endDate != null)
          QueryFilter(
            'startTime',
            FilterOp.isLessThanOrEqualTo,
            Timestamp.fromDate(endDate),
          ),
      ];

      final snapshot = await _firestoreService.getCollection(
        _collection,
        filters: filters,
        orderBy: 'startTime',
        descending: true,
        limit: limit,
      );

      results.addAll(
        snapshot.docs.map((doc) => SessionModel.fromFirestore(doc)),
      );
    }

    final filtered = results.where((session) {
      if (startDate == null && endDate == null) {
        return true;
      }
      final sessionEnd = session.endTime ?? session.startTime;
      final startsBeforeEnd = endDate == null || !session.startTime.isAfter(endDate);
      final endsAfterStart =
          startDate == null || !sessionEnd.isBefore(startDate);
      return startsBeforeEnd && endsAfterStart;
    }).toList();

    final byId = <String, SessionModel>{};
    for (final session in filtered) {
      byId[session.id] = session;
    }

    final merged = byId.values.toList()
      ..sort((a, b) => b.startTime.compareTo(a.startTime));
    if (limit != null && merged.length > limit) {
      return merged.take(limit).toList();
    }
    return merged;
  }

  Future<List<SessionModel>> getSessionHistoryByEmployeeIdsUnfiltered(
    List<String> employeeIds, {
    required String enterpriseId,
    int? limit,
  }) async {
    final normalizedIds =
        employeeIds.where((id) => id.trim().isNotEmpty).toSet().toList();
    if (normalizedIds.isEmpty) return const [];

    final results = <SessionModel>[];
    for (var i = 0; i < normalizedIds.length; i += 10) {
      final batch = normalizedIds.sublist(
        i,
        i + 10 > normalizedIds.length ? normalizedIds.length : i + 10,
      );

      final snapshot = await _firestoreService.getCollection(
        _collection,
        filters: [
          QueryFilter('enterpriseId', FilterOp.isEqualTo, enterpriseId),
          if (batch.length == 1)
            QueryFilter('employeeId', FilterOp.isEqualTo, batch.first)
          else
            QueryFilter('employeeId', FilterOp.whereIn, batch),
        ],
        limit: limit,
      );

      results.addAll(
        snapshot.docs.map((doc) => SessionModel.fromFirestore(doc)),
      );
    }

    final byId = <String, SessionModel>{};
    for (final session in results) {
      byId[session.id] = session;
    }

    final merged = byId.values.toList()
      ..sort((a, b) => b.startTime.compareTo(a.startTime));
    if (limit != null && merged.length > limit) {
      return merged.take(limit).toList();
    }
    return merged;
  }

  /// Enterprise-wide session query — used as a last-resort fallback when
  /// employee-scoped composite-index queries fail.
  Future<List<SessionModel>> getSessionsByEnterprise(
    String enterpriseId, {
    DateTime? startDate,
    DateTime? endDate,
    int? limit,
  }) async {
    final filters = <QueryFilter>[
      QueryFilter('enterpriseId', FilterOp.isEqualTo, enterpriseId),
      if (startDate != null)
        QueryFilter(
          'startTime',
          FilterOp.isGreaterThanOrEqualTo,
          Timestamp.fromDate(startDate),
        ),
      if (endDate != null)
        QueryFilter(
          'startTime',
          FilterOp.isLessThanOrEqualTo,
          Timestamp.fromDate(endDate),
        ),
    ];

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

  Stream<List<SessionModel>> streamActiveSessionsByEmployeeIds(
    List<String> employeeIds, {
    required String enterpriseId,
  }) {
    final normalizedIds =
        employeeIds.where((id) => id.trim().isNotEmpty).toSet().toList();
    if (normalizedIds.isEmpty) {
      return Stream.value(const <SessionModel>[]);
    }

    return _firestoreService
        .streamCollection(
          _collection,
          filters: [
            QueryFilter('enterpriseId', FilterOp.isEqualTo, enterpriseId),
            if (normalizedIds.length == 1)
              QueryFilter('employeeId', FilterOp.isEqualTo, normalizedIds.first)
            else
              QueryFilter('employeeId', FilterOp.whereIn, normalizedIds),
            QueryFilter('status', FilterOp.isEqualTo, 'active'),
          ],
          orderBy: 'startTime',
          descending: true,
          limit: 10,
        )
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => SessionModel.fromFirestore(doc))
              .toList(),
        );
  }
}
