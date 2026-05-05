import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/daily_summary_model.dart';
import '../models/activity_log_model.dart';
import '../models/session_model.dart';
import '../models/user_model.dart';
import '../repositories/daily_summary_repository.dart';
import '../repositories/activity_log_repository.dart';
import '../repositories/photo_repository.dart';
import '../services/realtime_db_service.dart';
import '../services/session_query_helper.dart';
import '../services/unified_data_layer.dart';
import 'enterprise_provider.dart';

class AnalyticsProvider extends ChangeNotifier {
  bool _disposed = false;
  final DailySummaryRepository _summaryRepo = DailySummaryRepository();
  final SessionQueryHelper _sessionHelper = SessionQueryHelper();
  final ActivityLogRepository _logRepo = ActivityLogRepository();
  final PhotoRepository _photoRepo = PhotoRepository();
  final RealtimeDbService _rtdb = RealtimeDbService();

  /// Reference to the enterprise-wide employee directory. Owned by
  /// [EnterpriseProvider] — this provider never fetches employees itself.
  EnterpriseProvider? _enterprise;

  String _selectedPeriod = 'Today';
  DateTime? _customStart;
  DateTime? _customEnd;
  Map<String, List<DailySummaryModel>> _employeeSummaries = {};
  final Map<String, List<ActivityLogModel>> _employeeLogs = {};
  Map<String, Map<String, dynamic>> _activeStatsData = {};
  Map<String, int> _employeePhotoCounts = {};
  Map<String, int> _employeeLeaveCounts = {};
  /// Per-employee distance for the currently-loaded range, computed via
  /// UnifiedDataLayer-compatible logic in [_computeEmployeeDistance] and
  /// rebuilt on every [_recomputeTotals] pass.
  Map<String, double> _employeeDistanceCache = {};
  /// Session-based fallback data: when dailySummaries are empty (e.g. auto-ended
  /// sessions that never wrote a summary), we compute stats from sessions directly.
  Map<String, List<SessionModel>> _employeeSessions = {};
  bool _sessionFallbackLoaded = false;
  int _actualTotalPhotos = 0;
  bool _isLoading = false;
  String? _error;

  // Stream subscriptions for real-time updates
  StreamSubscription? _summarySubscription;
  StreamSubscription? _logSubscription;
  StreamSubscription<DatabaseEvent>? _activeStatsSubscription;
  Timer? _liveClockTimer;

  // Aggregate stats (computed from completed sessions + live active sessions)
  int _totalDurationSecs = 0;
  double _totalDistance = 0.0;
  int _totalPhotos = 0;
  int _totalTasks = 0;

  String get selectedPeriod => _selectedPeriod;
  DateTime? get customStart => _customStart;
  DateTime? get customEnd => _customEnd;
  /// Employees are owned by [EnterpriseProvider]. Returns an empty list if
  /// [attachEnterprise] has not been called yet (shouldn't happen under the
  /// splash-gated bootstrap flow).
  List<UserModel> get employees => _enterprise?.employees ?? const [];

  /// Attach the [EnterpriseProvider] that owns the employee list. Must be
  /// called before [loadAnalytics]. Idempotent.
  void attachEnterprise(EnterpriseProvider enterprise) {
    if (identical(_enterprise, enterprise)) return;
    _enterprise?.removeListener(_onEnterpriseChanged);
    _enterprise = enterprise;
    _enterprise?.addListener(_onEnterpriseChanged);
  }

  void _onEnterpriseChanged() {
    if (_disposed) return;
    // The enterprise user directory just changed (user deleted, new user
    // migrated, etc). Purge stale entries for employeeIds that no longer
    // have a user doc so deleted/orphan users don't inflate totals.
    _purgeOrphanData();
    _recomputeTotals();
    notifyListeners();
  }

