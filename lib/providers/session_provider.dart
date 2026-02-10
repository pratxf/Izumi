import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/session_model.dart';
import '../models/session_location_model.dart';
import '../models/activity_log_model.dart';
import '../repositories/session_repository.dart';
import '../repositories/activity_log_repository.dart';
import '../services/realtime_db_service.dart';
import '../services/location_service.dart';
import 'package:geolocator/geolocator.dart';

class SessionProvider extends ChangeNotifier {
  final SessionRepository _sessionRepo = SessionRepository();
  final ActivityLogRepository _activityLogRepo = ActivityLogRepository();
  final RealtimeDbService _rtdb = RealtimeDbService();
  final LocationService _locationService = LocationService();

  SessionModel? _activeSession;
  Duration _sessionDuration = Duration.zero;
  double _distance = 0.0;
  String _currentLocation = '';
  double _currentLat = 0.0;
  double _currentLng = 0.0;
  Timer? _durationTimer;
  Position? _lastPosition;
  bool _isLoading = false;
  String? _error;
  bool _locationInitializing = false;

  SessionModel? get activeSession => _activeSession;
  Duration get sessionDuration => _sessionDuration;
  double get distance => _distance;
  String get currentLocation => _currentLocation;
  double get currentLat => _currentLat;
  double get currentLng => _currentLng;
  bool get isSessionActive => _activeSession != null;
  bool get isLoading => _isLoading;
  String? get error => _error;

  String get formattedDuration {
    final hours = _sessionDuration.inHours;
    final minutes = _sessionDuration.inMinutes.remainder(60);
    final seconds = _sessionDuration.inSeconds.remainder(60);
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  // Load active session on app start
  Future<void> loadActiveSession(String employeeId) async {
    _isLoading = true;
    notifyListeners();

    try {
      _activeSession = await _sessionRepo.getActiveSession(employeeId);
      if (_activeSession != null) {
        // Resume session timer
        _sessionDuration =
            DateTime.now().difference(_activeSession!.startTime);
        _startDurationTimer();
        _startLocationTracking();
      }
    } catch (e) {
      debugPrint('[SessionProvider] loadActiveSession error: $e');
      _error = e.toString();
    }

    _isLoading = false;
    notifyListeners();

    // Fetch location in background — don't block session loading
    _fetchInitialLocation();
  }

  /// Fetch current location independently of session loading.
  /// Safe to call multiple times. Pass [force] to retry after errors.
  Future<void> initializeLocation({bool force = false}) async {
    if (!force && _currentLocation.isNotEmpty &&
        !_currentLocation.contains('Unable') &&
        !_currentLocation.contains('enable') &&
        !_currentLocation.contains('permission')) {
      return;
    }
    // Reset so _fetchInitialLocation can run again
    if (force) {
      _currentLocation = '';
      _locationInitializing = false;
    }
    await _fetchInitialLocation();
  }

  // Fetch current location once (for initial display)
  Future<void> _fetchInitialLocation() async {
    if (_locationInitializing) return;
    _locationInitializing = true;
    try {
      debugPrint('[SessionProvider] Fetching initial location...');

      // Check permissions FIRST (requests if needed)
      final permResult = await _locationService.checkPermissions();
      if (permResult != LocationPermissionResult.granted) {
        debugPrint('[SessionProvider] Location check failed: $permResult');
        _currentLocation = _permissionErrorMessage(permResult);
        notifyListeners();
        return;
      }

      // Show last known position instantly while GPS warms up
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null && _currentLocation.isEmpty) {
        _currentLat = lastKnown.latitude;
        _currentLng = lastKnown.longitude;
        _lastPosition = lastKnown;
        try {
          _currentLocation = await _locationService.getAddressFromCoordinates(
            lastKnown.latitude,
            lastKnown.longitude,
          );
        } catch (_) {
          _currentLocation = 'Lat: ${lastKnown.latitude.toStringAsFixed(4)}, Lng: ${lastKnown.longitude.toStringAsFixed(4)}';
        }
        notifyListeners();
      }

      // Now get accurate GPS position
      final position = await _locationService.getCurrentPosition();
      _currentLat = position.latitude;
      _currentLng = position.longitude;
      _lastPosition = position;
      debugPrint('[SessionProvider] Got initial position: ${position.latitude}, ${position.longitude}');

      _currentLocation = await _locationService.getAddressFromCoordinates(
        position.latitude,
        position.longitude,
      );
      notifyListeners();
    } catch (e) {
      debugPrint('[SessionProvider] _fetchInitialLocation error: $e');
      if (_currentLocation.isEmpty) {
        _currentLocation = 'Unable to get location';
      }
      notifyListeners();
    } finally {
      _locationInitializing = false;
    }
  }

