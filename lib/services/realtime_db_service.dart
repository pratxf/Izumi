import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

class RealtimeDbService {
  final FirebaseDatabase _db = FirebaseDatabase.instance;

  // ── Presence ──

  Future<void> setPresence({
    required String enterpriseId,
    required String userId,
    required String status, // 'active' | 'break' | 'offline'
    String? currentSessionId,
  }) async {
    await _db.ref('presence/$enterpriseId/$userId').set({
      'status': status,
      'lastSeen': ServerValue.timestamp,
      'currentSessionId': currentSessionId,
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
    });
  }

  /// Registers an onDisconnect handler that sets presence to offline when
  /// the RTDB connection drops.
  Future<void> setupOfflineOnDisconnect({
    required String enterpriseId,
    required String userId,
    String? currentSessionId,
  }) async {
    await _db.ref('presence/$enterpriseId/$userId').onDisconnect().update({
      'status': 'offline',
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

  /// Records the latest known connectivity transition under
  /// `presence/{eid}/{uid}/lastConnectivity`. The server-side sweep uses this
  /// to distinguish "app dead" (online but no heartbeat) from "in a no-network
  /// zone" (offline but still tracking locally).
  ///
  /// If the device is already offline this write will fail silently — the
  /// previously recorded "online" state is enough for the sweep to know when
  /// the device last had network access.
  Future<void> recordConnectivityChange({
    required String enterpriseId,
    required String userId,
    required bool isOnline,
  }) async {
    await _db.ref('presence/$enterpriseId/$userId/lastConnectivity').set({
      'state': isOnline ? 'online' : 'offline',
      'changedAt': ServerValue.timestamp,
    });
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
    final path = 'liveLocations/$enterpriseId/$userId';
    final payload = {
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
      'updatedAt': ServerValue.timestamp,
      'accuracy': accuracy,
    };
    try {
      await _db.ref(path).set(payload);
      debugPrint('[RealtimeDbService] updateLiveLocation OK path=$path '
          'lat=$latitude lng=$longitude acc=$accuracy addr.len=${address.length}');
    } catch (e) {
      // FIX 7: surface RTDB write failures so the v4 "No location data"
      // regression is diagnosable. The most common cause is a missing /
      // stale Firebase Auth ID token after migration; force-refresh it and
      // retry once.
      debugPrint('[RealtimeDbService] updateLiveLocation failed: $e — '
          'refreshing auth and retrying');
      try {
        await FirebaseAuth.instance.currentUser?.getIdToken(true);
        await _db.ref(path).set(payload);
        debugPrint('[RealtimeDbService] updateLiveLocation retry OK path=$path');
      } catch (retryErr) {
        debugPrint('[RealtimeDbService] updateLiveLocation retry failed: '
            '$retryErr');
        rethrow;
      }
    }
  }

  Future<void> clearLiveLocation({
    required String enterpriseId,
    required String userId,
  }) async {
    await _db.ref('liveLocations/$enterpriseId/$userId').remove();
  }

  Stream<DatabaseEvent> streamLiveLocations(String enterpriseId) {
    final path = 'liveLocations/$enterpriseId';
    debugPrint('[RealtimeDbService] streamLiveLocations subscribing path=$path');
    return _db.ref(path).onValue.map((event) {
      final value = event.snapshot.value;
      final count = value is Map ? value.length : 0;
      debugPrint('[RealtimeDbService] streamLiveLocations emit path=$path '
          'type=${value.runtimeType} entries=$count');
      return event;
    });
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

  /// Overwrites activeStats with clean zero values and a fresh server timestamp
  /// for sessionStartTimeMs. Must be the first RTDB write on session start.
  Future<void> initializeActiveStats({
    required String enterpriseId,
    required String userId,
  }) async {
    await _db.ref('activeStats/$enterpriseId/$userId').set({
      'sessionDuration': 0,
      'distance': 0.0,
      'photosToday': 0,
      'tasksToday': 0,
      'sessionStartTimeMs': ServerValue.timestamp,
    });
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
