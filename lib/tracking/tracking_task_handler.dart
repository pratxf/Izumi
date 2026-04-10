import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_activity_recognition/flutter_activity_recognition.dart'
    as ar;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../firebase_options.dart';
import 'pending_location_store.dart';
import 'sync_manager.dart';

const String _enterpriseIdKey = 'tracking.enterpriseId';
const String _employeeIdKey = 'tracking.employeeId';
const String _sessionIdKey = 'tracking.sessionId';
const String _startedAtKey = 'tracking.startedAtMs';
const String _employeeNameKey = 'tracking.employeeName';

@pragma('vm:entry-point')
void startTrackingCallback() {
  FlutterForegroundTask.setTaskHandler(SessionTrackingTaskHandler());
}

class SessionTrackingTaskHandler extends TaskHandler {
  final PendingLocationStore _pendingLocationStore =
      PendingLocationStore.instance;
  late final FirebaseFirestore _firestore;
  late final FirebaseDatabase _database;
  late final SyncManager _syncManager;

  StreamSubscription<ar.Activity>? _activitySubscription;
  Timer? _heartbeatTimer;
  Timer? _activityTimeoutTimer;

  String? _enterpriseId;
  String? _employeeId;
  String? _sessionId;
  String? _employeeName;
  int? _startedAtMs;

  int? _taskStartedAtMs; // when this task handler instance started (for restart guard)

  Position? _lastPosition;
  double _totalDistanceKm = 0;
  Duration _pollInterval = const Duration(minutes: 1);
  LocationAccuracy _accuracy = LocationAccuracy.medium;
  String _activityType = 'WALKING';
  int _activityConfidence = 0;
  bool _pollInFlight = false;

