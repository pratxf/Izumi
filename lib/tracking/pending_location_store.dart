import 'package:sqflite/sqflite.dart';

import '../offline_queue/app_database.dart';

class PendingLocationStore {
  PendingLocationStore._();

  static final PendingLocationStore instance = PendingLocationStore._();

  static const tableName = 'pending_locations';

  Future<Database> get database async => AppDatabase.instance.database;

  Future<void> insertPendingLocation({
    required String sessionId,
    required String enterpriseId,
    required String employeeId,
    required double latitude,
    required double longitude,
    required double cumulativeDistanceKm,
    required String activityType,
    required int capturedAtMs,
    double? accuracy,
    double? speed,
    double? heading,
    int? activityConfidence,
  }) async {
    final db = await database;
    await db.insert(tableName, {
      'session_id': sessionId,
      'enterprise_id': enterpriseId,
      'employee_id': employeeId,
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'speed': speed,
      'heading': heading,
      'activity_type': activityType,
      'activity_confidence': activityConfidence,
      'cumulative_distance_km': cumulativeDistanceKm,
      'captured_at_ms': capturedAtMs,
      'created_at_ms': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<Map<String, dynamic>?> getLatestPointForSession(
      String sessionId) async {
    final db = await database;
    final rows = await db.query(
      tableName,
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'captured_at_ms DESC, id DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<int> getPendingCountForSession(String sessionId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM $tableName WHERE session_id = ?',
      [sessionId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<List<Map<String, dynamic>>> getPendingLocationsForSession(
    String sessionId,
  ) async {
    final db = await database;
    return db.query(
      tableName,
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'captured_at_ms ASC, id ASC',
    );
  }

  Future<void> deleteRowsByIds(List<int> ids) async {
    if (ids.isEmpty) {
      return;
    }

    final db = await database;
    final placeholders = List.filled(ids.length, '?').join(', ');
    await db.delete(
      tableName,
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
  }

  Future<void> clearSession(String sessionId) async {
    final db = await database;
    await db.delete(
      tableName,
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
  }

  // ── Session state persistence for crash recovery ──

  static const _sessionStateTable = 'session_state';

  Future<void> saveSessionState({
    required String sessionId,
    required String employeeId,
    required String enterpriseId,
    String? orgId,
    required int startTimeMs,
    required double totalDistanceKm,
    int? lastSyncedAtMs,
    double? lastLat,
    double? lastLng,
    String status = 'active',
  }) async {
    final db = await database;
    await db.insert(
      _sessionStateTable,
      {
        'id': 1,
        'session_id': sessionId,
        'employee_id': employeeId,
        'enterprise_id': enterpriseId,
        'org_id': orgId,
        'start_time_ms': startTimeMs,
        'total_distance_km': totalDistanceKm,
        'last_synced_at_ms': lastSyncedAtMs,
        'last_lat': lastLat,
        'last_lng': lastLng,
        'status': status,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getSessionState() async {
    final db = await database;
    final rows = await db.query(_sessionStateTable, where: 'id = 1', limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> updateSessionDistance(double totalDistanceKm) async {
    final db = await database;
    await db.update(
      _sessionStateTable,
      {'total_distance_km': totalDistanceKm},
      where: 'id = 1',
    );
  }

  Future<void> updateSessionLastSync(int lastSyncedAtMs) async {
    final db = await database;
    await db.update(
      _sessionStateTable,
      {'last_synced_at_ms': lastSyncedAtMs},
      where: 'id = 1',
    );
  }

  Future<void> markSessionEnding() async {
    final db = await database;
    await db.update(
      _sessionStateTable,
      {'status': 'ending'},
      where: 'id = 1',
    );
  }

  Future<void> clearSessionState() async {
    final db = await database;
    await db.delete(_sessionStateTable);
  }

  Future<void> close() async {
    await AppDatabase.instance.close();
  }
}
