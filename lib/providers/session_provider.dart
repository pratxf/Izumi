import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import '../models/session_location_model.dart';
import '../models/session_model.dart';
import '../repositories/daily_summary_repository.dart';
import '../repositories/session_repository.dart';
import '../services/location_service.dart';
import '../services/realtime_db_service.dart';
import '../tracking/pending_location_store.dart';
import '../tracking/session_task_guard.dart';
import '../tracking/tracking_foreground_service.dart';

class SessionProvider extends ChangeNotifier {
  final SessionRepository _sessionRepo = SessionRepository();
  final DailySummaryRepository _dailySummaryRepo = DailySummaryRepository();
  final RealtimeDbService _rtdb = RealtimeDbService();
  final LocationService _locationService = LocationService();

  StreamSubscription<SessionModel?>? _activeSessionSubscription;
  bool _disposed = false;

  SessionModel? _activeSession;
  double _distance = 0.0;
  String _currentLocation = '';
  double _currentLat = 0.0;
  double _currentLng = 0.0;
  DateTime? _lastLocationUpdate;
  bool _isLoading = false;
  String? _error;
  bool _locationInitializing = false;
  DateTime? _lastSessionStartAttempt;

  SessionProvider() {
    TrackingForegroundService.addTaskDataCallback(_onTaskData);
  }

  SessionModel? get activeSession => _activeSession;
  double get distance => _distance;
  String get currentLocation => _currentLocation;
  double get currentLat => _currentLat;
  double get currentLng => _currentLng;
  bool get isSessionActive => _activeSession != null;
  bool get isLoading => _isLoading;
  String? get error => _error;
  DateTime? get lastLocationUpdate => _lastLocationUpdate;
  bool get isLocationLost => false;
  String? get locationLostReason => null;
  int? get gracePeriodRemaining => null;

  Duration get sessionDuration {
    final session = _activeSession;
    if (session == null) {
      return Duration.zero;
    }

    if (!session.isActive && session.endTime != null) {
      return session.endTime!.difference(session.startTime);
    }

    return DateTime.now().difference(session.startTime);
  }

  String get lastLocationUpdateText {
    final updatedAt = _lastLocationUpdate;
    if (updatedAt == null) {
      return 'Updated: Waiting for fix';
    }

    final diff = DateTime.now().difference(updatedAt);
    if (diff.inSeconds < 60) {
      return 'Updated: Just now';
    }
    if (diff.inMinutes < 60) {
      return 'Updated: ${diff.inMinutes}m ago';
    }
    return 'Updated: ${diff.inHours}h ago';
  }

