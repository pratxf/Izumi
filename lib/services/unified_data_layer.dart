import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import '../models/activity_log_model.dart';
import '../models/daily_summary_model.dart';
import '../repositories/activity_log_repository.dart';
import '../repositories/daily_summary_repository.dart';
import 'realtime_db_service.dart';

/// Single source of truth for session-related data (distance, duration,
/// photos, activity feed) across every screen in the app.
///
/// All screens MUST call into this service instead of reading distance
/// directly from providers, RTDB, or Firestore. Sanitisation and
/// live + completed merging live here, and nowhere else.
class UnifiedDataLayer {
  UnifiedDataLayer._({
    RealtimeDbService? realtimeDb,
    DailySummaryRepository? summaryRepo,
    ActivityLogRepository? logRepo,
  })  : _rtdb = realtimeDb ?? RealtimeDbService(),
        _summaryRepo = summaryRepo ?? DailySummaryRepository(),
        _logRepo = logRepo ?? ActivityLogRepository();

  static final UnifiedDataLayer I = UnifiedDataLayer._();

  final RealtimeDbService _rtdb;
  final DailySummaryRepository _summaryRepo;
  final ActivityLogRepository _logRepo;

  // ==========================================================================
  // DISTANCE
  // ==========================================================================

  /// Distance for an employee on [date].
  /// Completed sessions → dailySummaries (server authoritative).
  /// Today with an active session → add live RTDB activeStats.
  Future<double> getDistance({
    required String employeeId,
    required String enterpriseId,
    required DateTime date,
  }) async {
    final completed = await _getCompletedDistance(employeeId, date);
    final live = _isToday(date)
        ? await _getLiveDistance(enterpriseId, employeeId)
        : 0.0;
    return completed + live;
  }

  /// Stream version: emits a new total whenever the summary or the
  /// live activeStats changes. Callers get loading via hasEmitted semantics.
  Stream<double> streamDistance({
    required String employeeId,
    required String enterpriseId,
    required DateTime date,
  }) {
    final summaryStream = _summaryRepo
        .streamDailySummaries(employeeId)
        .map((list) => _pickSummaryForDate(list, date))
        .map((summary) => summary == null
            ? 0.0
            : _sanitize(summary.totalDistance));

    if (!_isToday(date)) return summaryStream;

    final liveStream = _rtdb
        .streamUserActiveStats(enterpriseId, employeeId)
        .map((event) => _extractLiveDistance(event));

    return _combine2<double, double, double>(
      summaryStream,
      liveStream,
      (c, l) => c + l,
    );
  }

  // ==========================================================================
  // DURATION (seconds)
  // ==========================================================================

  Future<int> getDuration({
    required String employeeId,
    required String enterpriseId,
    required DateTime date,
  }) async {
    final summary = await _getSummary(employeeId, date);
    final completed = summary?.totalDuration ?? 0;

    if (!_isToday(date)) return completed;

    final liveSecs = await _getLiveDurationSeconds(enterpriseId, employeeId);
    return completed + liveSecs;
  }

  // ==========================================================================
  // ACTIVITY FEED
  // ==========================================================================

  /// One-shot activity feed load. Self-contained — does NOT depend on any
  /// provider being initialised first.
  Future<List<ActivityLogModel>> getActivityFeed({
    required String employeeId,
    required String enterpriseId,
    required DateTime from,
    required DateTime to,
    int limit = 100,
  }) async {
    try {
      return await _logRepo.getLogsByEmployeeIds(
        [employeeId],
        startDate: from,
        endDate: to,
        limit: limit,
      );
    } catch (e) {
      debugPrint('[UnifiedDataLayer] getActivityFeed failed: $e');
      return const [];
    }
  }

