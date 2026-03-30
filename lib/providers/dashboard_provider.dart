import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/daily_summary_model.dart';
import '../repositories/daily_summary_repository.dart';
import '../models/user_model.dart';
import '../repositories/user_repository.dart';
import '../services/realtime_db_service.dart';

class DashboardProvider extends ChangeNotifier {
  // Background location updates can legitimately arrive ~20 minutes apart,
  // so the dashboard should not mark a user offline too aggressively.
  static const Duration _liveLocationActiveGrace = Duration(minutes: 25);

  final UserRepository _userRepo = UserRepository();
  final DailySummaryRepository _summaryRepo = DailySummaryRepository();
  final RealtimeDbService _rtdb = RealtimeDbService();

  List<UserModel> _employees = [];
  Map<String, Map<String, dynamic>> _presenceData = {};
  Map<String, Map<String, dynamic>> _liveLocationData = {};
  Map<String, Map<String, dynamic>> _activeStatsData = {};
  Map<String, DailySummaryModel> _todaySummaries = {};
  bool _isLoading = false;
  String? _error;

  StreamSubscription? _summarySubscription;
  StreamSubscription<DatabaseEvent>? _presenceSubscription;
  StreamSubscription<DatabaseEvent>? _locationSubscription;
  StreamSubscription<DatabaseEvent>? _statsSubscription;
  Timer? _liveClockTimer;

  List<UserModel> get employees => _employees;
  Map<String, Map<String, dynamic>> get presenceData => _presenceData;
  Map<String, Map<String, dynamic>> get liveLocationData => _liveLocationData;
  Map<String, Map<String, dynamic>> get activeStatsData => _activeStatsData;
  bool get isLoading => _isLoading;
  String? get error => _error;

  int get activeCount => _employees
      .where((employee) => getEmployeeStatus(employee.id) == 'active')
      .length;
  int get breakCount => _employees
      .where((employee) => getEmployeeStatus(employee.id) == 'break')
      .length;
  int get signalLostCount => _employees
      .where((employee) => getEmployeeStatus(employee.id) == 'signal_lost')
      .length;
  int get offlineCount => _employees
      .where((employee) => getEmployeeStatus(employee.id) == 'offline')
      .length;

  // Lightweight refresh of just the employee list (no stream restart)
  Future<void> refreshEmployees(String enterpriseId) async {
    _employees = await _userRepo.getUsersByEnterprise(enterpriseId);
    _employees = _employees.where((u) => u.activeRole != 'admin').toList();
    notifyListeners();
  }

  // Initialize dashboard with all streams
  Future<void> initDashboard(String enterpriseId) async {
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
    _employees = await _userRepo.getUsersByEnterprise(enterpriseId);
    _employees = _employees.where((u) => u.activeRole != 'admin').toList();
    _streamTodaySummaries(enterpriseId);
    _streamPresence(enterpriseId);
    _streamLiveLocations(enterpriseId);
    _streamActiveStats(enterpriseId);
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
      }
    });
  }

  int _resolveLiveDurationSecs(Map<String, dynamic> stats) {
    final sessionStartTimeMs = (stats['sessionStartTimeMs'] as num?)?.toInt();
    if (sessionStartTimeMs != null) {
      final startedAt =
          DateTime.fromMillisecondsSinceEpoch(sessionStartTimeMs).toLocal();
      final elapsed = DateTime.now().difference(startedAt).inSeconds;
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
    _liveClockTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (_activeStatsData.isEmpty) {
        _liveClockTimer?.cancel();
        _liveClockTimer = null;
        return;
      }
      notifyListeners();
    });
  }

  // If both heartbeat (lastSeen) and live-location are older than this,
  // the service was likely killed without calling onDestroy.
  static const Duration _heartbeatStaleGrace = Duration(minutes: 35);

  // Get employee status from RTDB presence
  String getEmployeeStatus(String userId) {
    final rawPresenceStatus = _presenceData[userId]?['status'];
    final presenceStatus = rawPresenceStatus?.toString().toLowerCase();
    final liveLocation = _liveLocationData[userId];
    final updatedAt = liveLocation?['updatedAt'];
    final presenceLastSeen = _presenceData[userId]?['lastSeen'];

    if (presenceStatus == 'signal_lost' || presenceStatus == 'location_lost') {
      return 'signal_lost';
    }

    if (presenceStatus == 'break') {
      // If break but heartbeat is stale, the service was likely killed.
      if (!_isRecentTimestamp(presenceLastSeen, _heartbeatStaleGrace) &&
          !_isRecentTimestamp(updatedAt, _heartbeatStaleGrace)) {
        return 'signal_lost';
      }
      return 'break';
    }

    // A fresh live-location ping is the strongest signal that the user is
    // still active in the field, even if presence briefly got stuck.
    if (_isRecentTimestamp(updatedAt, _liveLocationActiveGrace)) {
      return 'active';
    }

    if (presenceStatus == 'active') {
      // Presence says active but location is stale. Check if the heartbeat
      // (lastSeen) is also stale — if so, the foreground service was likely
      // killed without calling onDestroy (common on OEM Android ROMs).
      if (!_isRecentTimestamp(presenceLastSeen, _heartbeatStaleGrace)) {
        return 'signal_lost';
      }
      return 'active';
    }

    return 'offline';
  }

  bool isEmployeeOnClock(String userId) {
    final status = getEmployeeStatus(userId);
    return status == 'active' || status == 'break' || status == 'signal_lost';
  }

  bool _isRecentTimestamp(dynamic value, Duration maxAge) {
    if (value is! num) return false;
    final timestamp = DateTime.fromMillisecondsSinceEpoch(value.toInt());
    return DateTime.now().difference(timestamp) <= maxAge;
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

    final distance = (summary?.totalDistance ?? 0.0) +
        ((stats?['distance'] as num?)?.toDouble() ?? 0.0);
    final sessionDuration = (summary?.totalDuration ?? 0) +
        (stats != null ? _resolveLiveDurationSecs(stats) : 0);
    final photosToday = (summary?.photosCount ?? 0) +
        ((stats?['photosToday'] as num?)?.toInt() ?? 0);
    final tasksToday = (summary?.tasksCompleted ?? 0) +
        ((stats?['tasksToday'] as num?)?.toInt() ?? 0);

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
    if (query.isEmpty) return _employees;
    final lowerQuery = query.toLowerCase();
    return _employees.where((e) {
      final location =
          _liveLocationData[e.id]?['address']?.toString().toLowerCase() ?? '';
      return e.name.toLowerCase().contains(lowerQuery) ||
          location.contains(lowerQuery);
    }).toList();
  }

  @override
  void dispose() {
    _summarySubscription?.cancel();
    _presenceSubscription?.cancel();
    _locationSubscription?.cancel();
    _statsSubscription?.cancel();
    _liveClockTimer?.cancel();
    super.dispose();
  }
}
