import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';

import 'pending_location_store.dart';

typedef SyncEventCallback = void Function(Map<String, dynamic> payload);

class SyncManager {
  SyncManager({
    required PendingLocationStore pendingLocationStore,
    required FirebaseFirestore firestore,
    required FirebaseDatabase realtimeDatabase,
    required SyncEventCallback onEvent,
  })  : _pendingLocationStore = pendingLocationStore,
        _firestore = firestore,
        _realtimeDatabase = realtimeDatabase,
        _onEvent = onEvent;

  static const int flushThreshold = 20;
  static const Duration flushInterval = Duration(minutes: 20);

  final PendingLocationStore _pendingLocationStore;
  final FirebaseFirestore _firestore;
  final FirebaseDatabase _realtimeDatabase;
  final SyncEventCallback _onEvent;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _periodicFlushTimer;

  String? _enterpriseId;
  String? _employeeId;
  String? _sessionId;
  bool _isOnline = true;
  bool _flushInFlight = false;
  DateTime? _lastFlushAt;

  Future<void> start({
    required String enterpriseId,
    required String employeeId,
    required String sessionId,
  }) async {
    _enterpriseId = enterpriseId;
    _employeeId = employeeId;
    _sessionId = sessionId;

    final connectivityResults = await Connectivity().checkConnectivity();
    _isOnline = _hasNetwork(connectivityResults);

    await _connectivitySubscription?.cancel();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      results,
    ) {
      final wasOnline = _isOnline;
      _isOnline = _hasNetwork(results);
      if (!wasOnline && _isOnline) {
        unawaited(_restorePresenceAndFlush(reason: 'reconnected'));
      }
    });

    _periodicFlushTimer?.cancel();
    _periodicFlushTimer = Timer.periodic(flushInterval, (_) {
      unawaited(flushPendingLocations(reason: 'periodic_flush'));
    });
  }

  Future<void> updateContext({
    required String enterpriseId,
    required String employeeId,
    required String sessionId,
  }) async {
    _enterpriseId = enterpriseId;
    _employeeId = employeeId;
    _sessionId = sessionId;
  }

  Future<void> maybeFlushWhenThresholdReached() async {
    final sessionId = _sessionId;
    if (sessionId == null) {
      return;
    }

    final pendingCount = await _pendingLocationStore.getPendingCountForSession(
      sessionId,
    );
    if (pendingCount >= flushThreshold) {
      _onEvent({
        'type': 'sync_status',
        'sessionId': sessionId,
        'employeeId': _employeeId,
        'enterpriseId': _enterpriseId,
        'status': 'buffer_threshold_reached',
        'reason': 'buffer_threshold',
        'points': pendingCount,
      });
    }
  }

  Future<Map<String, dynamic>> flushPendingLocations({
    required String reason,
    bool allowOfflineQueue = false,
  }) async {
    final sessionId = _sessionId;
    final enterpriseId = _enterpriseId;
    final employeeId = _employeeId;

    if (sessionId == null || enterpriseId == null || employeeId == null) {
      return {
        'flushed': false,
        'reason': reason,
        'error': 'Missing sync context.',
      };
    }

    if (_flushInFlight) {
      return {
        'flushed': false,
        'reason': reason,
        'skipped': 'flush_in_flight',
      };
    }

    if (!_isOnline && !allowOfflineQueue) {
      return {
        'flushed': false,
        'reason': reason,
        'skipped': 'offline',
      };
    }

    _flushInFlight = true;
    try {
      final rows = await _pendingLocationStore.getPendingLocationsForSession(
        sessionId,
      );

      if (rows.isEmpty) {
        _lastFlushAt = DateTime.now();
        return {
          'flushed': true,
          'reason': reason,
          'points': 0,
          'distanceKm': null,
        };
      }

      final batch = _firestore.batch();
      double latestDistanceKm = 0;
      final rowIds = <int>[];
      Map<String, dynamic>? latestRow;

      for (final row in rows) {
        final rowId = row['id'];
        if (rowId is int) {
          rowIds.add(rowId);
        }

        latestDistanceKm =
            ((row['cumulative_distance_km'] as num?) ?? 0).toDouble();
        latestRow = row;
      }

      if (latestRow != null) {
        final lat = (latestRow['latitude'] as num).toDouble();
        final lng = (latestRow['longitude'] as num).toDouble();
        final address = await _reverseGeocode(lat, lng);

        final locationRef = _firestore
            .collection('sessions')
            .doc(sessionId)
            .collection('locations')
            .doc();

        batch.set(locationRef, {
          'latitude': lat,
          'longitude': lng,
          'address': address,
          'timestamp': Timestamp.fromMillisecondsSinceEpoch(
            latestRow['captured_at_ms'] as int,
          ),
          'type': 'location_update',
          'title': 'Tracked Location',
          'accuracy': ((latestRow['accuracy'] as num?) ?? 0).toDouble(),
          'speed': ((latestRow['speed'] as num?) ?? 0).toDouble(),
          'heading': ((latestRow['heading'] as num?) ?? 0).toDouble(),
          'activityType': latestRow['activity_type'],
          'activityConfidence': latestRow['activity_confidence'],
          'distanceKm': latestDistanceKm,
          'capturedAtMs': latestRow['captured_at_ms'],
          'bufferedPointCount': rows.length,
        });
      }

      batch.set(
          _firestore.collection('sessions').doc(sessionId),
          {
            'totalDistance': latestDistanceKm,
            'lastSyncAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));

      await batch.commit();
      await _pendingLocationStore.deleteRowsByIds(rowIds);
      _lastFlushAt = DateTime.now();

      // Write one activityLogs entry so the analytics timeline shows location
      // data. We write the latest position only (not one per buffered point) to
      // avoid feed spam.
      if (latestRow != null) {
        final lat = (latestRow['latitude'] as num).toDouble();
        final lng = (latestRow['longitude'] as num).toDouble();
        final address = await _reverseGeocode(lat, lng);
        final now = DateTime.now();
        final dateStr =
            '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
        unawaited(
          _firestore.collection('activityLogs').add({
            'enterpriseId': enterpriseId,
            'employeeId': employeeId,
            'sessionId': sessionId,
            'orgId': enterpriseId,
            'type': 'location_update',
            'title': 'Tracked Location',
            'detail': address,
            'timestamp': Timestamp.fromMillisecondsSinceEpoch(
              latestRow['captured_at_ms'] as int,
            ),
            'date': dateStr,
            'payload': {
              'lat': lat,
              'lng': lng,
              'address': address,
              'accuracyMeters':
                  ((latestRow['accuracy'] as num?) ?? 0).toDouble(),
            },
            'metadata': {
              'latitude': lat,
              'longitude': lng,
              'address': address,
              'accuracy':
                  ((latestRow['accuracy'] as num?) ?? 0).toDouble(),
              'activityType': latestRow['activity_type'],
              'distanceKm': latestDistanceKm,
              'bufferedPoints': rows.length,
              'source': 'foreground_service_flush',
            },
          }),
        );
      }

      _onEvent({
        'type': 'sync_status',
        'sessionId': sessionId,
        'employeeId': employeeId,
        'enterpriseId': enterpriseId,
        'status': 'flushed',
        'reason': reason,
        'points': rows.length,
        'distanceKm': latestDistanceKm,
        'flushedAtMs': _lastFlushAt!.millisecondsSinceEpoch,
      });

      return {
        'flushed': true,
        'reason': reason,
        'points': rows.length,
        'distanceKm': latestDistanceKm,
      };
    } catch (error, stackTrace) {
      debugPrint('[SyncManager] flush failed: $error\n$stackTrace');
      _onEvent({
        'type': 'sync_status',
        'sessionId': sessionId,
        'employeeId': employeeId,
        'enterpriseId': enterpriseId,
        'status': 'flush_failed',
        'reason': reason,
        'error': error.toString(),
      });
      return {
        'flushed': false,
        'reason': reason,
        'error': error.toString(),
      };
    } finally {
      _flushInFlight = false;
    }
  }

  Future<void> dispose() async {
    await _connectivitySubscription?.cancel();
    _periodicFlushTimer?.cancel();
  }

  Future<void> _restorePresenceAndFlush({required String reason}) async {
    final enterpriseId = _enterpriseId;
    final employeeId = _employeeId;
    final sessionId = _sessionId;

    if (enterpriseId == null || employeeId == null || sessionId == null) {
      return;
    }

    await _realtimeDatabase.ref('presence/$enterpriseId/$employeeId').update({
      'status': 'active',
      'signalLostAt': null,
      'currentSessionId': sessionId,
      'lastSeen': ServerValue.timestamp,
    });

    await flushPendingLocations(reason: reason);
  }

  bool _hasNetwork(List<ConnectivityResult> results) {
    return results.any((result) => result != ConnectivityResult.none);
  }

  /// Reverse geocode coordinates into a human-readable address.
  /// Falls back to compact "lat, lng" on failure.
  static Future<String> _reverseGeocode(double lat, double lng) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng)
          .timeout(const Duration(seconds: 5));
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        final parts = <String>[];
        // Include street/thoroughfare for pin-point accuracy
        if (place.street?.isNotEmpty == true &&
            place.street != place.locality &&
            place.street != place.subLocality) {
          parts.add(place.street!);
        } else if (place.thoroughfare?.isNotEmpty == true) {
          parts.add(place.thoroughfare!);
        } else if (place.name?.isNotEmpty == true &&
            place.name != place.locality &&
            place.name != place.subLocality) {
          parts.add(place.name!);
        }
        if (place.subLocality?.isNotEmpty == true) parts.add(place.subLocality!);
        if (place.locality?.isNotEmpty == true) parts.add(place.locality!);
        if (parts.isNotEmpty) return parts.join(', ');
      }
    } catch (e) {
      debugPrint('[SyncManager] reverse geocode failed: $e');
    }
    return 'Lat: ${lat.toStringAsFixed(4)}, Lng: ${lng.toStringAsFixed(4)}';
  }
}
