import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

enum LocationPermissionResult {
  granted,
  serviceDisabled,
  denied,
  deniedForever,
}

class LocationService {
  StreamSubscription<Position>? _positionSubscription;

  // Check and request location permissions (with distinct error types)
  Future<LocationPermissionResult> checkPermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('[LocationService] Location services are disabled');
      return LocationPermissionResult.serviceDisabled;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        debugPrint('[LocationService] Permission denied');
        return LocationPermissionResult.denied;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      debugPrint('[LocationService] Permission denied forever');
      return LocationPermissionResult.deniedForever;
    }

    debugPrint('[LocationService] Permission granted: $permission');
    return LocationPermissionResult.granted;
  }

  // Get current position with timeout
  Future<Position> getCurrentPosition() async {
    debugPrint('[LocationService] Getting current position...');
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 15));
      debugPrint('[LocationService] Got position: ${position.latitude}, ${position.longitude}');
      return position;
    } on TimeoutException {
      debugPrint('[LocationService] getCurrentPosition timed out, trying getLastKnownPosition...');
      final lastPosition = await Geolocator.getLastKnownPosition();
      if (lastPosition != null) {
        debugPrint('[LocationService] Using last known: ${lastPosition.latitude}, ${lastPosition.longitude}');
        return lastPosition;
      }
      rethrow;
    } catch (e) {
      debugPrint('[LocationService] getCurrentPosition error: $e');
      // Fallback to last known position on any error
      final lastPosition = await Geolocator.getLastKnownPosition();
      if (lastPosition != null) {
        debugPrint('[LocationService] Using last known after error: ${lastPosition.latitude}, ${lastPosition.longitude}');
        return lastPosition;
      }
      rethrow;
    }
  }

  // Get address from coordinates
  Future<String> getAddressFromCoordinates(
    double latitude,
    double longitude,
  ) async {
    try {
      final placemarks = await placemarkFromCoordinates(latitude, longitude);
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        final parts = <String>[];
        if (place.subLocality?.isNotEmpty == true) parts.add(place.subLocality!);
        if (place.locality?.isNotEmpty == true) parts.add(place.locality!);
        if (parts.isEmpty && place.name?.isNotEmpty == true) {
          parts.add(place.name!);
        }
        return parts.join(', ');
      }
    } catch (e) {
      debugPrint('[LocationService] Geocoding error: $e');
    }
    return 'Lat: ${latitude.toStringAsFixed(4)}, Lng: ${longitude.toStringAsFixed(4)}';
  }

  // Start continuous location updates
  void startLocationUpdates({
    required void Function(Position position) onLocationUpdate,
    void Function(dynamic error)? onError,
    void Function()? onStreamDone,
    int distanceFilter = 25,
  }) {
    _positionSubscription?.cancel();
    debugPrint('[LocationService] Starting position stream (distanceFilter: $distanceFilter)');
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: _getPlatformSettings(distanceFilter: distanceFilter),
    ).listen(
      onLocationUpdate,
      onError: (e) {
        debugPrint('[LocationService] Stream error: $e');
        onError?.call(e);
      },
      onDone: () {
        debugPrint('[LocationService] Position stream ended');
        onStreamDone?.call();
      },
    );
  }

  // Platform-specific location settings
  LocationSettings _getPlatformSettings({required int distanceFilter}) {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilter,
        forceLocationManager: false,
        intervalDuration: const Duration(seconds: 60),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Izumi',
          notificationText: 'Tracking your location',
          enableWakeLock: true,
        ),
      );
    }
    return AppleSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: distanceFilter,
      activityType: ActivityType.fitness,
      pauseLocationUpdatesAutomatically: false,
      showBackgroundLocationIndicator: true,
    );
  }

  // Check permission status without requesting (safe for mid-session checks)
  Future<LocationPermissionResult> checkPermissionOnly() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return LocationPermissionResult.serviceDisabled;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      return LocationPermissionResult.denied;
    }
    if (permission == LocationPermission.deniedForever) {
      return LocationPermissionResult.deniedForever;
    }
    return LocationPermissionResult.granted;
  }

  // Stream that emits whenever location services are enabled/disabled
  Stream<ServiceStatus> get serviceStatusStream =>
      Geolocator.getServiceStatusStream();

  // Attempt to restart location stream after verifying permission+service
  Future<bool> tryRestartStream({
    required void Function(Position position) onLocationUpdate,
    void Function(dynamic error)? onError,
    void Function()? onStreamDone,
    int distanceFilter = 25,
  }) async {
    final result = await checkPermissionOnly();
    if (result != LocationPermissionResult.granted) {
      debugPrint('[LocationService] Cannot restart stream: $result');
      return false;
    }
    startLocationUpdates(
      onLocationUpdate: onLocationUpdate,
      onError: onError,
      onStreamDone: onStreamDone,
      distanceFilter: distanceFilter,
    );
    return true;
  }

  // Stop location updates
  void stopLocationUpdates() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  // Calculate distance between two points (in km)
  double calculateDistance(
    double startLat,
    double startLng,
    double endLat,
    double endLng,
  ) {
    return Geolocator.distanceBetween(
          startLat,
          startLng,
          endLat,
          endLng,
        ) /
        1000; // Convert meters to km
  }

  void dispose() {
    _positionSubscription?.cancel();
  }
}
