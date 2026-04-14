import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/daily_summary_model.dart';
import '../repositories/daily_summary_repository.dart';
import '../models/user_model.dart';
import '../services/realtime_db_service.dart';
import 'enterprise_provider.dart';

class DashboardProvider extends ChangeNotifier {
  final DailySummaryRepository _summaryRepo = DailySummaryRepository();
  final RealtimeDbService _rtdb = RealtimeDbService();

  /// Reference to the enterprise-wide employee directory. Owned by
  /// [EnterpriseProvider] — this provider never fetches employees itself.
  EnterpriseProvider? _enterprise;

  Map<String, Map<String, dynamic>> _presenceData = {};
  Map<String, Map<String, dynamic>> _liveLocationData = {};
  Map<String, Map<String, dynamic>> _activeStatsData = {};
  Map<String, DailySummaryModel> _todaySummaries = {};
  bool _isLoading = false;
  bool _initialized = false;
  String? _error;
  String? _enterpriseId;
  Timer? _refreshTimer;

  StreamSubscription? _summarySubscription;
  StreamSubscription<DatabaseEvent>? _presenceSubscription;
  StreamSubscription<DatabaseEvent>? _locationSubscription;
  StreamSubscription<DatabaseEvent>? _statsSubscription;
  Timer? _liveClockTimer;

  /// Employees are owned by [EnterpriseProvider]. Returns an empty list if
  /// [attachEnterprise] has not been called yet (shouldn't happen under the
  /// splash-gated bootstrap flow).
  List<UserModel> get employees => _enterprise?.employees ?? const [];
  Map<String, Map<String, dynamic>> get presenceData => _presenceData;
  Map<String, Map<String, dynamic>> get liveLocationData => _liveLocationData;
  Map<String, Map<String, dynamic>> get activeStatsData => _activeStatsData;
  bool get isLoading => _isLoading;
  bool get isInitialized => _initialized;
  String? get error => _error;

  int get activeCount => employees
      .where((employee) => getEmployeeStatus(employee.id) == 'active')
      .length;
  int get breakCount => employees
      .where((employee) => getEmployeeStatus(employee.id) == 'break')
      .length;
  int get offlineCount => employees
      .where((employee) => getEmployeeStatus(employee.id) == 'offline')
      .length;

  /// Attach the [EnterpriseProvider] that owns the employee list. Must be
  /// called before [initDashboard]. Idempotent.
  void attachEnterprise(EnterpriseProvider enterprise) {
    if (identical(_enterprise, enterprise)) return;
    _enterprise?.removeListener(_onEnterpriseChanged);
    _enterprise = enterprise;
    _enterprise?.addListener(_onEnterpriseChanged);
  }

  void _onEnterpriseChanged() {
    // Employee list changed upstream — propagate so computed counts rebuild.
    notifyListeners();
  }

  /// Delegates to [EnterpriseProvider.refresh]. Kept for API compatibility
  /// with callers that previously asked the dashboard to refresh employees.
  Future<void> refreshEmployees(String _) async {
    await _enterprise?.refresh();
  }

  void initWithEnterpriseId(String enterpriseId) {
    if (!_isLoading && _presenceSubscription == null) {
      initDashboard(enterpriseId);
    }
  }

