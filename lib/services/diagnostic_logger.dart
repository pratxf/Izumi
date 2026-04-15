import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../offline_queue/app_database.dart';

/// Singleton logger that writes structured diagnostic events to a local
/// SQLite table. Designed to never block or crash the tracking pipeline:
/// every call is async fire-and-forget, every failure is swallowed, and
/// when [enabled] is false the logger is a zero-cost no-op.
///
/// Usage:
/// ```dart
/// DiagnosticLogger.I.log('gps_fix_rejected', {'reason': 'accuracy_too_low'});
/// ```
class DiagnosticLogger {
  DiagnosticLogger._();
  static final DiagnosticLogger I = DiagnosticLogger._();

  static const String _enabledFlagKey = 'diagnostic_logger.enabled';
  static const Duration _retention = Duration(days: 7);
  static const int _maxEventsPerReport = 500;

  bool _enabled = false;
  bool _initialized = false;
  String? _currentSessionId;

  bool get enabled => _enabled;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_enabledFlagKey) ?? false;
      if (_enabled) {
        await _purgeOld();
      }
    } catch (_) {/* never throw */}
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
      // Keep the most recent N events on overflow.
      return rows.sublist(rows.length - _maxEventsPerReport);
    } catch (_) {
      return const [];
    }
  }

  /// Read the last [duration] of events regardless of session.
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

  /// Upload the diagnostic report for [sessionId] to Firestore at
  /// `diagnostics/{enterpriseId}/{userId}/reports/{reportId}`.
  Future<void> uploadSessionReport({
    required String enterpriseId,
    required String userId,
    required String sessionId,
    required Map<String, dynamic> deviceInfo,
    required Map<String, dynamic> sessionSummary,
    required String appVersion,
    String reportType = 'session_end',
  }) async {
    if (!_enabled) return;
    try {
      final events = await readSession(sessionId);
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
        'events': events
            .map((e) => {
                  'type': e['event_type'],
                  'timestamp': e['timestamp'],
                  'payload': e['payload'] == null
                      ? null
                      : jsonDecode(e['payload'] as String),
                  'severity': e['severity'],
                })
            .toList(),
        'uploadedAt': FieldValue.serverTimestamp(),
        'appVersion': appVersion,
        'reportType': reportType,
      });
    } catch (e) {
      debugPrint('[DiagnosticLogger] uploadSessionReport failed: $e');
    }
  }

  /// On-demand upload of recent activity (e.g. admin-triggered).
  Future<void> uploadRecent({
    required String enterpriseId,
    required String userId,
    required Map<String, dynamic> deviceInfo,
    required String appVersion,
    Duration window = const Duration(hours: 2),
  }) async {
    if (!_enabled) return;
    try {
      final events = await readRecent(window);
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
        'events': events
            .map((e) => {
                  'type': e['event_type'],
                  'timestamp': e['timestamp'],
                  'payload': e['payload'] == null
                      ? null
                      : jsonDecode(e['payload'] as String),
                  'severity': e['severity'],
                })
            .toList(),
        'uploadedAt': FieldValue.serverTimestamp(),
        'appVersion': appVersion,
        'reportType': 'on_demand',
      });
    } catch (e) {
      debugPrint('[DiagnosticLogger] uploadRecent failed: $e');
    }
  }
}
