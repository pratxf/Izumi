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
import 'package:shared_preferences/shared_preferences.dart';

import '../firebase_options.dart';
import '../services/diagnostic_logger.dart';
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
  Timer? _sevenPmReminderTimer;

  /// Fixed ID for the daily 7 PM IST session reminder so it can be cancelled.
  static const int sevenPmReminderNotificationId = 9001;

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
  // Tightened to reduce GPS-jitter-driven distance inflation. The first fix
  // is always accepted (see [_isUsableFix]) so stationary/indoor sessions
  // still register on the dashboard even with poor accuracy.
  static const double _maxAccuracyMeters = 40.0;
  static const double _maxSpeedMps = 25.0; // 90 km/h
  static const double _minMovementMeters = 30.0; // above GPS noise floor

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
    await DiagnosticLogger.I.init();
    DiagnosticLogger.I.setSessionId(_sessionId);
    DiagnosticLogger.I.log('service_started', {
      'sessionId': _sessionId,
      'employeeId': _employeeId,
    });
    await _startSyncManager();
    await _startActivityRecognition();
    await _sendHeartbeat();
    // Heartbeat every 15 minutes — more frequent proof-of-life without
    // significant RTDB write cost.
    _heartbeatTimer = Timer.periodic(
      const Duration(minutes: 15),
      (_) => unawaited(_sendHeartbeat()),
    );
    _scheduleSevenPmReminder();
    await _pollLocation(reason: 'service_start');
  }

  // ── 7 PM IST daily session reminder ──
  //
  // Computes ms until the next 19:00 IST (Asia/Kolkata, UTC+05:30) and
  // schedules a one-shot Timer. When it fires, a local notification is
  // shown and the timer re-schedules itself for 24 h later.
  //
  // All math is done in UTC to avoid device-local-time drift.

  void _scheduleSevenPmReminder() {
    _sevenPmReminderTimer?.cancel();

    final delay = _msUntilNextSevenPmIst();
    _sevenPmReminderTimer = Timer(delay, () async {
      await _showSevenPmReminderNotification();
      // Re-schedule for the following day.
      _scheduleSevenPmReminder();
    });
  }

  Duration _msUntilNextSevenPmIst() {
    // IST is fixed UTC+05:30 — no DST.
    const istOffsetMs = (5 * 60 + 30) * 60 * 1000;
    final nowUtcMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    final nowIstMs = nowUtcMs + istOffsetMs;

    // Interpret the shifted ms as a UTC DateTime whose calendar fields
    // represent the IST wall-clock date/time.
    final nowIst = DateTime.fromMillisecondsSinceEpoch(nowIstMs, isUtc: true);

    // Build today's 7 PM wall-clock time in IST.
    var target19Ist = DateTime.utc(
      nowIst.year,
      nowIst.month,
      nowIst.day,
      19,
      0,
      0,
    );

    // If it's already past 7 PM IST today, schedule for tomorrow.
    if (!target19Ist.isAfter(nowIst)) {
      target19Ist = target19Ist.add(const Duration(days: 1));
    }

    // Convert the IST wall-clock target back to real UTC ms.
    final targetUtcMs = target19Ist.millisecondsSinceEpoch - istOffsetMs;
    final delayMs = targetUtcMs - nowUtcMs;
    return Duration(milliseconds: delayMs.clamp(0, 24 * 3600 * 1000));
  }

  Future<void> _showSevenPmReminderNotification() async {
    try {
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_izumi'),
          iOS: DarwinInitializationSettings(),
        ),
      );
      await plugin.show(
        sevenPmReminderNotificationId,
        'Active session reminder',
        'You have an active session running. '
            'Please end your session if you\u2019re done for the day.',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'izumi_session_alerts',
            'Session Alerts',
            channelDescription:
                'Notifications about session lifecycle events',
            importance: Importance.high,
            priority: Priority.high,
            icon: 'ic_stat_izumi',
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
    } catch (e) {
      debugPrint('[TrackingTaskHandler] 7 PM reminder notification failed: $e');
    }
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
    DiagnosticLogger.I.log('service_destroyed', {
      'isTimeout': isTimeout,
      'sessionId': _sessionId,
    }, 'critical');
    _activitySubscription?.cancel();
    _heartbeatTimer?.cancel();
    _activityTimeoutTimer?.cancel();
    _sevenPmReminderTimer?.cancel();

    // Cancel any pending 7 PM reminder so it doesn't fire after session ends.
    unawaited(() async {
      try {
        await FlutterLocalNotificationsPlugin()
            .cancel(sevenPmReminderNotificationId);
      } catch (_) {}
    }());

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

      // Check if user intentionally backgrounded — skip auto-end if so.
      // The flag is set by the PopScope "Exit" dialog in the shells via
      // [SessionTaskGuard.setIntentionalBackground], stored in Flutter's
      // SharedPreferences. Always cleared after reading so it never persists
      // across multiple OEM-kill cycles.
      try {
        final prefs = await SharedPreferences.getInstance();
        final intentionalBackground =
            prefs.getBool('intentional_background') ?? false;
        if (intentionalBackground) {
          await prefs.remove('intentional_background');
          debugPrint(
            '[TrackingTaskHandler] onDestroy: intentional background — '
            'skipping auto-end.',
          );
          unawaited(_syncManager.dispose());
          return;
        }
      } catch (e) {
        debugPrint('[TrackingTaskHandler] onDestroy: prefs read failed: $e');
        // Fall through to auto-end on prefs failure — safer than letting a
        // genuinely-killed session linger.
      }

      // Skip location buffer flush — too slow for Android's kill window.
      // Pending SQLite locations are acceptable to lose on task removal.

      // FIX 6: Don't auto-end on service destroy. OEM kills are often
      // temporary and the foreground service can be restarted by the system
      // or by the user reopening the app. Instead:
      //   1. Mark presence as `signal_lost` so dashboards know the device
      //      hasn't been heard from, but the session is NOT ended.
      //   2. Persist `needs_resume` in SharedPreferences so the app can
      //      seamlessly resume tracking on next open (within 2 hours).
      //   3. Let the server-side sweep auto-end after the stale window if
      //      the user never comes back.

      // Fire-and-forget: cancel onDisconnect handler so the offline write
      // doesn't fire after our explicit signal_lost write.
      unawaited(
        _database.ref('presence/$enterpriseId/$employeeId')
            .onDisconnect().cancel().catchError((e) {
          debugPrint('[TrackingTaskHandler] onDestroy onDisconnect cancel failed: $e');
        }),
      );

      // Fire-and-forget: set presence to signal_lost. Keep liveLocation,
      // activeStats, and sessionHeartbeat intact so the admin dashboard
      // continues to show the employee's last known state — useful context
      // while waiting to see if the service restarts.
      unawaited(
        _database.ref('presence/$enterpriseId/$employeeId').update({
          'status': 'signal_lost',
          'currentSessionId': sessionId,
          'lastSeen': ServerValue.timestamp,
        }).catchError((e) {
          debugPrint('[TrackingTaskHandler] onDestroy presence write failed: $e');
        }),
      );

      // Persist resume hint so [SessionProvider.loadActiveSession] can
      // restart tracking on next app open. The startedAt timestamp lets us
      // decide whether the gap was short enough to resume (< 2h) or long
      // enough that the session should be ended properly.
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('needs_resume', true);
        await prefs.setString('needs_resume_session_id', sessionId);
        await prefs.setInt(
          'needs_resume_started_at_ms',
          _startedAtMs ?? DateTime.now().millisecondsSinceEpoch,
        );
        // Record when the service was killed so the resume log can show
        // the gap duration on the admin activity timeline.
        await prefs.setInt(
          'needs_resume_killed_at_ms',
          DateTime.now().millisecondsSinceEpoch,
        );
      } catch (e) {
        debugPrint('[TrackingTaskHandler] onDestroy needs_resume write failed: $e');
      }
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

      if (!_isUsableFix(position)) {
        DiagnosticLogger.I.log('gps_fix_rejected', {
          'reason': 'accuracy_too_low',
          'accuracy': position.accuracy,
        });
        return;
      }
      DiagnosticLogger.I.log('gps_fix_received', {
        'lat': position.latitude,
        'lng': position.longitude,
        'accuracy': position.accuracy,
        'speed': position.speed,
      });

      // Distance quality filters (order: movement → timestamp → speed → accumulate)
      if (_lastPosition != null) {
        final meters = Geolocator.distanceBetween(
          _lastPosition!.latitude,
          _lastPosition!.longitude,
          position.latitude,
          position.longitude,
        );

        // 1. Minimum movement filter — discard GPS jitter
        if (meters < _minMovementMeters) {
          DiagnosticLogger.I.log('gps_fix_rejected', {
            'reason': 'movement_too_small',
            'meters': meters,
          });
          return;
        }

        // 2. Timestamp validity — reject fixes with duplicate/invalid timestamps
        final timeDiffSecs = position.timestamp
            .difference(_lastPosition!.timestamp)
            .inSeconds
            .abs();
        if (timeDiffSecs <= 0) {
          DiagnosticLogger.I.log('gps_fix_rejected', {
            'reason': 'duplicate_timestamp',
          });
          return;
        }

        // 3. Speed spike detection
        final speedMps = meters / timeDiffSecs;
        if (speedMps > _maxSpeedMps) {
          DiagnosticLogger.I.log('gps_fix_rejected', {
            'reason': 'speed_too_high',
            'speedMps': speedMps,
          });
          return;
        }

        // 4. STILL freeze — when the activity classifier reports STILL, GPS
        // jitter that slips past the 30 m filter is not real movement. Don't
        // accumulate distance, but keep buffering the point and updating
        // RTDB so the session stays live on the dashboard.
        if (_activityType == 'STILL') {
          DiagnosticLogger.I.log('distance_frozen', {
            'reason': 'activity_still',
            'cumulativeKm': _totalDistanceKm,
          });
        } else {
          _totalDistanceKm += meters / 1000;
          DiagnosticLogger.I.log('distance_added', {
            'segmentKm': meters / 1000,
            'cumulativeKm': _totalDistanceKm,
          });
        }
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

  // ── Heartbeat (every 15 min) ──

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
            'presence/$_enterpriseId/$_employeeId/currentSessionId': null,
            'presence/$_enterpriseId/$_employeeId/lastSeen':
                ServerValue.timestamp,
            'activeStats/$_enterpriseId/$_employeeId': null,
            'sessionHeartbeat/$_enterpriseId/$_employeeId': null,
            'liveLocations/$_enterpriseId/$_employeeId': null,
          });
          // Cancel onDisconnect so it doesn't double-fire after cleanup
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