  /// Stream variant with cold-start cache prime. Before opening the
  /// snapshot stream, a one-shot server get() runs so the stream's first
  /// emission hits a warmed-up local cache instead of racing the network.
  /// If the narrow employeeId query returns empty, an enterprise-wide
  /// prime runs as a fallback (mirrors AdminActivityFeedService).
  ///
  /// Accepts a list of employee IDs so migration-chain feeds (current uid +
  /// prior migrated-from IDs) stay visible. Firestore `whereIn` is capped at
  /// 30 values — callers passing more than 30 linked IDs will have the list
  /// truncated.
  Stream<List<ActivityLogModel>> streamActivityFeed({
    required List<String> employeeIds,
    required String enterpriseId,
    required DateTime from,
    int limit = 100,
  }) async* {
    final ids = employeeIds
        .where((id) => id.isNotEmpty)
        .toSet()
        .take(30)
        .toList();
    if (ids.isEmpty) {
      yield const <ActivityLogModel>[];
      return;
    }

    final q = FirebaseFirestore.instance
        .collection('activityLogs')
        .where('employeeId', whereIn: ids)
        .where('timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(from))
        .orderBy('timestamp', descending: true)
        .limit(limit);

    // Prime the local Firestore cache with a one-shot server fetch so the
    // stream's first emission has real data instead of an empty cache.
    try {
      final primary =
          await q.get(const GetOptions(source: Source.server));
      if (primary.docs.isEmpty && enterpriseId.isNotEmpty) {
        // Fallback: enterprise-wide prime for cases where the narrow
        // employeeId query comes back empty (index propagation delay,
        // data-shape drift). We don't consume this result — the goal is
        // just to populate the SDK's local cache.
        try {
          await FirebaseFirestore.instance
              .collection('activityLogs')
              .where('enterpriseId', isEqualTo: enterpriseId)
              .where('timestamp',
                  isGreaterThanOrEqualTo: Timestamp.fromDate(from))
              .orderBy('timestamp', descending: true)
              .limit(200)
              .get(const GetOptions(source: Source.server));
        } catch (_) {}
      }
    } catch (_) {
      // Offline or slow — proceed anyway, the stream will keep retrying.
    }

    yield* q.snapshots().map(
          (snap) => snap.docs
              .map((d) => ActivityLogModel.fromFirestore(d))
              .toList(),
        );
  }

  // ==========================================================================
  // COMBINED DAY STATS
  // ==========================================================================

  Future<EmployeeDayStats> getDayStats({
    required String employeeId,
    required String enterpriseId,
    required DateTime date,
  }) async {
    final summary = await _getSummary(employeeId, date);
    final completedDistance =
        summary == null ? 0.0 : _sanitize(summary.totalDistance);
    final completedDuration = summary?.totalDuration ?? 0;
    final completedPhotos = summary?.photosCount ?? 0;

    double liveDistance = 0;
    int liveDuration = 0;
    int livePhotos = 0;
    int? sessionStartTimeMs;

    if (_isToday(date)) {
      final stats = await _readActiveStats(enterpriseId, employeeId);
      if (stats != null) {
        liveDistance =
            _sanitize((stats['distance'] as num?)?.toDouble() ?? 0.0);
        liveDuration = _resolveLiveDurationSecs(stats);
        livePhotos = (stats['photosToday'] as num?)?.toInt() ?? 0;
        sessionStartTimeMs =
            (stats['sessionStartTimeMs'] as num?)?.toInt();
      }
    }

    return EmployeeDayStats(
      distance: completedDistance + liveDistance,
      duration: completedDuration + liveDuration,
      photos: completedPhotos + livePhotos,
      sessionStartTimeMs: sessionStartTimeMs,
    );
  }

  // ==========================================================================
  // INTERNAL HELPERS
  // ==========================================================================

  Future<DailySummaryModel?> _getSummary(
      String employeeId, DateTime date) async {
    try {
      return await _summaryRepo.getDailySummary(employeeId, date);
    } catch (e) {
      debugPrint('[UnifiedDataLayer] _getSummary failed: $e');
      return null;
    }
  }

  Future<double> _getCompletedDistance(
      String employeeId, DateTime date) async {
    final summary = await _getSummary(employeeId, date);
    if (summary == null) return 0.0;
    return _sanitize(summary.totalDistance);
  }

  Future<double> _getLiveDistance(
      String enterpriseId, String employeeId) async {
    final stats = await _readActiveStats(enterpriseId, employeeId);
    if (stats == null) return 0.0;
    final raw = (stats['distance'] as num?)?.toDouble() ?? 0.0;
    return _sanitize(raw);
  }

  Future<int> _getLiveDurationSeconds(
      String enterpriseId, String employeeId) async {
    final stats = await _readActiveStats(enterpriseId, employeeId);
    if (stats == null) return 0;
    return _resolveLiveDurationSecs(stats);
  }

  Future<Map<String, dynamic>?> _readActiveStats(
      String enterpriseId, String employeeId) async {
    try {
      final stream =
          _rtdb.streamUserActiveStats(enterpriseId, employeeId);
      final event = await stream.first.timeout(
        const Duration(seconds: 3),
        onTimeout: () => throw TimeoutException('activeStats read timeout'),
      );
      final value = event.snapshot.value;
      if (value is Map) {
        return value.map((k, v) => MapEntry(k.toString(), v));
      }
      return null;
    } catch (e) {
      debugPrint('[UnifiedDataLayer] _readActiveStats failed: $e');
      return null;
    }
  }

  double _extractLiveDistance(DatabaseEvent event) {
    final value = event.snapshot.value;
    if (value is! Map) return 0.0;
    final raw = (value['distance'] as num?)?.toDouble() ?? 0.0;
    final startMs = (value['sessionStartTimeMs'] as num?)?.toInt();
    if (startMs == null) return 0.0;
    return _sanitize(raw);
  }

  int _resolveLiveDurationSecs(Map<String, dynamic> stats) {
    final startMs = (stats['sessionStartTimeMs'] as num?)?.toInt();
    if (startMs != null && startMs > 0) {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final diff = (nowMs - startMs) ~/ 1000;
      // 16h cap — matches legacy ghost-session protection.
      return diff.clamp(0, 16 * 3600);
    }
    final fallback = (stats['sessionDuration'] as num?)?.toInt() ?? 0;
    return fallback.clamp(0, 16 * 3600);
  }

  DailySummaryModel? _pickSummaryForDate(
      List<DailySummaryModel> list, DateTime date) {
    for (final s in list) {
      if (s.date.year == date.year &&
          s.date.month == date.month &&
          s.date.day == date.day) {
        return s;
      }
    }
    return null;
  }

  bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  /// The ONLY copy of the meters-vs-kilometers sanitisation in the
  /// codebase. A legacy bug wrote meter-valued numbers into the `km`
  /// field. Values > 500 are almost certainly meters.
  double _sanitize(double value) => sanitizeKm(value);

  /// Public wrapper so legacy provider code (dashboard, analytics, history)
  /// can route through the same sanitisation rule while it's being
  /// migrated away from direct distance reads. Outside of UDL, this is
  /// the only way to sanitise a km value.
  static double sanitizeKm(double value) {
    if (value.isNaN || value.isInfinite || value < 0) return 0.0;
    if (value > 500) return value / 1000;
    return value;
  }

  /// Combines two streams by emitting the latest (a,b) pair whenever
  /// either emits. Emits as soon as both sides have produced a value.
  static Stream<R> _combine2<A, B, R>(
      Stream<A> a, Stream<B> b, R Function(A, B) f) {
    final controller = StreamController<R>();
    A? lastA;
    B? lastB;
    var hasA = false;
    var hasB = false;

    void pushIfReady() {
      if (hasA && hasB) controller.add(f(lastA as A, lastB as B));
    }

    final subA = a.listen((v) {
      lastA = v;
      hasA = true;
      pushIfReady();
    }, onError: controller.addError);
    final subB = b.listen((v) {
      lastB = v;
      hasB = true;
      pushIfReady();
    }, onError: controller.addError);

    controller.onCancel = () async {
      await subA.cancel();
      await subB.cancel();
    };
    return controller.stream;
  }
}

class EmployeeDayStats {
  const EmployeeDayStats({
    required this.distance,
    required this.duration,
    required this.photos,
    this.sessionStartTimeMs,
  });

  final double distance; // km
  final int duration; // seconds
  final int photos;
  final int? sessionStartTimeMs;
}