  /// Set of `users/{id}` doc IDs that belong to the current enterprise. When
  /// the enterprise provider hasn't loaded yet we return `null` and all
  /// employeeIds are passed through (recomputed as soon as the directory
  /// arrives via [_onEnterpriseChanged]).
  Set<String>? _activeUserIdSnapshot() {
    final ent = _enterprise;
    if (ent == null || !ent.isReady) return null;
    return ent.users.map((u) => u.id).toSet();
  }

  bool _shouldIncludeEmployee(String employeeId) {
    final snap = _activeUserIdSnapshot();
    if (snap == null) return true;
    return snap.contains(employeeId);
  }

  void _purgeOrphanData() {
    final snap = _activeUserIdSnapshot();
    if (snap == null) return;
    _employeeSummaries.removeWhere((id, _) => !snap.contains(id));
    _employeeSessions.removeWhere((id, _) => !snap.contains(id));
    _employeePhotoCounts.removeWhere((id, _) => !snap.contains(id));
    _employeeLogs.removeWhere((id, _) => !snap.contains(id));
    _activeStatsData.removeWhere((id, _) => !snap.contains(id));
    _employeeLeaveCounts.removeWhere((id, _) => !snap.contains(id));
    _actualTotalPhotos =
        _employeePhotoCounts.values.fold<int>(0, (a, b) => a + b);
  }
  Map<String, List<DailySummaryModel>> get employeeSummaries =>
      _employeeSummaries;
  Map<String, List<SessionModel>> get employeeSessions => _employeeSessions;
  Map<String, List<ActivityLogModel>> get employeeLogs => _employeeLogs;
  Map<String, Map<String, dynamic>> get activeStatsData => _activeStatsData;
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get totalHours => Duration(seconds: _totalDurationSecs).inHours;
  String get formattedTotalDuration => _formatDuration(_totalDurationSecs);
  double get totalDistance => _totalDistance;
  int get totalPhotos => _totalPhotos;
  int get totalTasks => _totalTasks;

