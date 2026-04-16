import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../offline_queue/app_database.dart';

/// Singleton logger that writes structured diagnostic events to a local
/// SQLite table. Designed to never block or crash the tracking pipeline:
/// every call is async fire-and-forget, every failure is swallowed, and
/// when [isEnabled] is false the logger is a zero-cost no-op.
class DiagnosticLogger {
  DiagnosticLogger._();
  static final DiagnosticLogger I = DiagnosticLogger._();

  static const String _enabledFlagKey = 'diagnostic_logger.enabled';
  static const String _pendingUploadKey = 'diagnostic_logger.pending_upload';
  static const Duration _retention = Duration(days: 7);
  static const int _maxEventsPerReport = 500;

  bool _enabled = false;
  bool _initialized = false;
  String? _currentSessionId;
  String? _enterpriseId;
  String? _userId;
  String _appVersion = 'unknown';

  bool get isEnabled => _enabled;
  @Deprecated('Use isEnabled')
  bool get enabled => _enabled;

  /// Store per-user context so upload methods can build full report docs
  /// without every caller reassembling enterpriseId / userId / appVersion.
  /// Safe to call repeatedly (e.g. on every auth refresh).
  void configure({
    required String enterpriseId,
    required String userId,
    required String appVersion,
  }) {
    _enterpriseId = enterpriseId;
    _userId = userId;
    _appVersion = appVersion;
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_enabledFlagKey) ?? false;
      if (_enabled) {
        await _purgeOld();
      }
      await _drainPendingUpload(prefs);
    } catch (_) {/* never throw */}
  }

  /// Re-read the enabled flag and any queued upload request from
  /// SharedPreferences. Call on app resume so that background FCM commands
  /// (which can only touch prefs, not this singleton) take effect without
  /// a full restart.
  Future<void> reloadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_enabledFlagKey) ?? _enabled;
      await _drainPendingUpload(prefs);
    } catch (_) {}
  }

  Future<void> _drainPendingUpload(SharedPreferences prefs) async {
    if (!prefs.containsKey(_pendingUploadKey)) return;
    await prefs.remove(_pendingUploadKey);
    if (!_enabled) return;
    if (_enterpriseId == null || _userId == null) return;
    unawaited(uploadRecent());
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledFlagKey, value);
    } catch (_) {}
  }

  void setSessionId(String? id) {
    _currentSessionId = id;
  }

  /// Log an event. No-op when disabled. Never throws.
  void log(
    String eventType, [
    Map<String, dynamic>? payload,
    String severity = 'info',
  ]) {
    if (!_enabled) return;
    unawaited(_writeAsync(eventType, payload, severity));
  }

  Future<void> _writeAsync(
    String eventType,
    Map<String, dynamic>? payload,
    String severity,
  ) async {
    try {
      final db = await AppDatabase.instance.database;
      await db.insert('diagnostic_logs', {
        'session_id': _currentSessionId,
        'event_type': eventType,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'payload': payload == null ? null : jsonEncode(payload),
        'severity': severity,
      });
    } catch (_) {/* swallow */}
  }

  Future<void> _purgeOld() async {
    try {
      final db = await AppDatabase.instance.database;
      final cutoff =
          DateTime.now().subtract(_retention).millisecondsSinceEpoch;
      await db.delete(
        'diagnostic_logs',
        where: 'timestamp < ?',
        whereArgs: [cutoff],
      );
    } catch (_) {}
  }

  /// Read events for a session, oldest first. Returns at most
  /// [_maxEventsPerReport] entries (most-recent kept on overflow).
  Future<List<Map<String, dynamic>>> readSession(String sessionId) async {
    try {
      final db = await AppDatabase.instance.database;
      final rows = await db.query(
        'diagnostic_logs',
        where: 'session_id = ?',
        whereArgs: [sessionId],
        orderBy: 'timestamp ASC',
      );
      if (rows.length <= _maxEventsPerReport) return rows;
      return rows.sublist(rows.length - _maxEventsPerReport);
    } catch (_) {
      return const [];
    }
  }

  Future<List<Map<String, dynamic>>> readRecent(Duration duration) async {
    try {
      final db = await AppDatabase.instance.database;
      final cutoff = DateTime.now().subtract(duration).millisecondsSinceEpoch;
      return await db.query(
        'diagnostic_logs',
        where: 'timestamp >= ?',
        whereArgs: [cutoff],
        orderBy: 'timestamp ASC',
        limit: _maxEventsPerReport,
      );
    } catch (_) {
      return const [];
    }
  }

  /// Upload the diagnostic report for [sessionId] to
  /// `diagnostics/{enterpriseId}/{userId}/reports/items/{autoId}`.
  Future<void> uploadSessionReport({
    required String sessionId,
    Map<String, dynamic>? sessionSummary,
    String reportType = 'session_end',
  }) async {
    if (!_enabled) return;
    final enterpriseId = _enterpriseId;
    final userId = _userId;
    if (enterpriseId == null || userId == null) {
      debugPrint('[DiagnosticLogger] uploadSessionReport: not configured');
      return;
    }
    try {
      final events = await readSession(sessionId);
      final deviceInfo = await _buildDeviceInfo();
      await FirebaseFirestore.instance
          .collection('diagnostics')
          .doc(enterpriseId)
          .collection(userId)
          .doc('reports')
          .collection('items')
          .add({
        'sessionId': sessionId,
        'deviceInfo': deviceInfo,
        'sessionSummary': sessionSummary,
        'events': events.map(_eventToJson).toList(),
        'uploadedAt': FieldValue.serverTimestamp(),
        'appVersion': _appVersion,
        'reportType': reportType,
      });
    } catch (e) {
      debugPrint('[DiagnosticLogger] uploadSessionReport failed: $e');
    }
  }

  /// On-demand upload of recent activity (admin-triggered via FCM).
  Future<void> uploadRecent({
    Duration window = const Duration(hours: 2),
  }) async {
    if (!_enabled) return;
    final enterpriseId = _enterpriseId;
    final userId = _userId;
    if (enterpriseId == null || userId == null) {
      debugPrint('[DiagnosticLogger] uploadRecent: not configured');
      return;
    }
    try {
      final events = await readRecent(window);
      final deviceInfo = await _buildDeviceInfo();
      await FirebaseFirestore.instance
          .collection('diagnostics')
          .doc(enterpriseId)
          .collection(userId)
          .doc('reports')
          .collection('items')
          .add({
        'sessionId': _currentSessionId,
        'deviceInfo': deviceInfo,
        'sessionSummary': null,
        'events': events.map(_eventToJson).toList(),
        'uploadedAt': FieldValue.serverTimestamp(),
        'appVersion': _appVersion,
        'reportType': 'on_demand',
      });
    } catch (e) {
      debugPrint('[DiagnosticLogger] uploadRecent failed: $e');
    }
  }

  static Map<String, dynamic> _eventToJson(Map<String, dynamic> e) => {
        'type': e['event_type'],
        'timestamp': e['timestamp'],
        'payload': e['payload'] == null
            ? null
            : jsonDecode(e['payload'] as String),
        'severity': e['severity'],
      };

  Future<Map<String, dynamic>> _buildDeviceInfo() async {
    try {
      final plugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await plugin.androidInfo;
        return {
          'platform': 'android',
          'brand': info.brand,
          'model': info.model,
          'manufacturer': info.manufacturer,
          'sdkInt': info.version.sdkInt,
          'release': info.version.release,
        };
      }
      if (Platform.isIOS) {
        final info = await plugin.iosInfo;
        return {
          'platform': 'ios',
          'model': info.model,
          'name': info.name,
          'systemVersion': info.systemVersion,
        };
      }
    } catch (_) {}
    return {'platform': Platform.operatingSystem};
  }
}