  String get formattedDuration {
    final duration = sessionDuration;
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> loadActiveSession(String employeeId) async {
    _isLoading = true;
    notifyListeners();

    await _activeSessionSubscription?.cancel();
    _activeSessionSubscription =
        _sessionRepo.streamActiveSession(employeeId).listen((session) async {
      if (_disposed) return;
      _activeSession = session;

      if (session == null) {
        _distance = 0.0;
        // Session ended or doesn't exist — ensure the foreground service is
        // stopped so heartbeats/presence don't resurrect a ghost session.
        try {
          if (await FlutterForegroundTask.isRunningService) {
            await TrackingForegroundService.stopTracking(clearContext: true);
          }
        } catch (e) {
          debugPrint('[SessionProvider] stop orphan tracking failed: $e');
        }
      } else {
        _distance = session.totalDistance;
        try {
          await TrackingForegroundService.ensureTrackingRunning(
            enterpriseId: session.enterpriseId,
            employeeId: session.employeeId,
            sessionId: session.id,
            startTimeMs: session.startTime.millisecondsSinceEpoch,
          );
        } catch (error, stackTrace) {
          debugPrint(
            '[SessionProvider] unable to ensure tracking is running: $error\n$stackTrace',
          );
          _error = error.toString();
        }
      }

      _isLoading = false;
      _safeNotifyListeners();
    }, onError: (Object error, StackTrace stackTrace) {
      debugPrint(
        '[SessionProvider] active session stream failed: $error\n$stackTrace',
      );
      _error = error.toString();
      _isLoading = false;
      _safeNotifyListeners();
    });

    await initializeLocation();
  }

  Future<void> initializeLocation({bool force = false}) async {
    if (!force &&
        _currentLocation.isNotEmpty &&
        !_currentLocation.contains('Unable') &&
        !_currentLocation.contains('enable') &&
        !_currentLocation.contains('permission')) {
      return;
    }

    if (_locationInitializing) {
      return;
    }

    _locationInitializing = true;
    try {
      final permission = await _locationService.checkPermissions();
      if (permission != LocationPermissionResult.granted) {
        _currentLocation = _permissionErrorMessage(permission);
        _safeNotifyListeners();
        return;
      }

      final position = await _locationService.getCurrentPosition();
      _currentLat = position.latitude;
      _currentLng = position.longitude;
      _currentLocation = await _locationService.getAddressFromCoordinates(
        position.latitude,
        position.longitude,
      );
      _lastLocationUpdate = DateTime.now();
      _safeNotifyListeners();
    } catch (error, stackTrace) {
      debugPrint(
        '[SessionProvider] initializeLocation failed: $error\n$stackTrace',
      );
      if (_currentLocation.isEmpty) {
        _currentLocation = 'Unable to get location';
      }
      _safeNotifyListeners();
    } finally {
      _locationInitializing = false;
    }
  }

  String _formatDuration(int totalSeconds) {
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }

  String _todayDateIST() {
    final now = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<bool> startSession({
    required String employeeId,
    required String enterpriseId,
    required String employeeName,
  }) async {
    // Debounce: prevent rapid session start after recent auto-end
    final now = DateTime.now();
    if (_lastSessionStartAttempt != null &&
        now.difference(_lastSessionStartAttempt!).inSeconds < 60) {
      _error = 'Please wait before starting a new session. A recent session was just ended.';
      notifyListeners();
      return false;
    }
    _lastSessionStartAttempt = now;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final permission = await _locationService.checkPermissions();
      if (permission != LocationPermissionResult.granted) {
        _error = _permissionErrorMessage(permission);
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // Check background location — warn but don't hard-block
      final alwaysStatus = await ph.Permission.locationAlways.status;
      if (!alwaysStatus.isGranted) {
        debugPrint(
            '[SessionProvider] Background location not granted, '
            'requesting upgrade...');
        final result = await ph.Permission.locationAlways.request();
        if (!result.isGranted) {
          debugPrint(
              '[SessionProvider] WARNING: background location denied, '
              'GPS may stop when screen locks');
        }
      }

      Position? initialPosition;
      String initialAddress = _currentLocation;

      try {
        initialPosition = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 10),
          ),
        );
        _currentLat = initialPosition.latitude;
        _currentLng = initialPosition.longitude;
        initialAddress = await _locationService.getAddressFromCoordinates(
          initialPosition.latitude,
          initialPosition.longitude,
        );
      } catch (_) {
        final fallback = await Geolocator.getLastKnownPosition();
        if (fallback != null) {
          initialPosition = fallback;
          _currentLat = fallback.latitude;
          _currentLng = fallback.longitude;
          initialAddress = await _locationService.getAddressFromCoordinates(
            fallback.latitude,
            fallback.longitude,
          );
        }
      }

      _currentLocation = initialAddress;
      _lastLocationUpdate = DateTime.now();

      // ── 1-2. Reset RTDB and clear stale data in parallel ────────────
      final sessionStartTime = DateTime.now();
      await Future.wait([
        _rtdb.initializeActiveStats(
          enterpriseId: enterpriseId,
          userId: employeeId,
        ),
        _rtdb.clearLiveLocation(
          enterpriseId: enterpriseId,
          userId: employeeId,
        ),
        _rtdb.clearSessionHeartbeat(
          enterpriseId: enterpriseId,
          userId: employeeId,
        ),
      ]);

      // ── 3. Create Firestore session doc ──────────────────────────────
      final session = SessionModel(
        id: '',
        enterpriseId: enterpriseId,
        employeeId: employeeId,
        startTime: sessionStartTime,
        status: 'active',
        createdAt: sessionStartTime,
      );

      final sessionId = await _sessionRepo.createSession(session);
      _activeSession = session.copyWith(id: sessionId);
      _distance = 0.0;
      _safeNotifyListeners();

      // ── 3b. Clear stale SQLite pending locations from previous session
      unawaited(
        PendingLocationStore.instance.clearStaleLocations(sessionId).catchError((e) {
          debugPrint('[SessionProvider] clearStaleLocations failed: $e');
        }),
      );

      // ── 4. Write session_started activityLog (fire-and-forget) ─────────
      // The Cloud Function onSessionStarted also writes this log as a
      // fallback, so we don't need to block the UI waiting for it.
      unawaited(
        _writeSessionStartLog(
          sessionId: sessionId,
          employeeId: employeeId,
          enterpriseId: enterpriseId,
          employeeName: employeeName,
          address: initialAddress,
          position: initialPosition,
        ).catchError((e) {
          debugPrint('[SessionProvider] session_started log failed: $e');
        }),
      );

      // ── 5-8. Set RTDB presence, onDisconnect, start tracking ─────────
      await Future.wait([
        _rtdb.setPresence(
          enterpriseId: enterpriseId,
          userId: employeeId,
          status: 'active',
          currentSessionId: sessionId,
        ),
        _rtdb.setupSignalLostOnDisconnect(
          enterpriseId: enterpriseId,
          userId: employeeId,
          currentSessionId: sessionId,
        ),
        if (initialPosition != null)
          _rtdb.updateLiveLocation(
            enterpriseId: enterpriseId,
            userId: employeeId,
            latitude: initialPosition.latitude,
            longitude: initialPosition.longitude,
            address: initialAddress,
            accuracy: initialPosition.accuracy,
          ),
        TrackingForegroundService.startTracking(
          enterpriseId: enterpriseId,
          employeeId: employeeId,
          sessionId: sessionId,
          employeeName: employeeName,
          startTimeMs: sessionStartTime.millisecondsSinceEpoch,
        ),
      ]);

      // ── 9. Write check-in location to session/locations subcollection
      if (initialPosition != null) {
        unawaited(
          _sessionRepo.addSessionLocation(
            sessionId,
            SessionLocationModel(
              id: '',
              latitude: initialPosition.latitude,
              longitude: initialPosition.longitude,
              address: initialAddress,
              timestamp: sessionStartTime,
              type: 'check_in',
              title: 'Session Started',
            ),
          ),
        );
      }

      // ── 10. Start native SessionTaskGuard ────────────────────────────
      unawaited(
        SessionTaskGuard.start(
          enterpriseId: enterpriseId,
          employeeId: employeeId,
          sessionId: sessionId,
        ),
      );

      _isLoading = false;
      _safeNotifyListeners();

      return true;
    } catch (error, stackTrace) {
      debugPrint('[SessionProvider] startSession failed: $error\n$stackTrace');
      _error = error.toString();
      _isLoading = false;
      _safeNotifyListeners();
      return false;
    }
  }

  /// Writes the session_started activityLog with one retry on failure.
  Future<void> _writeSessionStartLog({
    required String sessionId,
    required String employeeId,
    required String enterpriseId,
    required String employeeName,
    required String address,
    Position? position,
  }) async {
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        await FirebaseFirestore.instance.collection('activityLogs').add({
          'type': 'session_started',
          'employeeId': employeeId,
          'sessionId': sessionId,
          'enterpriseId': enterpriseId,
          'orgId': enterpriseId,
          'timestamp': FieldValue.serverTimestamp(),
          'date': _todayDateIST(),
          'title': 'Session Started',
          'detail': '$employeeName started a field session',
          'payload': {
            if (position != null) 'lat': position.latitude,
            if (position != null) 'lng': position.longitude,
            'address': address,
            'startTime': FieldValue.serverTimestamp(),
          },
        });
        return;
      } catch (e) {
        debugPrint('[SessionProvider] session_started log attempt ${attempt + 1} failed: $e');
        if (attempt == 1) rethrow;
        await Future.delayed(const Duration(seconds: 2));
      }
    }
  }

  Future<Map<String, dynamic>?> endSession({
    required String enterpriseId,
    required String employeeId,
  }) async {
    final session = _activeSession;
    if (session == null) {
      return null;
    }

    _isLoading = true;
    notifyListeners();

    try {
      // Attempt a quick flush — 5s cap so the button doesn't spin forever.
      // Any un-flushed points will be written by the Cloud Function or
      // picked up on next app open. Data already tracked locally is used
      // as fallback for the summary.
      Map<String, dynamic> flushResult = const {};
      try {
        flushResult = await TrackingForegroundService.finalFlush()
            .timeout(const Duration(seconds: 5));
      } on TimeoutException {
        debugPrint('[SessionProvider] finalFlush timed out after 5s, proceeding');
      } catch (e) {
        debugPrint('[SessionProvider] finalFlush failed: $e');
      }

      final flushedDistance = flushResult['distanceKm'];
      if (flushedDistance is num) {
        _distance = flushedDistance.toDouble();
      }

      final latitude = flushResult['latitude'];
      final longitude = flushResult['longitude'];
      if (latitude is num && longitude is num) {
        _currentLat = latitude.toDouble();
        _currentLng = longitude.toDouble();
      }

      final durationSeconds = flushResult['sessionDurationSeconds'];
      final totalDuration = durationSeconds is num
          ? Duration(seconds: durationSeconds.toInt())
          : DateTime.now().difference(session.startTime);
      final totalDurationSecs = totalDuration.inSeconds;

      // Stop tracking + RTDB cleanup in parallel for speed.
      // clearOnDisconnect runs first, then setOffline — but both are
      // independent of stopTracking, so we overlap them.
      unawaited(SessionTaskGuard.stop());
      await Future.wait([
        TrackingForegroundService.stopTracking(clearContext: true),
        _rtdb.clearOnDisconnect(
          enterpriseId: enterpriseId,
          userId: employeeId,
        ).then((_) => _rtdb.setOffline(
              enterpriseId: enterpriseId,
              userId: employeeId,
            )),
      ]);

      final now = DateTime.now();
      final finalAddress = _currentLocation.isNotEmpty
          ? _currentLocation
          : 'Lat: ${_currentLat.toStringAsFixed(4)}, Lng: ${_currentLng.toStringAsFixed(4)}';

      await Future.wait([
        _sessionRepo.endSession(
          sessionId: session.id,
          totalDuration: totalDurationSecs,
          totalDistance: _distance,
          photosCount: session.photosCount,
          tasksCompleted: session.tasksCompleted,
        ),
        _rtdb.clearActiveStats(
          enterpriseId: enterpriseId,
          userId: employeeId,
        ),
        _rtdb.clearSessionHeartbeat(
          enterpriseId: enterpriseId,
          userId: employeeId,
        ),
        _rtdb.clearLiveLocation(
          enterpriseId: enterpriseId,
          userId: employeeId,
        ),
        if (_currentLat != 0 || _currentLng != 0)
          _sessionRepo.addSessionLocation(
            session.id,
            SessionLocationModel(
              id: '',
              latitude: _currentLat,
              longitude: _currentLng,
              address: finalAddress,
              timestamp: now,
              type: 'check_out',
              title: 'Session Ended',
            ),
          ),
      ]);

      // ── Write session_ended activity log ───────────────────────────────
      unawaited(
        FirebaseFirestore.instance.collection('activityLogs').add({
          'type': 'session_ended',
          'employeeId': employeeId,
          'sessionId': session.id,
          'enterpriseId': enterpriseId,
          'orgId': enterpriseId,
          'timestamp': FieldValue.serverTimestamp(),
          'date': _todayDateIST(),
          'title': 'Session Ended',
          'detail': _formatDuration(totalDurationSecs),
          'payload': {
            'endTime': FieldValue.serverTimestamp(),
            'durationSeconds': totalDurationSecs,
            'distanceKm': _distance,
            'photosCount': session.photosCount,
            'tasksCompleted': session.tasksCompleted,
            if (_currentLat != 0 || _currentLng != 0) 'lat': _currentLat,
            if (_currentLat != 0 || _currentLng != 0) 'lng': _currentLng,
            'address': finalAddress,
          },
          'metadata': {
            if (_currentLat != 0 || _currentLng != 0) 'latitude': _currentLat,
            if (_currentLat != 0 || _currentLng != 0) 'longitude': _currentLng,
            'address': finalAddress,
          },
        }).then((_) {}).catchError((e) {
          debugPrint('[SessionProvider] session_ended activity log failed: $e');
        }),
      );

      // ── Upsert daily summary so analytics reflect this session ────────
      unawaited(
        _dailySummaryRepo.upsertFromSession(
          employeeId: employeeId,
          enterpriseId: enterpriseId,
          sessionId: session.id,
          totalDuration: totalDurationSecs,
          totalDistance: _distance,
          photosCount: session.photosCount,
          tasksCompleted: session.tasksCompleted,
        ).catchError((e) {
          debugPrint('[SessionProvider] dailySummary upsert failed: $e');
        }),
      );

      final summary = <String, dynamic>{
        'sessionDuration': totalDuration,
        'distance': _distance,
        'photosCount': session.photosCount,
        'tasksCompleted': session.tasksCompleted,
        'locations': finalAddress,
      };

      _activeSession = null;
      _distance = 0.0;
      _isLoading = false;
      _safeNotifyListeners();

      return summary;
    } catch (error, stackTrace) {
      debugPrint('[SessionProvider] endSession failed: $error\n$stackTrace');
      _error = error.toString();
      _isLoading = false;
      _safeNotifyListeners();
      return null;
    }
  }

  void incrementPhotoCount() {
    final session = _activeSession;
    if (session == null) {
      return;
    }

    _activeSession = session.copyWith(
      photosCount: session.photosCount + 1,
    );
    _safeNotifyListeners();

    unawaited(
      _sessionRepo.updateSession(_activeSession!.id, {
        'photosCount': _activeSession!.photosCount,
      }),
    );
  }

  void incrementTaskCount() {
    final session = _activeSession;
    if (session == null) {
      return;
    }

    _activeSession = session.copyWith(
      tasksCompleted: session.tasksCompleted + 1,
    );
    _safeNotifyListeners();

    unawaited(
      _sessionRepo.updateSession(_activeSession!.id, {
        'tasksCompleted': _activeSession!.tasksCompleted,
      }),
    );
  }

  Future<void> addVisitLocation(String title) async {
    final session = _activeSession;
    if (session == null) {
      return;
    }

    try {
      final position = await _locationService.getCurrentPosition();
      final address = await _locationService.getAddressFromCoordinates(
        position.latitude,
        position.longitude,
      );

      await _sessionRepo.addSessionLocation(
        session.id,
        SessionLocationModel(
          id: '',
          latitude: position.latitude,
          longitude: position.longitude,
          address: address,
          timestamp: DateTime.now(),
          type: 'visit',
          title: title,
        ),
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[SessionProvider] addVisitLocation failed: $error\n$stackTrace',
      );
    }
  }

  void _onTaskData(Object data) {
    if (data is! Map) {
      return;
    }

    final type = data['type'];
    if (type != 'tracking_state' && type != 'sync_status') {
      return;
    }

    final activeSession = _activeSession;
    if (activeSession != null && data['sessionId'] != activeSession.id) {
      return;
    }

    final distanceKm = data['distanceKm'];
    if (distanceKm is num) {
      _distance = distanceKm.toDouble();
    }

    final latitude = data['latitude'];
    final longitude = data['longitude'];
    if (latitude is num && longitude is num) {
      _currentLat = latitude.toDouble();
      _currentLng = longitude.toDouble();
      _currentLocation =
          'Lat: ${_currentLat.toStringAsFixed(4)}, Lng: ${_currentLng.toStringAsFixed(4)}';
    }

    final lastUpdate = data['lastLocationUpdateMs'];
    if (lastUpdate is num) {
      _lastLocationUpdate =
          DateTime.fromMillisecondsSinceEpoch(lastUpdate.toInt());
    }

    final error = data['error'];
    _error = (error is String && error.isNotEmpty) ? error : null;
    _safeNotifyListeners();
  }

  String _permissionErrorMessage(LocationPermissionResult result) {
    switch (result) {
      case LocationPermissionResult.serviceDisabled:
        return 'Please enable Location Services in device settings';
      case LocationPermissionResult.denied:
        return 'Location permission required';
      case LocationPermissionResult.deniedForever:
        return 'Location permission permanently denied. Please enable in app settings';
      case LocationPermissionResult.granted:
        return '';
    }
  }

  void _safeNotifyListeners() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    TrackingForegroundService.removeTaskDataCallback(_onTaskData);
    _activeSessionSubscription?.cancel();
    _locationService.dispose();
    super.dispose();
  }
}