  // Initialize dashboard with all streams
  Future<void> initDashboard(String enterpriseId) async {
    // Idempotent — skip if already initialized for this enterprise
    if (_initialized && _enterpriseId == enterpriseId) return;

    // Cancel any existing subscriptions to prevent orphaned listeners
    // if this is called multiple times without dispose.
    _summarySubscription?.cancel();
    _presenceSubscription?.cancel();
    _locationSubscription?.cancel();
    _statsSubscription?.cancel();
    _refreshTimer?.cancel();
    _liveClockTimer?.cancel();

    _enterpriseId = enterpriseId;
    _initialized = true;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _loadEmployeesAndStreams(enterpriseId);
    } catch (e) {
      // Query may fail if token claims aren't ready — refresh and retry once
      debugPrint(
          '[DashboardProvider] First load failed: $e — retrying with token refresh');
      try {
        await FirebaseAuth.instance.currentUser?.getIdToken(true);
        await _loadEmployeesAndStreams(enterpriseId);
      } catch (retryError) {
        _error = retryError.toString();
        debugPrint('[DashboardProvider] Retry also failed: $retryError');
      }
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> _loadEmployeesAndStreams(String enterpriseId) async {
    // Employees are owned by EnterpriseProvider — already loaded by the
    // splash-gated bootstrap before this method runs. Just start the
    // dashboard-specific RTDB streams.
    _streamTodaySummaries(enterpriseId);
    _streamPresence(enterpriseId);
    _streamLiveLocations(enterpriseId);
    _streamActiveStats(enterpriseId);
    _startRefreshTimer();
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    // Periodic employee-list refresh (picks up new hires, role changes) —
    // delegated to EnterpriseProvider, the single source of truth.
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      unawaited(_enterprise?.refresh());
    });
  }

  void _streamTodaySummaries(String enterpriseId) {
    _summarySubscription?.cancel();
    final now = DateTime.now();
    final startDate = DateTime(now.year, now.month, now.day);
    final endDate = startDate.add(const Duration(days: 1));

    _summarySubscription = _summaryRepo
        .streamSummariesByEnterprise(
      enterpriseId,
      startDate: startDate,
      endDate: endDate,
    )
        .listen((summaries) {
      _todaySummaries = {
        for (final summary in summaries) summary.employeeId: summary,
      };
      notifyListeners();
    }, onError: (e) {
      debugPrint('[DashboardProvider] today summaries stream error: $e');
    });
  }

  void _streamPresence(String enterpriseId) {
    _presenceSubscription?.cancel();
    _presenceSubscription = _rtdb.streamPresence(enterpriseId).listen((event) {
      final data = event.snapshot.value;
      _presenceData = {};
      if (data is Map) {
        data.forEach((key, value) {
          if (value is Map) {
            _presenceData[key.toString()] = Map<String, dynamic>.from(value);
          }
        });
      }
      notifyListeners();
    });
  }

  void _streamLiveLocations(String enterpriseId) {
    _locationSubscription?.cancel();
    _locationSubscription =
        _rtdb.streamLiveLocations(enterpriseId).listen((event) {
      final data = event.snapshot.value;
      if (data is Map) {
        _liveLocationData = {};
        data.forEach((key, value) {
          if (value is Map) {
            _liveLocationData[key.toString()] =
                Map<String, dynamic>.from(value);
          }
        });
        notifyListeners();
      } else {
        _liveLocationData = {};
        notifyListeners();
      }
    });
  }

  void _streamActiveStats(String enterpriseId) {
    _statsSubscription?.cancel();
    _statsSubscription = _rtdb.streamActiveStats(enterpriseId).listen((event) {
      final data = event.snapshot.value;
      if (data is Map) {
        _activeStatsData = {};
        data.forEach((key, value) {
          if (value is Map) {
            _activeStatsData[key.toString()] = Map<String, dynamic>.from(value);
          }
        });
        _refreshLiveClockIfNeeded();
        notifyListeners();
      } else {
        _activeStatsData = {};
        _refreshLiveClockIfNeeded();
        notifyListeners();
      }
    });
  }

  /// Sanitize a distance value — some older sessions wrote meters instead of km.
  /// A realistic day's travel cap is ~500 km. Anything beyond that is meters.
  static double _sanitizeDistance(double rawKm) {
    if (rawKm > 500) return rawKm / 1000.0;
    return rawKm;
  }

  static const int _maxSessionDurationSecs = 16 * 3600; // 16 hours

  int _resolveLiveDurationSecs(Map<String, dynamic> stats) {
    final sessionStartTimeMs = (stats['sessionStartTimeMs'] as num?)?.toInt();
    if (sessionStartTimeMs != null) {
      final startedAt =
          DateTime.fromMillisecondsSinceEpoch(sessionStartTimeMs).toLocal();
      final elapsed = DateTime.now().difference(startedAt).inSeconds;
      // Safety cap: if more than 16 hours, this is a ghost session
      if (elapsed >= _maxSessionDurationSecs) return 0;
      if (elapsed >= 0) return elapsed;
    }
    return (stats['sessionDuration'] as num?)?.toInt() ?? 0;
  }

  void _refreshLiveClockIfNeeded() {
    final hasLiveSessions = _activeStatsData.isNotEmpty;
    if (!hasLiveSessions) {
      _liveClockTimer?.cancel();
      _liveClockTimer = null;
      return;
    }
    _liveClockTimer ??= Timer.periodic(const Duration(seconds: 10), (_) {
      if (_activeStatsData.isEmpty) {
        _liveClockTimer?.cancel();
        _liveClockTimer = null;
        return;
      }
      notifyListeners();
    });
  }

  /// Get employee status from RTDB presence. Reads `presence.status` directly
  /// — no staleness heuristics. Status is exactly one of: active, break, offline.
  String getEmployeeStatus(String userId) {
    final rawPresenceStatus = _presenceData[userId]?['status'];
    final presenceStatus = rawPresenceStatus?.toString().toLowerCase();

    if (presenceStatus == 'active') return 'active';
    if (presenceStatus == 'break') return 'break';
    return 'offline';
  }

  bool isEmployeeOnClock(String userId) {
    final status = getEmployeeStatus(userId);
    return status == 'active' || status == 'break';
  }

  // Get employee live location
  Map<String, dynamic>? getEmployeeLocation(String userId) {
    return _liveLocationData[userId];
  }

  // Get employee active stats
  Map<String, dynamic>? getEmployeeStats(String userId) {
    final stats = _activeStatsData[userId];
    final summary = _todaySummaries[userId];
    if (stats == null && summary == null) return null;

    // Only count RTDB live stats when the employee is still on-clock.
    // When a session ends, the dailySummary stream may arrive before the
    // RTDB activeStats deletion — skipping RTDB for offline employees
    // prevents brief double-counting during this race window.
    final employeeStatus = getEmployeeStatus(userId);
    final isOnClock =
        employeeStatus == 'active' || employeeStatus == 'break';
    final liveStats = (stats != null && isOnClock) ? stats : null;

    final distance = _sanitizeDistance(summary?.totalDistance ?? 0.0) +
        _sanitizeDistance((liveStats?['distance'] as num?)?.toDouble() ?? 0.0);
    final sessionDuration = (summary?.totalDuration ?? 0) +
        (liveStats != null ? _resolveLiveDurationSecs(liveStats) : 0);
    final photosToday = (summary?.photosCount ?? 0) +
        ((liveStats?['photosToday'] as num?)?.toInt() ?? 0);
    final tasksToday = (summary?.tasksCompleted ?? 0) +
        ((liveStats?['tasksToday'] as num?)?.toInt() ?? 0);

    final merged = <String, dynamic>{
      ...?stats,
      'distance': distance,
      'sessionDuration': sessionDuration,
      'photosToday': photosToday,
      'tasksToday': tasksToday,
    };

    if (summary != null) {
      merged['summaryDate'] = summary.date;
    }

    if (stats == null) {
      return merged;
    }

    return {
      ...merged,
    };
  }

  // Search employees
  List<UserModel> searchEmployees(String query) {
    if (query.isEmpty) return employees;
    final lowerQuery = query.toLowerCase();
    return employees.where((e) {
      final location =
          _liveLocationData[e.id]?['address']?.toString().toLowerCase() ?? '';
      return e.name.toLowerCase().contains(lowerQuery) ||
          location.contains(lowerQuery);
    }).toList();
  }

  @override
  void dispose() {
    _enterprise?.removeListener(_onEnterpriseChanged);
    _summarySubscription?.cancel();
    _presenceSubscription?.cancel();
    _locationSubscription?.cancel();
    _statsSubscription?.cancel();
    _liveClockTimer?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }
}
