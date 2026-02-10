import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/user_model.dart';
import '../repositories/user_repository.dart';
import '../services/realtime_db_service.dart';

class DashboardProvider extends ChangeNotifier {
  final UserRepository _userRepo = UserRepository();
  final RealtimeDbService _rtdb = RealtimeDbService();

  List<UserModel> _employees = [];
  Map<String, Map<String, dynamic>> _presenceData = {};
  Map<String, Map<String, dynamic>> _liveLocationData = {};
  Map<String, Map<String, dynamic>> _activeStatsData = {};
  bool _isLoading = false;
  String? _error;

  StreamSubscription? _usersSubscription;
  StreamSubscription<DatabaseEvent>? _presenceSubscription;
  StreamSubscription<DatabaseEvent>? _locationSubscription;
  StreamSubscription<DatabaseEvent>? _statsSubscription;

  List<UserModel> get employees => _employees;
  Map<String, Map<String, dynamic>> get presenceData => _presenceData;
  Map<String, Map<String, dynamic>> get liveLocationData => _liveLocationData;
  Map<String, Map<String, dynamic>> get activeStatsData => _activeStatsData;
  bool get isLoading => _isLoading;
  String? get error => _error;

  int get activeCount =>
      _presenceData.values.where((p) => p['status'] == 'active').length;
  int get breakCount =>
      _presenceData.values.where((p) => p['status'] == 'break').length;
  int get offlineCount => _employees.length - activeCount - breakCount;

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
      debugPrint('[DashboardProvider] First load failed: $e — retrying with token refresh');
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
    _streamPresence(enterpriseId);
    _streamLiveLocations(enterpriseId);
    _streamActiveStats(enterpriseId);
  }

  void _streamPresence(String enterpriseId) {
    _presenceSubscription?.cancel();
    _presenceSubscription =
        _rtdb.streamPresence(enterpriseId).listen((event) {
      final data = event.snapshot.value;
      if (data is Map) {
        _presenceData = {};
        data.forEach((key, value) {
          if (value is Map) {
            _presenceData[key.toString()] =
                Map<String, dynamic>.from(value);
          }
        });
        notifyListeners();
      }
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
    _statsSubscription =
        _rtdb.streamActiveStats(enterpriseId).listen((event) {
      final data = event.snapshot.value;
      if (data is Map) {
        _activeStatsData = {};
        data.forEach((key, value) {
          if (value is Map) {
            _activeStatsData[key.toString()] =
                Map<String, dynamic>.from(value);
          }
        });
        notifyListeners();
      }
    });
  }

  // Get employee status from RTDB presence
  String getEmployeeStatus(String userId) {
    return _presenceData[userId]?['status'] as String? ?? 'offline';
  }

  // Get employee live location
  Map<String, dynamic>? getEmployeeLocation(String userId) {
    return _liveLocationData[userId];
  }

  // Get employee active stats
  Map<String, dynamic>? getEmployeeStats(String userId) {
    return _activeStatsData[userId];
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
    _usersSubscription?.cancel();
    _presenceSubscription?.cancel();
    _locationSubscription?.cancel();
    _statsSubscription?.cancel();
    super.dispose();
  }
}