  // Start a new work session
  Future<bool> startSession({
    required String employeeId,
    required String enterpriseId,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Check location permissions
      final permResult = await _locationService.checkPermissions();
      if (permResult != LocationPermissionResult.granted) {
        _error = _permissionErrorMessage(permResult);
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // Get current location
      final position = await _locationService.getCurrentPosition();
      final address = await _locationService.getAddressFromCoordinates(
        position.latitude,
        position.longitude,
      );

      _currentLat = position.latitude;
      _currentLng = position.longitude;
      _currentLocation = address;
      _lastPosition = position;

      final now = DateTime.now();

      // Create session in Firestore
      final session = SessionModel(
        id: '',
        enterpriseId: enterpriseId,
        employeeId: employeeId,
        startTime: now,
        status: 'active',
        createdAt: now,
      );

      final sessionId = await _sessionRepo.createSession(session);
      _activeSession = session.copyWith(id: sessionId);

      // Add check-in location
      await _sessionRepo.addSessionLocation(
        sessionId,
        SessionLocationModel(
          id: '',
          latitude: position.latitude,
          longitude: position.longitude,
          address: address,
          timestamp: now,
          type: 'check_in',
          title: 'Session Started',
        ),
      );

      // Update RTDB presence
      await _rtdb.setPresence(
        enterpriseId: enterpriseId,
        userId: employeeId,
        status: 'active',
        currentSessionId: sessionId,
      );
      await _rtdb.setupOnDisconnect(
        enterpriseId: enterpriseId,
        userId: employeeId,
      );

      // Update live location
      await _rtdb.updateLiveLocation(
        enterpriseId: enterpriseId,
        userId: employeeId,
        latitude: position.latitude,
        longitude: position.longitude,
        address: address,
        accuracy: position.accuracy,
      );

      // Log activity
      await _activityLogRepo.createLog(ActivityLogModel(
        id: '',
        enterpriseId: enterpriseId,
        employeeId: employeeId,
        sessionId: sessionId,
        type: 'session_started',
        title: 'Session Started',
        detail: 'Checked in at $address',
        timestamp: now,
        metadata: {
          'latitude': position.latitude,
          'longitude': position.longitude,
        },
      ));

      // Start timers
      _sessionDuration = Duration.zero;
      _distance = 0.0;
      _startDurationTimer();
      _startLocationTracking();

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // End the current work session
  Future<Map<String, dynamic>?> endSession({
    String? notes,
    required String enterpriseId,
    required String employeeId,
  }) async {
    if (_activeSession == null) return null;

    _isLoading = true;
    notifyListeners();

    try {
      // Stop timers
      _durationTimer?.cancel();
      _locationService.stopLocationUpdates();

      // Get final location
      Position? finalPosition;
      String finalAddress = _currentLocation;
      try {
        finalPosition = await _locationService.getCurrentPosition();
        finalAddress = await _locationService.getAddressFromCoordinates(
          finalPosition.latitude,
          finalPosition.longitude,
        );
      } catch (_) {}

      final now = DateTime.now();
      final totalDurationSecs = _sessionDuration.inSeconds;

      // Add check-out location
      if (finalPosition != null) {
        await _sessionRepo.addSessionLocation(
          _activeSession!.id,
          SessionLocationModel(
            id: '',
            latitude: finalPosition.latitude,
            longitude: finalPosition.longitude,
            address: finalAddress,
            timestamp: now,
            type: 'check_out',
            title: 'Session Ended',
          ),
        );
      }

      // End session in Firestore
      await _sessionRepo.endSession(
        sessionId: _activeSession!.id,
        totalDuration: totalDurationSecs,
        totalDistance: _distance,
        photosCount: _activeSession!.photosCount,
        tasksCompleted: _activeSession!.tasksCompleted,
        notes: notes,
      );

      // Update RTDB
      await _rtdb.setOffline(
        enterpriseId: enterpriseId,
        userId: employeeId,
      );
      await _rtdb.clearActiveStats(
        enterpriseId: enterpriseId,
        userId: employeeId,
      );

      // Log activity
      await _activityLogRepo.createLog(ActivityLogModel(
        id: '',
        enterpriseId: enterpriseId,
        employeeId: employeeId,
        sessionId: _activeSession!.id,
        type: 'session_ended',
        title: 'Session Ended',
        detail:
            'Checked out at $finalAddress. Duration: $formattedDuration',
        timestamp: now,
      ));

      final summary = {
        'sessionDuration': _sessionDuration,
        'distance': _distance,
        'photosCount': _activeSession!.photosCount,
        'tasksCompleted': _activeSession!.tasksCompleted,
        'locations': finalAddress,
      };

      // Reset state
      _activeSession = null;
      _sessionDuration = Duration.zero;
      _distance = 0.0;
      _currentLocation = '';
      _lastPosition = null;
      _isLoading = false;
      notifyListeners();

      return summary;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  void _startDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_activeSession != null) {
        _sessionDuration =
            DateTime.now().difference(_activeSession!.startTime);

        // Update RTDB active stats periodically (every 30 seconds)
        if (_sessionDuration.inSeconds % 30 == 0) {
          _updateActiveStats();
        }

        notifyListeners();
      }
    });
  }

  void _startLocationTracking() {
    debugPrint('[SessionProvider] Starting location tracking...');
    _locationService.startLocationUpdates(
      onLocationUpdate: (position) async {
        debugPrint('[SessionProvider] Location update: ${position.latitude}, ${position.longitude}');
        // Calculate distance from last position
        if (_lastPosition != null) {
          final dist = _locationService.calculateDistance(
            _lastPosition!.latitude,
            _lastPosition!.longitude,
            position.latitude,
            position.longitude,
          );
          _distance += dist;
        }

        _currentLat = position.latitude;
        _currentLng = position.longitude;
        _lastPosition = position;

        // Update address
        try {
          _currentLocation = await _locationService.getAddressFromCoordinates(
            position.latitude,
            position.longitude,
          );
        } catch (_) {}

        // Update RTDB live location
        if (_activeSession != null) {
          try {
            await _rtdb.updateLiveLocation(
              enterpriseId: _activeSession!.enterpriseId,
              userId: _activeSession!.employeeId,
              latitude: position.latitude,
              longitude: position.longitude,
              address: _currentLocation,
              accuracy: position.accuracy,
            );
          } catch (e) {
            debugPrint('[SessionProvider] RTDB live location update failed: $e');
          }
        }

        notifyListeners();
      },
      onError: (error) {
        debugPrint('[SessionProvider] Location stream error: $error');
        _error = 'Location tracking interrupted';
        notifyListeners();
      },
      onStreamDone: () {
        // Stream was killed (e.g. activity recreation) - restart if session active
        if (_activeSession != null) {
          debugPrint('[SessionProvider] Location stream died, restarting...');
          Future.delayed(const Duration(seconds: 2), () {
            if (_activeSession != null) {
              _startLocationTracking();
            }
          });
        }
      },
    );
  }

  Future<void> _updateActiveStats() async {
    if (_activeSession == null) return;
    try {
      await _rtdb.updateActiveStats(
        enterpriseId: _activeSession!.enterpriseId,
        userId: _activeSession!.employeeId,
        sessionDuration: _sessionDuration.inSeconds,
        distance: _distance,
        photosToday: _activeSession!.photosCount,
        tasksToday: _activeSession!.tasksCompleted,
      );
    } catch (_) {}
  }

  // Increment photo count for active session
  void incrementPhotoCount() {
    if (_activeSession != null) {
      _activeSession = _activeSession!.copyWith(
        photosCount: _activeSession!.photosCount + 1,
      );
      notifyListeners();
    }
  }

  // Increment task count for active session
  void incrementTaskCount() {
    if (_activeSession != null) {
      _activeSession = _activeSession!.copyWith(
        tasksCompleted: _activeSession!.tasksCompleted + 1,
      );
      notifyListeners();
    }
  }

  // Add a visit location point
  Future<void> addVisitLocation(String title) async {
    if (_activeSession == null) return;

    try {
      final position = await _locationService.getCurrentPosition();
      final address = await _locationService.getAddressFromCoordinates(
        position.latitude,
        position.longitude,
      );

      await _sessionRepo.addSessionLocation(
        _activeSession!.id,
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
    } catch (_) {}
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

  @override
  void dispose() {
    _durationTimer?.cancel();
    _locationService.dispose();
    super.dispose();
  }
}
