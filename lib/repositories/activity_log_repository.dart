import '../models/activity_log_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firestore_service.dart';

class ActivityLogRepository {
  final FirestoreService _firestoreService = FirestoreService();
  static const String _collection = 'activityLogs';
  Future<void> createLog(ActivityLogModel log) async {
    await _firestoreService.addDocument(_collection, log.toFirestore());
  }

  Future<List<ActivityLogModel>> getLogsByEmployee(
    String employeeId, {
    required String enterpriseId,
    DateTime? date,
    int? limit,
  }) async {
    return getLogsByEmployeeIds(
      [employeeId],
      enterpriseId: enterpriseId,
      date: date,
      limit: limit,
    );
  }

  Future<List<ActivityLogModel>> getLogsByEmployeeIds(
    List<String> employeeIds, {
    required String enterpriseId,
    DateTime? date,
    DateTime? startDate,
    DateTime? endDate,
    int? limit,
  }) async {
    final normalizedIds =
        employeeIds.where((id) => id.trim().isNotEmpty).toSet().toList();
    if (normalizedIds.isEmpty) return const [];

    // `enterpriseId` MUST be the first filter. Firestore security rules gate
    // reads on resource.data.enterpriseId; without a matching query filter
    // the rules engine rejects the whole query with permission-denied,
    // regardless of isOwner / isAdmin / isTeamLead.
    final filters = <QueryFilter>[
      QueryFilter('enterpriseId', FilterOp.isEqualTo, enterpriseId),
      if (normalizedIds.length == 1)
        QueryFilter('employeeId', FilterOp.isEqualTo, normalizedIds.first)
      else
        QueryFilter('employeeId', FilterOp.whereIn, normalizedIds),
    ];
    if (date != null) {
      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));
      filters.add(QueryFilter(
        'timestamp',
        FilterOp.isGreaterThanOrEqualTo,
        Timestamp.fromDate(startOfDay),
      ));
      filters.add(QueryFilter(
        'timestamp',
        FilterOp.isLessThan,
        Timestamp.fromDate(endOfDay),
      ));
    } else {
      if (startDate != null) {
        filters.add(QueryFilter(
          'timestamp',
          FilterOp.isGreaterThanOrEqualTo,
          Timestamp.fromDate(startDate),
        ));
      }
      if (endDate != null) {
        filters.add(QueryFilter(
          'timestamp',
          FilterOp.isLessThanOrEqualTo,
          Timestamp.fromDate(endDate),
        ));
      }
    }

    final snapshot = await _firestoreService.getCollection(
      _collection,
      filters: filters,
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
    DateTime? startDate,
    DateTime? endDate,
    int? limit,
  }) async {
    final filters = <QueryFilter>[
      QueryFilter('enterpriseId', FilterOp.isEqualTo, enterpriseId),
      if (startDate != null)
        QueryFilter(
          'timestamp',
          FilterOp.isGreaterThanOrEqualTo,
          Timestamp.fromDate(startDate),
        ),
      if (endDate != null)
        QueryFilter(
          'timestamp',
          FilterOp.isLessThanOrEqualTo,
          Timestamp.fromDate(endDate),
        ),
    ];

    final snapshot = await _firestoreService.getCollection(
      _collection,
      filters: filters,
      orderBy: 'timestamp',
      descending: true,
      limit: limit,
    );

    return snapshot.docs
        .map((doc) => ActivityLogModel.fromFirestore(doc))
        .toList();
  }

  Future<List<ActivityLogModel>> getLogsBySessionIds(
    List<String> sessionIds, {
    required String enterpriseId,
    DateTime? startDate,
    DateTime? endDate,
    int? limit,
  }) async {
    final normalizedIds =
        sessionIds.where((id) => id.trim().isNotEmpty).toSet().toList();
    if (normalizedIds.isEmpty) return const [];

    final results = <ActivityLogModel>[];
    for (var i = 0; i < normalizedIds.length; i += 10) {
      final batch = normalizedIds.sublist(
        i,
        i + 10 > normalizedIds.length ? normalizedIds.length : i + 10,
      );

      final filters = <QueryFilter>[
        QueryFilter('enterpriseId', FilterOp.isEqualTo, enterpriseId),
        QueryFilter('sessionId', FilterOp.whereIn, batch),
        if (startDate != null)
          QueryFilter(
            'timestamp',
            FilterOp.isGreaterThanOrEqualTo,
            Timestamp.fromDate(startDate),
          ),
        if (endDate != null)
          QueryFilter(
            'timestamp',
            FilterOp.isLessThanOrEqualTo,
            Timestamp.fromDate(endDate),
          ),
      ];

      final snapshot = await _firestoreService.getCollection(
        _collection,
        filters: filters,
        orderBy: 'timestamp',
        descending: true,
        limit: limit,
      );

      results.addAll(
        snapshot.docs.map((doc) => ActivityLogModel.fromFirestore(doc)),
      );
    }

    final byId = <String, ActivityLogModel>{};
    for (final log in results) {
      byId[log.id] = log;
    }

    final merged = byId.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    if (limit != null && merged.length > limit) {
      return merged.take(limit).toList();
    }
    return merged;
  }

  Future<List<ActivityLogModel>> getLogsByEmployeeIdsUnfiltered(
    List<String> employeeIds, {
    required String enterpriseId,
    int? limit,
  }) async {
    final normalizedIds =
        employeeIds.where((id) => id.trim().isNotEmpty).toSet().toList();
    if (normalizedIds.isEmpty) return const [];

    final results = <ActivityLogModel>[];
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
        orderBy: 'timestamp',
        descending: true,
        limit: limit,
      );

      results.addAll(
        snapshot.docs.map((doc) => ActivityLogModel.fromFirestore(doc)),
      );
    }

    final byId = <String, ActivityLogModel>{};
    for (final log in results) {
      byId[log.id] = log;
    }

    final merged = byId.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    if (limit != null && merged.length > limit) {
      return merged.take(limit).toList();
    }
    return merged;
  }

  Future<List<ActivityLogModel>> getLogsBySessionIdsUnfiltered(
    List<String> sessionIds, {
    required String enterpriseId,
    int? limit,
  }) async {
    final normalizedIds =
        sessionIds.where((id) => id.trim().isNotEmpty).toSet().toList();
    if (normalizedIds.isEmpty) return const [];

    final results = <ActivityLogModel>[];
    for (var i = 0; i < normalizedIds.length; i += 10) {
      final batch = normalizedIds.sublist(
        i,
        i + 10 > normalizedIds.length ? normalizedIds.length : i + 10,
      );

      final snapshot = await _firestoreService.getCollection(
        _collection,
        filters: [
          QueryFilter('enterpriseId', FilterOp.isEqualTo, enterpriseId),
          QueryFilter('sessionId', FilterOp.whereIn, batch),
        ],
        orderBy: 'timestamp',
        descending: true,
        limit: limit,
      );

      results.addAll(
        snapshot.docs.map((doc) => ActivityLogModel.fromFirestore(doc)),
      );
    }

    final byId = <String, ActivityLogModel>{};
    for (final log in results) {
      byId[log.id] = log;
    }

    final merged = byId.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    if (limit != null && merged.length > limit) {
      return merged.take(limit).toList();
    }
    return merged;
  }

  Stream<List<ActivityLogModel>> streamLogsByEmployeeIdsSince(
    List<String> employeeIds, {
    required String enterpriseId,
    required DateTime since,
    int limit = 100,
  }) {
    final normalizedIds =
        employeeIds.where((id) => id.trim().isNotEmpty).toSet().toList();
    if (normalizedIds.isEmpty) {
      return Stream.value(const <ActivityLogModel>[]);
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
            QueryFilter(
              'timestamp',
              FilterOp.isGreaterThanOrEqualTo,
              Timestamp.fromDate(since),
            ),
          ],
          orderBy: 'timestamp',
          descending: true,
          limit: limit,
        )
        .map((snapshot) => snapshot.docs
            .map((doc) => ActivityLogModel.fromFirestore(doc))
            .toList());
  }

  Stream<List<ActivityLogModel>> streamLogsBySessionIdsSince(
    List<String> sessionIds, {
    required String enterpriseId,
    required DateTime since,
    int limit = 200,
  }) {
    final normalizedIds =
        sessionIds.where((id) => id.trim().isNotEmpty).toSet().toList();
    if (normalizedIds.isEmpty) {
      return Stream.value(const <ActivityLogModel>[]);
    }

    return _firestoreService
        .streamCollection(
          _collection,
          filters: [
            QueryFilter('enterpriseId', FilterOp.isEqualTo, enterpriseId),
            if (normalizedIds.length == 1)
              QueryFilter('sessionId', FilterOp.isEqualTo, normalizedIds.first)
            else
              QueryFilter('sessionId', FilterOp.whereIn, normalizedIds),
            QueryFilter(
              'timestamp',
              FilterOp.isGreaterThanOrEqualTo,
              Timestamp.fromDate(since),
            ),
          ],
          orderBy: 'timestamp',
          descending: true,
          limit: limit,
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

  Future<DateTime?> getLatestLocationLogTimeForSession(
    String sessionId, {
    required String enterpriseId,
  }) async {
    final snapshot = await _firestoreService.getCollection(
      _collection,
      filters: [
        QueryFilter('enterpriseId', FilterOp.isEqualTo, enterpriseId),
        QueryFilter('sessionId', FilterOp.isEqualTo, sessionId),
        QueryFilter('type', FilterOp.isEqualTo, 'location_update'),
      ],
      orderBy: 'timestamp',
      descending: true,
      limit: 1,
    );

    if (snapshot.docs.isEmpty) return null;
    return ActivityLogModel.fromFirestore(snapshot.docs.first).timestamp;
  }
}
