import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';

/// A simple in-memory cache for reverse geocoding results.
/// Prevents repeated network calls for the same coordinates.
class GeocodingCache {
  GeocodingCache._();
  static final GeocodingCache instance = GeocodingCache._();

  final Map<String, String> _cache = {};
  final Set<String> _inflight = {};

  /// Round coordinates to ~11m precision for cache key.
  static String _key(double lat, double lng) =>
      '${lat.toStringAsFixed(4)},${lng.toStringAsFixed(4)}';

  /// Returns a cached place name if available, otherwise starts an async
  /// lookup and returns `null`. Call [addListener] or poll to detect when
  /// a result becomes available.
  String? getCached(double lat, double lng) {
    return _cache[_key(lat, lng)];
  }

  /// Reverse geocode and return a human-readable address.
  /// Returns the resolved name, or a compact coordinate string on failure.
  /// Results are cached so subsequent calls for the same location are instant.
  Future<String> resolve(double lat, double lng) async {
    final key = _key(lat, lng);
    final cached = _cache[key];
    if (cached != null) return cached;

    // Prevent duplicate in-flight requests
    if (_inflight.contains(key)) {
      // Wait briefly for the other request to finish
      for (var i = 0; i < 10; i++) {
        await Future.delayed(const Duration(milliseconds: 200));
        final result = _cache[key];
        if (result != null) return result;
      }
      return '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
    }

    _inflight.add(key);
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
        if (parts.isNotEmpty) {
          final result = parts.join(', ');
          _cache[key] = result;
          return result;
        }
      }
    } catch (e) {
      debugPrint('[GeocodingCache] resolve failed: $e');
    } finally {
      _inflight.remove(key);
    }

    final fallback = '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
    _cache[key] = fallback;
    return fallback;
  }

  /// Check whether a string looks like raw coordinates rather than a place name.
  static bool isCoordinateString(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return false;
    if (trimmed.startsWith('Lat:')) return true;
    // Matches patterns like "26.5590, 72.8818" or "26.5590,72.8818"
    if (RegExp(r'^\d+\.\d+,\s*\d+\.\d+$').hasMatch(trimmed)) return true;
    // Matches "Lat: 26.5590, Lng: 72.8818"
    if (RegExp(r'^Lat:\s*[\d.]+,\s*Lng:\s*[\d.]+$').hasMatch(trimmed)) return true;
    return false;
  }

  /// Extract lat/lng from a coordinate string.
  /// Returns null if parsing fails.
  static (double, double)? parseCoordinates(String value) {
    final trimmed = value.trim();

    // "Lat: 26.5590, Lng: 72.8818"
    final latLngMatch = RegExp(r'Lat:\s*([\d.]+),\s*Lng:\s*([\d.]+)').firstMatch(trimmed);
    if (latLngMatch != null) {
      final lat = double.tryParse(latLngMatch.group(1)!);
      final lng = double.tryParse(latLngMatch.group(2)!);
      if (lat != null && lng != null) return (lat, lng);
    }

    // "26.5590, 72.8818"
    final simpleMatch = RegExp(r'^([\d.]+),\s*([\d.]+)$').firstMatch(trimmed);
    if (simpleMatch != null) {
      final lat = double.tryParse(simpleMatch.group(1)!);
      final lng = double.tryParse(simpleMatch.group(2)!);
      if (lat != null && lng != null) return (lat, lng);
    }

    return null;
  }
}