  // Quality filter constants
  // Indoor/desk workers can have GPS accuracy worse than 30m — use a generous
  // threshold so stationary sessions still record location data.
  static const double _maxAccuracyMeters = 100.0;
  static const double _maxSpeedMps = 55.6; // 200 km/h — covers all realistic vehicles with margin
  static const double _minMovementMeters = 15.0; // discard GPS jitter

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _taskStartedAtMs = DateTime.now().millisecondsSinceEpoch;
    await _ensureFirebase();
    _firestore = FirebaseFirestore.instance;
    _database = FirebaseDatabase.instance;
    _syncManager = SyncManager(
      pendingLocationStore: _pendingLocationStore,
      firestore: _firestore,
      realtimeDatabase: _database,
      onEvent: _sendGenericEvent,
    );
    await _loadContext();
    await _restoreSessionState();
    await _startSyncManager();
    await _startActivityRecognition();
    await _sendHeartbeat();
    // Heartbeat every 25 minutes per spec
    _heartbeatTimer = Timer.periodic(
      const Duration(minutes: 25),
      (_) => unawaited(_sendHeartbeat()),
    );
    await _pollLocation(reason: 'service_start');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    unawaited(_pollLocation(reason: 'scheduled_poll'));
  }

  @override
  void onReceiveData(Object data) {
    if (data is! Map) return;

    final type = data['type']?.toString();
    switch (type) {
      case 'refresh_context':
        _enterpriseId = data['enterpriseId']?.toString() ?? _enterpriseId;
        _employeeId = data['employeeId']?.toString() ?? _employeeId;
        _sessionId = data['sessionId']?.toString() ?? _sessionId;
        _employeeName = data['employeeName']?.toString() ?? _employeeName;
        final refreshStartMs = data['startTimeMs'];
        if (refreshStartMs is int) _startedAtMs = refreshStartMs;
        final enterpriseId = _enterpriseId;
        final employeeId = _employeeId;
        final sessionId = _sessionId;
        if (enterpriseId != null && employeeId != null && sessionId != null) {
          unawaited(
            _syncManager.updateContext(
              enterpriseId: enterpriseId,
              employeeId: employeeId,
              sessionId: sessionId,
            ),
          );
        }
        break;
      case 'heartbeat':
        unawaited(_sendHeartbeat());
        break;
      case 'poll_now':
        unawaited(_pollLocation(reason: 'manual_poll'));
        break;
      case 'flush_now':
        unawaited(
          _runFlushCommand(
            requestId: data['requestId']?.toString(),
            reason: 'manual_flush',
          ),
        );
        break;
      case 'final_flush':
        unawaited(
          _runFlushCommand(
            requestId: data['requestId']?.toString(),
            reason: 'final_flush',
          ),
        );
        break;
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _activitySubscription?.cancel();
    _heartbeatTimer?.cancel();
    _activityTimeoutTimer?.cancel();

    // Auto-end on app removal from recents.
    // All Firebase writes are fire-and-forget — Android kills the process
    // ~5 seconds after onDestroy, so we must not await network I/O.
    final sessionId = _sessionId;
    final enterpriseId = _enterpriseId;
    final employeeId = _employeeId;

    if (sessionId != null && enterpriseId != null && employeeId != null) {
      // If context was cleared or marked as 'ending' from shared storage,
      // this is a normal session end (not an app kill). Skip auto-end to
      // avoid duplicate notifications.
      final storedSessionId = await FlutterForegroundTask.getData<String>(
        key: _sessionIdKey,
      );
      final sessionStatus = await FlutterForegroundTask.getData<String>(
        key: 'tracking.sessionStatus',
      );
      if (storedSessionId == null || storedSessionId.isEmpty || sessionStatus == 'ending') {
        debugPrint(
          '[TrackingTaskHandler] onDestroy: context cleared or ending, '
          'skipping auto-end (normal session end).',
        );
        unawaited(_syncManager.dispose());
        return;
      }

      // Safety: don't auto-end if this task handler instance just started
      // (< 30s ago). Uses _taskStartedAtMs (when onStart ran), not
      // _startedAtMs (session start time), so it correctly skips auto-end
      // when the OEM restarts the foreground service mid-session.
      final taskStartMs = _taskStartedAtMs;
      if (taskStartMs != null) {
        final elapsed = DateTime.now().millisecondsSinceEpoch - taskStartMs;
        if (elapsed < 30000) {
          debugPrint(
            '[TrackingTaskHandler] onDestroy: task handler only ${elapsed}ms old, '
            'skipping auto-end (likely an OEM restart).',
          );
          unawaited(_syncManager.dispose());
          return;
        }
      }

      // Skip location buffer flush — too slow for Android's kill window.
      // Pending SQLite locations are acceptable to lose on task removal.

      // Fire-and-forget: write session end to Firestore
      final now = DateTime.now();
      final durationSecs = _sessionDurationSeconds();
      unawaited(
        _firestore.collection('sessions').doc(sessionId).set({
          'endTime': Timestamp.fromDate(now),
          'status': 'auto_ended',
          'totalDuration': durationSecs,
          'totalDistance': _totalDistanceKm,
          'autoEndReason': 'app_removed',
          'autoEndSource': 'foreground_task_onDestroy',
        }, SetOptions(merge: true)).catchError((e) {
          debugPrint('[TrackingTaskHandler] onDestroy session write failed: $e');
        }),
      );

      // Fire-and-forget: write activityLog
      unawaited(
        _firestore.collection('activityLogs').doc('session_auto_ended_$sessionId').set({
          'enterpriseId': enterpriseId,
          'employeeId': employeeId,
          'sessionId': sessionId,
          'orgId': enterpriseId,
          'type': 'session_auto_ended',
          'title': 'Session Auto-Ended',
          'detail': 'Session ended because the app was closed',
          'timestamp': FieldValue.serverTimestamp(),
          'date': _todayDateString(),
          'payload': {
            'endTime': Timestamp.fromDate(now),
            'durationSeconds': durationSecs,
            'distanceKm': _totalDistanceKm,
            'endReason': 'app_removed',
          },
        }, SetOptions(merge: true)).catchError((e) {
          debugPrint('[TrackingTaskHandler] onDestroy activityLog write failed: $e');
        }),
      );

      // Fire-and-forget: cancel onDisconnect handler before writing presence
      // so the signal_lost ghost write doesn't fire after our cleanup.
      unawaited(
        _database.ref('presence/$enterpriseId/$employeeId')
            .onDisconnect().cancel().catchError((e) {
          debugPrint('[TrackingTaskHandler] onDestroy onDisconnect cancel failed: $e');
        }),
      );

      // Fire-and-forget: set presence to offline (not signal_lost — this is
      // a clean auto-end, not an unexpected death) and clear dashboard nodes.
      unawaited(
        _database.ref().update({
          'presence/$enterpriseId/$employeeId/status': 'offline',
          'presence/$enterpriseId/$employeeId/signalLostAt': null,
          'presence/$enterpriseId/$employeeId/currentSessionId': null,
          'presence/$enterpriseId/$employeeId/lastSeen': ServerValue.timestamp,
          'activeStats/$enterpriseId/$employeeId': null,
          'sessionHeartbeat/$enterpriseId/$employeeId': null,
          'liveLocations/$enterpriseId/$employeeId': null,
        }).catchError((e) {
          debugPrint('[TrackingTaskHandler] onDestroy RTDB update failed: $e');
        }),
      );

      // Send local push notification to employee
      try {
        final duration = Duration(seconds: _sessionDurationSeconds());
        final hours = duration.inHours;
        final minutes = duration.inMinutes.remainder(60);
        final durationText = hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';

        final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
        await flutterLocalNotificationsPlugin.initialize(
          const InitializationSettings(
            android: AndroidInitializationSettings('ic_stat_izumi'),
            iOS: DarwinInitializationSettings(),
          ),
        );
        await flutterLocalNotificationsPlugin.show(
          9901,
          'Session Ended',
          'Your tracking session has ended because the app was closed. Duration: $durationText.',
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'izumi_session_alerts',
              'Session Alerts',
              channelDescription: 'Notifications about session lifecycle events',
              importance: Importance.high,
              priority: Priority.high,
              icon: 'ic_stat_izumi',
            ),
            iOS: DarwinNotificationDetails(),
          ),
        );
      } catch (e) {
        debugPrint('[TrackingTaskHandler] onDestroy notification failed: $e');
      }

      // Fire-and-forget: clear session state from SQLite
      unawaited(
        _pendingLocationStore.markSessionEnding().catchError((e) {
          debugPrint('[TrackingTaskHandler] onDestroy markSessionEnding failed: $e');
        }),
      );
    }

    unawaited(_syncManager.dispose());
  }

  // ── Firebase init ──

  Future<void> _ensureFirebase() async {
    if (Firebase.apps.isNotEmpty) return;
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  // ── Context loading ──

  Future<void> _loadContext() async {
    _enterpriseId = await FlutterForegroundTask.getData<String>(
      key: _enterpriseIdKey,
    );
    _employeeId = await FlutterForegroundTask.getData<String>(
      key: _employeeIdKey,
    );
    _sessionId = await FlutterForegroundTask.getData<String>(
      key: _sessionIdKey,
    );
    _startedAtMs = await FlutterForegroundTask.getData<int>(key: _startedAtKey);
    _employeeName = await FlutterForegroundTask.getData<String>(
      key: _employeeNameKey,
    );
  }

  // ── Session state crash recovery ──

  Future<void> _restoreSessionState() async {
    // First try restoring from SQLite session_state table
    final state = await _pendingLocationStore.getSessionState();
    if (state != null && state['status'] == 'active') {
      _sessionId ??= state['session_id'] as String?;
      _employeeId ??= state['employee_id'] as String?;
      _enterpriseId ??= state['enterprise_id'] as String?;
      _startedAtMs ??= (state['start_time_ms'] as num?)?.toInt();
      _totalDistanceKm =
          ((state['total_distance_km'] as num?) ?? 0).toDouble();

      final lastLat = state['last_lat'] as double?;
      final lastLng = state['last_lng'] as double?;
      if (lastLat != null && lastLng != null) {
        _lastPosition = Position(
          latitude: lastLat,
          longitude: lastLng,
          timestamp: DateTime.fromMillisecondsSinceEpoch(
            (state['last_synced_at_ms'] as num?)?.toInt() ??
                DateTime.now().millisecondsSinceEpoch,
          ),
          accuracy: 0,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 0,
          speedAccuracy: 0,
          isMocked: false,
        );
      }
      return;
    }

    // Fallback: restore from pending_locations table
    if (_sessionId == null) return;

    final latestPoint =
        await _pendingLocationStore.getLatestPointForSession(_sessionId!);
    if (latestPoint == null) return;

    _lastPosition = Position(
      longitude: (latestPoint['longitude'] as num).toDouble(),
      latitude: (latestPoint['latitude'] as num).toDouble(),
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        latestPoint['captured_at_ms'] as int,
      ),
      accuracy: ((latestPoint['accuracy'] as num?) ?? 0).toDouble(),
      altitude: 0,
      altitudeAccuracy: 0,
      heading: ((latestPoint['heading'] as num?) ?? 0).toDouble(),
      headingAccuracy: 0,
      floor: null,
      speed: ((latestPoint['speed'] as num?) ?? 0).toDouble(),
      speedAccuracy: 0,
      isMocked: false,
    );
    _totalDistanceKm =
        ((latestPoint['cumulative_distance_km'] as num?) ?? 0).toDouble();
  }

  // ── Sync manager ──

  Future<void> _startSyncManager() async {
    final enterpriseId = _enterpriseId;
    final employeeId = _employeeId;
    final sessionId = _sessionId;
    if (enterpriseId == null || employeeId == null || sessionId == null) return;

    await _syncManager.start(
      enterpriseId: enterpriseId,
      employeeId: employeeId,
      sessionId: sessionId,
    );

    // Save initial session state for crash recovery
    await _pendingLocationStore.saveSessionState(
      sessionId: sessionId,
      employeeId: employeeId,
      enterpriseId: enterpriseId,
      startTimeMs: _startedAtMs ?? DateTime.now().millisecondsSinceEpoch,
      totalDistanceKm: _totalDistanceKm,
    );
  }

  // ── Activity recognition ──

  Future<void> _startActivityRecognition() async {
    try {
      _activitySubscription = ar
          .FlutterActivityRecognition.instance.activityStream
          .listen(_handleActivityChange);

      // If no activity emitted within 30 seconds, default to WALKING
      _activityTimeoutTimer = Timer(const Duration(seconds: 30), () {
        if (_activityType == 'WALKING' && _activityConfidence == 0) {
          // Still on defaults — activity recognition never emitted
          unawaited(_setTrackingProfile(
            activityType: 'WALKING',
            confidence: 0,
          ));
        }
      });
    } catch (error, stackTrace) {
      debugPrint(
        '[SessionTrackingTaskHandler] activity stream unavailable: $error\n$stackTrace',
      );
      await _setTrackingProfile(activityType: 'WALKING', confidence: 0);
    }
  }

  void _handleActivityChange(ar.Activity activity) {
    _activityTimeoutTimer?.cancel();
    unawaited(_setTrackingProfile(
      activityType: activity.type.name.toUpperCase(),
      confidence: _confidenceScore(activity.confidence),
    ));
  }

  Future<void> _setTrackingProfile({
    required String activityType,
    required int confidence,
  }) async {
    final previousInterval = _pollInterval;

    _activityType = activityType;
    _activityConfidence = confidence;

    // Spec intervals:
    // STILL → 5 min, medium accuracy
    // WALKING / ON_FOOT / unknown → 60s, medium accuracy
    // IN_VEHICLE / ON_BICYCLE → 20s, high accuracy
    if (activityType == 'STILL') {
      _pollInterval = const Duration(minutes: 5);
      _accuracy = LocationAccuracy.medium;
    } else if (activityType == 'IN_VEHICLE' || activityType == 'ON_BICYCLE') {
      _pollInterval = const Duration(seconds: 20);
      _accuracy = LocationAccuracy.high;
    } else {
      // WALKING, ON_FOOT, RUNNING, unknown
      _pollInterval = const Duration(seconds: 60);
      _accuracy = LocationAccuracy.medium;
    }

    if (previousInterval != _pollInterval) {
      await FlutterForegroundTask.updateService(
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction:
              ForegroundTaskEventAction.repeat(_pollInterval.inMilliseconds),
          autoRunOnBoot: false,
          autoRunOnMyPackageReplaced: true,
          allowWakeLock: true,
          allowWifiLock: true,
        ),
        notificationTitle: _buildNotificationTitle(),
        notificationText: _buildNotificationText(),
      );
    }

    _sendStateToMain();
  }

  // ── GPS polling ──

  Future<void> _pollLocation({required String reason}) async {
    if (_pollInFlight ||
        _sessionId == null ||
        _employeeId == null ||
        _enterpriseId == null) {
      return;
    }

    _pollInFlight = true;
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: _buildLocationSettings(),
      ).timeout(const Duration(seconds: 30));

      if (!_isUsableFix(position)) return;

      // Distance quality filters (order: movement → timestamp → speed → accumulate)
      if (_lastPosition != null) {
        final meters = Geolocator.distanceBetween(
          _lastPosition!.latitude,
          _lastPosition!.longitude,
          position.latitude,
          position.longitude,
        );

        // 1. Minimum movement filter — discard GPS jitter
        if (meters < _minMovementMeters) return;

        // 2. Timestamp validity — reject fixes with duplicate/invalid timestamps
        final timeDiffSecs = position.timestamp
            .difference(_lastPosition!.timestamp)
            .inSeconds
            .abs();
        if (timeDiffSecs <= 0) return;

        // 3. Speed spike detection
        final speedMps = meters / timeDiffSecs;
        if (speedMps > _maxSpeedMps) return;

        _totalDistanceKm += meters / 1000;
      }

      _lastPosition = position;

      await _pendingLocationStore.insertPendingLocation(
        sessionId: _sessionId!,
        enterpriseId: _enterpriseId!,
        employeeId: _employeeId!,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        speed: position.speed,
        heading: position.heading,
        activityType: _activityType,
        activityConfidence: _activityConfidence,
        cumulativeDistanceKm: _totalDistanceKm,
        capturedAtMs: position.timestamp.millisecondsSinceEpoch,
      );

      // Persist distance to session state for crash recovery
      unawaited(_pendingLocationStore.updateSessionDistance(_totalDistanceKm));

      final pendingCount =
          await _pendingLocationStore.getPendingCountForSession(_sessionId!);

      await _updateLiveRealtimePosition(position);
      await _syncManager.maybeFlushWhenThresholdReached();

      await FlutterForegroundTask.updateService(
        notificationTitle: _buildNotificationTitle(),
        notificationText: _buildNotificationText(),
      );

      _sendStateToMain(
        position: position,
        pendingCount: pendingCount,
        reason: reason,
      );
    } on TimeoutException {
      // Spec: timeout = silent skip
    } catch (error, stackTrace) {
      debugPrint(
        '[SessionTrackingTaskHandler] location poll failed: $error\n$stackTrace',
      );
      _sendStateToMain(error: error.toString(), reason: reason);
    } finally {
      _pollInFlight = false;
    }
  }

  LocationSettings _buildLocationSettings() {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: _accuracy,
        distanceFilter: 0,
        intervalDuration: _pollInterval,
        timeLimit: const Duration(seconds: 10),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Izumi session active',
          notificationText: 'Collecting field session updates',
          enableWakeLock: true,
        ),
      );
    }

    return AppleSettings(
      accuracy: _accuracy,
      activityType: ActivityType.fitness,
      distanceFilter: 0,
      timeLimit: const Duration(seconds: 10),
      pauseLocationUpdatesAutomatically: true,
      showBackgroundLocationIndicator: true,
      allowBackgroundLocationUpdates: true,
    );
  }

  int _confidenceScore(ar.ActivityConfidence confidence) {
    switch (confidence) {
      case ar.ActivityConfidence.HIGH:
        return 100;
      case ar.ActivityConfidence.MEDIUM:
        return 70;
      case ar.ActivityConfidence.LOW:
        return 30;
    }
  }

  bool _isUsableFix(Position position) {
    if (position.accuracy <= 0) return false;
    // Always accept the first fix so stationary/indoor sessions immediately
    // show up in the dashboard and analytics, even with poor GPS.
    if (_lastPosition == null) return true;
    return position.accuracy <= _maxAccuracyMeters;
  }

  // ── Heartbeat (every 25 min) ──

  Future<void> _sendHeartbeat() async {
    if (_enterpriseId == null || _employeeId == null || _sessionId == null) {
      return;
    }

    // Validate the Firestore session is still active before writing presence.
    // This prevents ghost sessions from reappearing after admin force-end.
    try {
      final sessionDoc =
          await _firestore.collection('sessions').doc(_sessionId).get();
      if (!sessionDoc.exists || sessionDoc.data()?['status'] != 'active') {
        debugPrint(
          '[TrackingTaskHandler] heartbeat: session $_sessionId is no longer '
          'active (${sessionDoc.data()?['status']}), cleaning up and stopping.',
        );
        // Clean up RTDB presence so dashboard stops showing this employee
        // as active. Must happen BEFORE stopping the service.
        try {
          await _database.ref().update({
            'presence/$_enterpriseId/$_employeeId/status': 'offline',
            'presence/$_enterpriseId/$_employeeId/signalLostAt': null,
            'presence/$_enterpriseId/$_employeeId/currentSessionId': null,
            'presence/$_enterpriseId/$_employeeId/lastSeen':
                ServerValue.timestamp,
            'activeStats/$_enterpriseId/$_employeeId': null,
            'sessionHeartbeat/$_enterpriseId/$_employeeId': null,
            'liveLocations/$_enterpriseId/$_employeeId': null,
          });
          // Cancel onDisconnect so it doesn't write signal_lost after cleanup
          await _database
              .ref('presence/$_enterpriseId/$_employeeId')
              .onDisconnect()
              .cancel();
        } catch (e) {
          debugPrint('[TrackingTaskHandler] heartbeat RTDB cleanup failed: $e');
        }
        // Clear context so onDestroy skips auto-end
        await FlutterForegroundTask.saveData(
          key: 'tracking.sessionStatus',
          value: 'ending',
        );
        await FlutterForegroundTask.removeData(key: _sessionIdKey);
        await FlutterForegroundTask.stopService();
        return;
      }
    } catch (e) {
      // Network error — skip heartbeat but don't kill the service
      debugPrint('[TrackingTaskHandler] heartbeat validation failed: $e');
      return;
    }

    await Future.wait([
      _database.ref('sessionHeartbeat/$_enterpriseId/$_employeeId').set({
        'sessionId': _sessionId,
        'lastSeen': ServerValue.timestamp,
      }),
      _database.ref('presence/$_enterpriseId/$_employeeId').update({
        'status': 'active',
        'signalLostAt': null,
        'currentSessionId': _sessionId,
        'lastSeen': ServerValue.timestamp,
      }),
    ]);

    _sendStateToMain(reason: 'heartbeat');
  }

  // ── RTDB live position ──

  Future<void> _updateLiveRealtimePosition(Position position) async {
    if (_enterpriseId == null || _employeeId == null) return;

    final address = await _reverseGeocode(position.latitude, position.longitude);

    await Future.wait([
      _database.ref('liveLocations/$_enterpriseId/$_employeeId').set({
        'latitude': position.latitude,
        'longitude': position.longitude,
        'address': address,
        'updatedAt': ServerValue.timestamp,
        'accuracy': position.accuracy,
      }),
      _database.ref('activeStats/$_enterpriseId/$_employeeId').update({
        'distance': _totalDistanceKm,
        'sessionDuration': _sessionDurationSeconds(),
        'sessionStartTimeMs': _startedAtMs,
      }),
    ]);
  }

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
      debugPrint('[TrackingTaskHandler] reverse geocode failed: $e');
    }
    return 'Lat: ${lat.toStringAsFixed(4)}, Lng: ${lng.toStringAsFixed(4)}';
  }

  // ── Flush commands ──

  Future<void> _runFlushCommand({
    required String? requestId,
    required String reason,
  }) async {
    if (reason == 'final_flush') {
      await _pollLocation(reason: 'final_flush_snapshot');
    }

    final result = await _syncManager.flushPendingLocations(
      reason: reason,
      allowOfflineQueue: reason == 'final_flush',
    );

    // Update last sync time in session state
    unawaited(
      _pendingLocationStore
          .updateSessionLastSync(DateTime.now().millisecondsSinceEpoch),
    );

    _sendGenericEvent({
      'type': 'command_result',
      'command': reason,
      'requestId': requestId,
      ...result,
      'distanceKm': result['distanceKm'] ?? _totalDistanceKm,
      'sessionDurationSeconds': _sessionDurationSeconds(),
      'lastLocationUpdateMs': _lastPosition?.timestamp.millisecondsSinceEpoch,
      'latitude': _lastPosition?.latitude,
      'longitude': _lastPosition?.longitude,
    });
  }

  // ── Notification formatting ──

  String _buildNotificationTitle() {
    return 'Tracking active';
  }

  String _buildNotificationText() {
    final name = _employeeName ?? 'Employee';
    final duration = Duration(seconds: _sessionDurationSeconds());
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final durationText = '${hours}h ${minutes.toString().padLeft(2, '0')}m';
    final distanceText = '${_totalDistanceKm.toStringAsFixed(1)} km';
    return '$name \u00b7 $durationText \u00b7 $distanceText';
  }

  // ── Helpers ──

  int _sessionDurationSeconds() {
    final startedAtMs = _startedAtMs;
    if (startedAtMs == null) return 0;
    return Duration(
      milliseconds: DateTime.now().millisecondsSinceEpoch - startedAtMs,
    ).inSeconds;
  }

  String _todayDateString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  void _sendGenericEvent(Map<String, dynamic> payload) {
    FlutterForegroundTask.sendDataToMain(payload);
  }

  void _sendStateToMain({
    Position? position,
    int? pendingCount,
    String? error,
    String? reason,
  }) {
    FlutterForegroundTask.sendDataToMain({
      'type': 'tracking_state',
      'reason': reason,
      'error': error,
      'sessionId': _sessionId,
      'employeeId': _employeeId,
      'enterpriseId': _enterpriseId,
      'activityType': _activityType,
      'activityConfidence': _activityConfidence,
      'distanceKm': _totalDistanceKm,
      'pendingCount': pendingCount,
      'latitude': position?.latitude ?? _lastPosition?.latitude,
      'longitude': position?.longitude ?? _lastPosition?.longitude,
      'accuracy': position?.accuracy ?? _lastPosition?.accuracy,
      'lastLocationUpdateMs':
          (position ?? _lastPosition)?.timestamp.millisecondsSinceEpoch,
    });
  }
}