  static String _formatDuration(int totalSeconds) {
    final d = Duration(seconds: totalSeconds);
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0 && m > 0) return '${h}h ${m}m';
    if (h > 0) return '${h}h';
    return '${m}m';
  }

  static const int _maxSessionDurationSecs = 16 * 3600; // 16 hours cap

  int _resolveLiveDurationSecs(Map<String, dynamic> stats) {
    final sessionStartTimeMs = (stats['sessionStartTimeMs'] as num?)?.toInt();
    if (sessionStartTimeMs != null) {
      final startedAt =
          DateTime.fromMillisecondsSinceEpoch(sessionStartTimeMs).toLocal();
      final elapsed = DateTime.now().difference(startedAt).inSeconds;
      // Return 0 for ghost sessions (same logic as DashboardProvider)
      if (elapsed >= _maxSessionDurationSecs) return 0;
      if (elapsed >= 0) return elapsed;
    }
    final raw = (stats['sessionDuration'] as num?)?.toInt() ?? 0;
    return raw.clamp(0, _maxSessionDurationSecs);
  }

  void _refreshLiveClockIfNeeded() {
    final hasLiveSessions = _activeStatsData.isNotEmpty;
    if (!hasLiveSessions) {
      _liveClockTimer?.cancel();
      _liveClockTimer = null;
      return;
    }
    _liveClockTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed || _activeStatsData.isEmpty) {
        _liveClockTimer?.cancel();
        _liveClockTimer = null;
        return;
      }
      final prevMinutes = Duration(seconds: _totalDurationSecs).inMinutes;
      _recomputeTotals();
      final newMinutes = Duration(seconds: _totalDurationSecs).inMinutes;
      // Only rebuild widgets when the displayed minute rolls over
      if (newMinutes != prevMinutes) {
        notifyListeners();
      }
    });
  }

  Future<void> loadAnalytics(String enterpriseId, {String? period}) async {
    if (period != null) _selectedPeriod = period;
    _isLoading = true;
    notifyListeners();

    try {
      // Employees are owned by EnterpriseProvider — already loaded by the
      // splash-gated bootstrap. No fetch needed here.

      // Determine date range based on period
      final dateRange = _getDateRange();

      // Cancel previous streams
      _summarySubscription?.cancel();
      _logSubscription?.cancel();
      _activeStatsSubscription?.cancel();

      // Reset session fallback state for new load
      _employeeSessions = {};
      _sessionFallbackLoaded = false;

      // Stream completed-session summaries from Firestore
      _summarySubscription = _summaryRepo
          .streamSummariesByEnterprise(
        enterpriseId,
        startDate: dateRange.$1,
        endDate: dateRange.$2,
      )
          .listen((summaries) {
        _processSummaries(summaries);
        _recomputeTotals();
        notifyListeners();
      }, onError: (e) {
        debugPrint('[AnalyticsProvider] summary stream error: $e');
      });

      // Stream activity logs from Firestore
      _logSubscription =
          _logRepo.streamLogsByEnterprise(enterpriseId).listen((logs) {
        _processLogs(logs);
        notifyListeners();
      }, onError: (e) {
        debugPrint('[AnalyticsProvider] log stream error: $e');
      });

      // Load actual photo counts from the photos collection so totals
      // aren't limited to what dailySummaries recorded.
      _loadPhotoCounts(enterpriseId, dateRange.$1, dateRange.$2);

      // Load leave counts for the current date range.
      _loadLeaveCounts(enterpriseId, dateRange.$1, dateRange.$2);

      // Proactively load session fallback so analytics isn't blank while
      // waiting for the dailySummaries stream to emit.
      _loadSessionFallback(enterpriseId, dateRange.$1, dateRange.$2);

      // Stream live active-session stats from RTDB (updated every 30s)
      _activeStatsSubscription =
          _rtdb.streamActiveStats(enterpriseId).listen((event) {
        final data = event.snapshot.value;
        _activeStatsData = {};
        if (data is Map) {
          data.forEach((key, value) {
            if (value is! Map) return;
            final id = key.toString();
            if (!_shouldIncludeEmployee(id)) return;
            _activeStatsData[id] = Map<String, dynamic>.from(value);
          });
        }
        _refreshLiveClockIfNeeded();
        _recomputeTotals();
        notifyListeners();
      }, onError: (e) {
        debugPrint('[AnalyticsProvider] active stats stream error: $e');
      });
    } catch (e) {
      _error = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  (DateTime, DateTime) _getDateRange() {
    final now = DateTime.now();
    DateTime startDate;

    switch (_selectedPeriod) {
      case 'Today':
        startDate = DateTime(now.year, now.month, now.day);
        break;
      case 'Yesterday':
        final yesterday = now.subtract(const Duration(days: 1));
        startDate = DateTime(yesterday.year, yesterday.month, yesterday.day);
        return (startDate, DateTime(yesterday.year, yesterday.month, yesterday.day, 23, 59, 59));
      case 'This Week':
        startDate = now.subtract(Duration(days: now.weekday - 1));
        startDate = DateTime(startDate.year, startDate.month, startDate.day);
        break;
      case 'This Month':
        startDate = DateTime(now.year, now.month, 1);
        break;
      case 'Custom':
        if (_customStart != null && _customEnd != null) {
          return (_customStart!, _customEnd!);
        }
        startDate = DateTime(now.year, now.month, now.day);
        break;
      default:
        startDate = DateTime(now.year, now.month, now.day);
    }

    return (startDate, now);
  }

  void _processSummaries(List<DailySummaryModel> allSummaries) {
    _employeeSummaries = {};
    for (final s in allSummaries) {
      if (!_shouldIncludeEmployee(s.employeeId)) continue;
      _employeeSummaries.putIfAbsent(s.employeeId, () => []).add(s);
    }
  }

  /// Always load sessions directly alongside dailySummaries.
  /// Auto-ended sessions and admin force-ended sessions never write
  /// dailySummary docs, so we must read sessions to get complete data.
  Future<void> _loadSessionFallback(
    String enterpriseId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    if (_sessionFallbackLoaded) return;
    _sessionFallbackLoaded = true;

    final sessions = await _sessionHelper.loadSessions(
      enterpriseId: enterpriseId,
      startDate: startDate,
      endDate: endDate,
    );

    _employeeSessions = {};
    for (final s in sessions) {
      if (!_shouldIncludeEmployee(s.employeeId)) continue;
      _employeeSessions.putIfAbsent(s.employeeId, () => []).add(s);
    }
    _recomputeTotals();
    notifyListeners();
  }

  /// Recompute aggregate totals from both completed (Firestore) and
  /// live active (RTDB) sources. No double-counting because RTDB stats
  /// are cleared when a session ends, and dailySummaries are only
  /// written on session completion.
  void _recomputeTotals() {
    _totalDurationSecs = 0;
    _totalDistance = 0.0;
    _totalPhotos = 0;
    _totalTasks = 0;

    // Rebuild the per-employee distance map using the same logic UDL uses
    // (summary.totalDistance → sanitize + live RTDB top-up). No session
    // fallback for distance — UDL does not read session.totalDistance, so
    // this provider must not either. Duration/photos/tasks keep the session
    // fallback because Phase 3 only unifies distance.
    _employeeDistanceCache = {};

    final allEmployeeIds = <String>{
      ..._employeeSummaries.keys,
      ..._employeeSessions.keys,
      ..._activeStatsData.keys,
    };

    for (final empId in allEmployeeIds) {
      final summaries = _employeeSummaries[empId] ?? [];
      final sessions = _employeeSessions[empId] ?? [];

      int summaryDuration = 0;
      int summaryPhotos = 0;
      int summaryTasks = 0;
      for (final s in summaries) {
        summaryDuration += s.totalDuration.clamp(0, _maxSessionDurationSecs);
        summaryPhotos += s.photosCount;
        summaryTasks += s.tasksCompleted;
      }

      int sessionDuration = 0;
      int sessionPhotos = 0;
      int sessionTasks = 0;
      for (final session in sessions) {
        sessionDuration +=
            session.totalDuration.clamp(0, _maxSessionDurationSecs);
        sessionPhotos += session.photosCount;
        sessionTasks += session.tasksCompleted;
      }

      if (summaries.isNotEmpty) {
        _totalDurationSecs += summaryDuration;
        _totalPhotos += summaryPhotos;
        _totalTasks += summaryTasks;

        final coveredSessionIds = <String>{
          for (final s in summaries) ...s.sessionIds,
        };
        for (final session in sessions) {
          if (coveredSessionIds.contains(session.id)) continue;
          _totalDurationSecs +=
              session.totalDuration.clamp(0, _maxSessionDurationSecs);
          _totalPhotos += session.photosCount;
          _totalTasks += session.tasksCompleted;
        }
      } else {
        _totalDurationSecs += sessionDuration;
        _totalPhotos += sessionPhotos;
        _totalTasks += sessionTasks;
      }

      final empDistance = _computeEmployeeDistance(empId);
      _employeeDistanceCache[empId] = empDistance;
      _totalDistance += empDistance;
    }

    // Duration/photos/tasks from currently active sessions (RTDB activeStats).
    // Distance is already folded in via _computeEmployeeDistance above.
    for (final stats in _activeStatsData.values) {
      _totalDurationSecs += _resolveLiveDurationSecs(stats);
      _totalPhotos += (stats['photosToday'] as num?)?.toInt() ?? 0;
      _totalTasks += (stats['tasksToday'] as num?)?.toInt() ?? 0;
    }

    // Use the actual photo count from the photos collection when it's higher
    // than the summary-based count (dailySummaries often undercount).
    if (_actualTotalPhotos > _totalPhotos) {
      _totalPhotos = _actualTotalPhotos;
    }
  }

  /// Canonical per-employee distance in km, sourced via UDL-compatible
  /// logic (sanitised summaries + live RTDB) and cached in
  /// [_employeeDistanceCache]. Callers should use this instead of reading
  /// `getEmployeeStats()['distance']` so the distance pipeline is explicit.
  double getEmployeeDistance(String employeeId) =>
      _employeeDistanceCache[employeeId] ?? 0.0;

  /// Canonical per-employee distance for the currently-loaded date range.
  /// Mirrors UnifiedDataLayer.getDistance logic: sanitised
  /// summary.totalDistance for every day in the range, plus live RTDB
  /// activeStats when that employee has a running session today. Used by
  /// both getEmployeeStats (per row) and _recomputeTotals (aggregate).
  double _computeEmployeeDistance(String employeeId) {
    final summaries = _employeeSummaries[employeeId] ?? const [];
    double distance = 0.0;
    for (final s in summaries) {
      distance += UnifiedDataLayer.sanitizeKm(s.totalDistance);
    }
    final liveStats = _activeStatsData[employeeId];
    if (liveStats != null) {
      final raw = (liveStats['distance'] as num?)?.toDouble() ?? 0.0;
      distance += UnifiedDataLayer.sanitizeKm(raw);
    }
    return distance;
  }


  Future<void> _loadPhotoCounts(
    String enterpriseId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    try {
      final photos = await _photoRepo.getPhotosByEnterprise(
        enterpriseId,
        startDate: startDate,
        endDate: endDate,
        limit: 500,
      );
      final counts = <String, int>{};
      var total = 0;
      for (final photo in photos) {
        if (!_shouldIncludeEmployee(photo.employeeId)) continue;
        counts[photo.employeeId] = (counts[photo.employeeId] ?? 0) + 1;
        total++;
      }
      _employeePhotoCounts = counts;
      _actualTotalPhotos = total;
      _recomputeTotals();
      notifyListeners();
    } catch (e) {
      debugPrint('[AnalyticsProvider] _loadPhotoCounts error: $e');
    }
  }

  Future<void> _loadLeaveCounts(
    String enterpriseId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    try {
      String dateKey(DateTime d) =>
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final startKey = dateKey(startDate);
      final endKey = dateKey(endDate);

      final snap = await FirebaseFirestore.instance
          .collection('leaves')
          .where('enterpriseId', isEqualTo: enterpriseId)
          .where('date', isGreaterThanOrEqualTo: startKey)
          .where('date', isLessThanOrEqualTo: endKey)
          .get();

      final counts = <String, int>{};
      for (final doc in snap.docs) {
        final empId = doc.data()['employeeId'] as String? ?? '';
        if (empId.isEmpty || !_shouldIncludeEmployee(empId)) continue;
        counts[empId] = (counts[empId] ?? 0) + 1;
      }
      _employeeLeaveCounts = counts;
      notifyListeners();
    } catch (e) {
      debugPrint('[AnalyticsProvider] _loadLeaveCounts error: $e');
    }
  }

  int getEmployeeLeaveCount(String employeeId) =>
      _employeeLeaveCounts[employeeId] ?? 0;

  void _processLogs(List<ActivityLogModel> allLogs) {
    _employeeLogs.clear();
    for (final log in allLogs) {
      if (!_shouldIncludeEmployee(log.employeeId)) continue;
      _employeeLogs.putIfAbsent(log.employeeId, () => []).add(log);
    }
  }

  void setPeriod(String period) {
    _selectedPeriod = period;
    notifyListeners();
  }

  Future<void> loadCustomRange(
    String enterpriseId,
    DateTime start,
    DateTime end,
  ) async {
    _customStart = DateTime(start.year, start.month, start.day);
    _customEnd = DateTime(end.year, end.month, end.day, 23, 59, 59);
    await loadAnalytics(enterpriseId, period: 'Custom');
  }

  // Get aggregated stats for a specific employee (completed + live)
  Map<String, dynamic> getEmployeeStats(String employeeId) {
    final summaries = _employeeSummaries[employeeId] ?? [];
    final sessions = _employeeSessions[employeeId] ?? [];

    // Duration/photos/tasks still use the summary-preferred, session-fallback
    // pattern — Phase 3 only unifies distance. Distance comes exclusively
    // from _employeeDistanceCache which mirrors UDL.getDistance logic.
    int summaryDuration = 0;
    int summaryPhotos = 0;
    int summaryTasks = 0;
    for (final s in summaries) {
      summaryDuration += s.totalDuration.clamp(0, _maxSessionDurationSecs);
      summaryPhotos += s.photosCount;
      summaryTasks += s.tasksCompleted;
    }

    int sessionDuration = 0;
    int sessionPhotos = 0;
    int sessionTasks = 0;
    for (final session in sessions) {
      sessionDuration += session.totalDuration.clamp(0, _maxSessionDurationSecs);
      sessionPhotos += session.photosCount;
      sessionTasks += session.tasksCompleted;
    }

    int durationSecs;
    int photos;
    int tasks;
    if (summaries.isNotEmpty) {
      durationSecs = summaryDuration;
      photos = summaryPhotos;
      tasks = summaryTasks;

      final coveredSessionIds = <String>{
        for (final s in summaries) ...s.sessionIds,
      };
      for (final session in sessions) {
        if (coveredSessionIds.contains(session.id)) continue;
        durationSecs +=
            session.totalDuration.clamp(0, _maxSessionDurationSecs);
        photos += session.photosCount;
        tasks += session.tasksCompleted;
      }
    } else {
      durationSecs = sessionDuration;
      photos = sessionPhotos;
      tasks = sessionTasks;
    }

    // Add live duration/photos/tasks from currently active session.
    // Distance is already folded into _employeeDistanceCache.
    final liveStats = _activeStatsData[employeeId];
    if (liveStats != null) {
      durationSecs += _resolveLiveDurationSecs(liveStats);
      photos += (liveStats['photosToday'] as num?)?.toInt() ?? 0;
      tasks += (liveStats['tasksToday'] as num?)?.toInt() ?? 0;
    }

    // UDL-routed distance (summary-sanitised + live RTDB). Same calculation
    // everywhere — dashboard, analytics, history, TL monitor.
    final distance = _employeeDistanceCache[employeeId] ?? 0.0;

    // Use actual photo count from photos collection when higher
    final actualPhotos = _employeePhotoCounts[employeeId] ?? 0;
    if (actualPhotos > photos) {
      photos = actualPhotos;
    }

    return {
      'hours': Duration(seconds: durationSecs).inHours,
      'durationSecs': durationSecs,
      'duration': _formatDuration(durationSecs),
      'distance': distance,
      'photos': photos,
      'tasks': tasks,
    };
  }

  // Get activity logs for an employee
  List<ActivityLogModel> getLogsForEmployee(String employeeId) {
    return _employeeLogs[employeeId] ?? [];
  }

  String? getResolvedProfileImageUrl(String employeeId) {
    final relatedIds = <String>{employeeId};

    var changed = true;
    while (changed) {
      changed = false;
      for (final employee in employees) {
        final migratedFrom = employee.migratedFrom;
        final isLinked = relatedIds.contains(employee.id) ||
            (migratedFrom != null && relatedIds.contains(migratedFrom));
        if (!isLinked) continue;

        if (relatedIds.add(employee.id)) {
          changed = true;
        }
        if (migratedFrom != null &&
            migratedFrom.trim().isNotEmpty &&
            relatedIds.add(migratedFrom.trim())) {
          changed = true;
        }
      }
    }

    String? exact;
    String? linked;
    for (final employee in employees) {
      final url = employee.profileImageUrl?.trim();
      if (url == null || url.isEmpty) continue;
      if (employee.id == employeeId) {
        exact = url;
        break;
      }
      if (relatedIds.contains(employee.id)) {
        linked ??= url;
      }
    }

    return exact ?? linked;
  }

  @override
  void dispose() {
    _disposed = true;
    _enterprise?.removeListener(_onEnterpriseChanged);
    _summarySubscription?.cancel();
    _logSubscription?.cancel();
    _activeStatsSubscription?.cancel();
    _liveClockTimer?.cancel();
    super.dispose();
  }
}
