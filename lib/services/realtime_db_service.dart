import 'package:firebase_database/firebase_database.dart';

class RealtimeDbService {
  final FirebaseDatabase _db = FirebaseDatabase.instance;

  // ── Presence ──

  Future<void> setPresence({
    required String enterpriseId,
    required String userId,
    required String status, // 'active' | 'break' | 'offline' | 'signal_lost'
    String? currentSessionId,
  }) async {
    await _db.ref('presence/$enterpriseId/$userId').set({
      'status': status,
      'lastSeen': ServerValue.timestamp,
      'currentSessionId': currentSessionId,
      'signalLostAt': null,
    });
  }

  Future<void> setOffline({
    required String enterpriseId,
    required String userId,
  }) async {
    await _db.ref('presence/$enterpriseId/$userId').set({
      'status': 'offline',
      'lastSeen': ServerValue.timestamp,
      'currentSessionId': null,
      'signalLostAt': null,
    });
  }

  Future<void> setupSignalLostOnDisconnect({
    required String enterpriseId,
    required String userId,
    String? currentSessionId,
  }) async {
    await _db.ref('presence/$enterpriseId/$userId').onDisconnect().update({
      'status': 'signal_lost',
      'signalLostAt': ServerValue.timestamp,
      'lastSeen': ServerValue.timestamp,
      'currentSessionId': currentSessionId,
    });
  }

  Future<void> clearOnDisconnect({
    required String enterpriseId,
    required String userId,
  }) async {
    await _db.ref('presence/$enterpriseId/$userId').onDisconnect().cancel();
  }

  Stream<DatabaseEvent> streamPresence(String enterpriseId) {
    return _db.ref('presence/$enterpriseId').onValue;
  }

  Stream<DatabaseEvent> streamUserPresence(String enterpriseId, String userId) {
    return _db.ref('presence/$enterpriseId/$userId').onValue;
  }

  // ── Live Locations ──

  Future<void> updateLiveLocation({
    required String enterpriseId,
    required String userId,
    required double latitude,
    required double longitude,
    required String address,
    double? accuracy,
  }) async {
    await _db.ref('liveLocations/$enterpriseId/$userId').set({
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
      'updatedAt': ServerValue.timestamp,
      'accuracy': accuracy,
    });
  }

  Future<void> clearLiveLocation({
    required String enterpriseId,
    required String userId,
  }) async {
    await _db.ref('liveLocations/$enterpriseId/$userId').remove();
  }

  Stream<DatabaseEvent> streamLiveLocations(String enterpriseId) {
    return _db.ref('liveLocations/$enterpriseId').onValue;
  }

  Stream<DatabaseEvent> streamUserLiveLocation(
      String enterpriseId, String userId) {
    return _db.ref('liveLocations/$enterpriseId/$userId').onValue;
  }

  // ── Active Stats ──

  Future<void> updateActiveStats({
    required String enterpriseId,
    required String userId,
    required int sessionDuration, // seconds
    required double distance, // km
    required int photosToday,
    required int tasksToday,
    int? sessionStartTimeMs,
  }) async {
    await _db.ref('activeStats/$enterpriseId/$userId').set({
      'sessionDuration': sessionDuration,
      'distance': distance,
      'photosToday': photosToday,
      'tasksToday': tasksToday,
      'sessionStartTimeMs': sessionStartTimeMs,
    });
  }

  Future<void> clearActiveStats({
    required String enterpriseId,
    required String userId,
  }) async {
    await _db.ref('activeStats/$enterpriseId/$userId').remove();
  }

  Stream<DatabaseEvent> streamActiveStats(String enterpriseId) {
    return _db.ref('activeStats/$enterpriseId').onValue;
  }

  Stream<DatabaseEvent> streamUserActiveStats(
      String enterpriseId, String userId) {
    return _db.ref('activeStats/$enterpriseId/$userId').onValue;
  }

  // ── Session Heartbeat ──

  Future<void> updateSessionHeartbeat({
    required String enterpriseId,
    required String userId,
    required String sessionId,
  }) async {
    await _db.ref('sessionHeartbeat/$enterpriseId/$userId').set({
      'sessionId': sessionId,
      'lastSeen': ServerValue.timestamp,
    });
  }

  Future<void> clearSessionHeartbeat({
    required String enterpriseId,
    required String userId,
  }) async {
    await _db.ref('sessionHeartbeat/$enterpriseId/$userId').remove();
  }

}
