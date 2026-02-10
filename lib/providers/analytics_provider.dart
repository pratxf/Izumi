import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/daily_summary_model.dart';
import '../models/activity_log_model.dart';
import '../models/user_model.dart';
import '../repositories/daily_summary_repository.dart';
import '../repositories/activity_log_repository.dart';
import '../repositories/user_repository.dart';

class AnalyticsProvider extends ChangeNotifier {
  final DailySummaryRepository _summaryRepo = DailySummaryRepository();
  final ActivityLogRepository _logRepo = ActivityLogRepository();
  final UserRepository _userRepo = UserRepository();

  String _selectedPeriod = 'Today';
  List<UserModel> _employees = [];
  Map<String, List<DailySummaryModel>> _employeeSummaries = {};
  final Map<String, List<ActivityLogModel>> _employeeLogs = {};
  bool _isLoading = false;
  String? _error;

  // Aggregate stats
  int _totalHours = 0;
  double _totalDistance = 0.0;
  int _totalPhotos = 0;
  int _totalTasks = 0;

  String get selectedPeriod => _selectedPeriod;
  List<UserModel> get employees => _employees;
  Map<String, List<DailySummaryModel>> get employeeSummaries =>
      _employeeSummaries;
  Map<String, List<ActivityLogModel>> get employeeLogs => _employeeLogs;
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get totalHours => _totalHours;
  double get totalDistance => _totalDistance;
  int get totalPhotos => _totalPhotos;
  int get totalTasks => _totalTasks;

  Future<void> loadAnalytics(String enterpriseId, {String? period}) async {
    if (period != null) _selectedPeriod = period;
    _isLoading = true;
    notifyListeners();

    try {
      // Load employees
      _employees = await _userRepo.getUsersByEnterprise(enterpriseId);
      _employees = _employees.where((u) => u.activeRole != 'admin').toList();

      // Determine date range based on period
      final now = DateTime.now();
      DateTime startDate;
      DateTime endDate = now;

      switch (_selectedPeriod) {
        case 'Today':
          startDate = DateTime(now.year, now.month, now.day);
          break;
        case 'This Week':
          startDate = now.subtract(Duration(days: now.weekday - 1));
          startDate =
              DateTime(startDate.year, startDate.month, startDate.day);
          break;
        case 'This Month':
          startDate = DateTime(now.year, now.month, 1);
          break;
        default:
          startDate = DateTime(now.year, now.month, now.day);
      }

      // Load summaries for each employee
      _employeeSummaries = {};
      _totalHours = 0;
      _totalDistance = 0.0;
      _totalPhotos = 0;
      _totalTasks = 0;

      for (final employee in _employees) {
        final summaries = await _summaryRepo.getDailySummaries(
          employee.id,
          startDate: startDate,
          endDate: endDate,
        );
        _employeeSummaries[employee.id] = summaries;

        // Aggregate
        for (final s in summaries) {
          _totalHours += s.hours;
          _totalDistance += s.totalDistance;
          _totalPhotos += s.photosCount;
          _totalTasks += s.tasksCompleted;
        }

        // Load activity logs
        final logs = await _logRepo.getLogsByEmployee(
          employee.id,
          limit: 20,
        );
        _employeeLogs[employee.id] = logs;
      }
    } catch (e) {
      _error = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  void setPeriod(String period) {
    _selectedPeriod = period;
    notifyListeners();
  }

  // Get aggregated stats for a specific employee
  Map<String, dynamic> getEmployeeStats(String employeeId) {
    final summaries = _employeeSummaries[employeeId] ?? [];
    int hours = 0;
    double distance = 0.0;
    int photos = 0;
    int tasks = 0;

    for (final s in summaries) {
      hours += s.hours;
      distance += s.totalDistance;
      photos += s.photosCount;
      tasks += s.tasksCompleted;
    }

    return {
      'hours': hours,
      'distance': distance,
      'photos': photos,
      'tasks': tasks,
    };
  }

  // Get activity logs for an employee
  List<ActivityLogModel> getLogsForEmployee(String employeeId) {
    return _employeeLogs[employeeId] ?? [];
  }
}
