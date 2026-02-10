import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import '../models/task_model.dart';
import '../repositories/task_repository.dart';

class TaskProvider extends ChangeNotifier {
  final TaskRepository _taskRepo = TaskRepository();

  List<TaskModel> _allTasks = [];
  List<TaskModel> _activeTasks = [];
  List<TaskModel> _completedTasks = [];
  String _filterType = 'all'; // 'all' | 'task' | 'followup'
  bool _isLoading = false;
  String? _error;
  StreamSubscription? _tasksSubscription;

  // Track current stream context for reload after create
  String? _activeEnterpriseId;
  String? _activeEmployeeId;

  List<TaskModel> get allTasks => _allTasks;
  List<TaskModel> get activeTasks => _filteredActive;
  List<TaskModel> get completedTasks => _filteredCompleted;
  String get filterType => _filterType;
  bool get isLoading => _isLoading;
  String? get error => _error;

  int get pendingCount => _activeTasks.length;
  int get completedCount => _completedTasks.length;

  List<TaskModel> get _filteredActive {
    if (_filterType == 'all') return _activeTasks;
    return _activeTasks.where((t) => t.type == _filterType).toList();
  }

  List<TaskModel> get _filteredCompleted {
    if (_filterType == 'all') return _completedTasks;
    return _completedTasks.where((t) => t.type == _filterType).toList();
  }

  // Load tasks for an employee (one-time fetch)
  Future<void> loadTasks(String employeeId) async {
    _isLoading = true;
    notifyListeners();

    try {
      _allTasks = await _taskRepo.getTasksByEmployee(employeeId);
      _splitTasks();
    } catch (e) {
      _error = e.toString();
      debugPrint('[TaskProvider] loadTasks error: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  // Stream tasks for live updates (employee)
  void streamTasks(String employeeId) {
    debugPrint('[TaskProvider] streamTasks called for: $employeeId');
    _activeEmployeeId = employeeId;
    _activeEnterpriseId = null;
    _tasksSubscription?.cancel();
    _tasksSubscription =
        _taskRepo.streamTasksByEmployee(employeeId).listen(
      (tasks) {
        debugPrint('[TaskProvider] streamTasks received ${tasks.length} tasks for $employeeId');
        _allTasks = tasks;
        _splitTasks();
        notifyListeners();
      },
      onError: (e) {
        debugPrint('[TaskProvider] streamTasks error: $e');
        // Fallback to one-time fetch if stream fails (e.g. missing index)
        loadTasks(employeeId);
      },
    );
  }

  // Load tasks for enterprise (admin) - one-time fetch
  Future<void> loadEnterpriseTasks(String enterpriseId) async {
    _isLoading = true;
    notifyListeners();

    try {
      _allTasks = await _taskRepo.getTasksByEnterprise(enterpriseId);
      _splitTasks();
    } catch (e) {
      _error = e.toString();
      debugPrint('[TaskProvider] loadEnterpriseTasks error: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  // Stream tasks for enterprise (admin / team lead)
  void streamEnterpriseTasks(String enterpriseId) {
    _activeEnterpriseId = enterpriseId;
    _activeEmployeeId = null;
    _tasksSubscription?.cancel();
    _tasksSubscription =
        _taskRepo.streamTasksByEnterprise(enterpriseId).listen(
      (tasks) {
        _allTasks = tasks;
        _splitTasks();
        notifyListeners();
      },
      onError: (e) {
        debugPrint('[TaskProvider] streamEnterpriseTasks error: $e');
        // Fallback to one-time fetch if stream fails (e.g. missing index)
        loadEnterpriseTasks(enterpriseId);
      },
    );
  }

  // Create a new task
  Future<String?> createTask(TaskModel task) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final taskId = await _taskRepo.createTask(task);
      debugPrint('[TaskProvider] Task created: $taskId');

      // Force reload from Firestore to ensure UI has latest data
      if (_activeEnterpriseId != null) {
        _allTasks = await _taskRepo.getTasksByEnterprise(_activeEnterpriseId!);
      } else if (_activeEmployeeId != null) {
        _allTasks = await _taskRepo.getTasksByEmployee(_activeEmployeeId!);
      } else {
        // No active stream context - optimistically add to local list
        final newTask = task.copyWith(id: taskId);
        _allTasks.insert(0, newTask);
      }
      _splitTasks();

      _isLoading = false;
      notifyListeners();
      return taskId;
    } catch (e) {
      _error = e.toString();
      debugPrint('[TaskProvider] createTask error: $e');
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  // Complete a task
  Future<bool> completeTask(String taskId) async {
    try {
      await _taskRepo.completeTask(taskId);

      // Update local state
      final taskIndex = _activeTasks.indexWhere((t) => t.id == taskId);
      if (taskIndex != -1) {
        final task = _activeTasks[taskIndex].copyWith(
          status: 'completed',
          completedAt: DateTime.now(),
        );
        _activeTasks.removeAt(taskIndex);
        _completedTasks.insert(0, task);
        notifyListeners();
      }

      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  // Migrate orphaned tasks (one-time fix for ID mismatch)
  Future<Map<String, dynamic>?> migrateOrphanedTasks() async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-south1')
          .httpsCallable('migrateOrphanedTasks');
      final result = await callable.call();
      final data = Map<String, dynamic>.from(result.data as Map);
      debugPrint('[TaskProvider] migrateOrphanedTasks result: $data');

      // Reload tasks after migration
      if (_activeEnterpriseId != null) {
        _allTasks = await _taskRepo.getTasksByEnterprise(_activeEnterpriseId!);
        _splitTasks();
        notifyListeners();
      }

      return data;
    } catch (e) {
      debugPrint('[TaskProvider] migrateOrphanedTasks error: $e');
      return null;
    }
  }

  // Set filter type
  void setFilterType(String type) {
    _filterType = type;
    notifyListeners();
  }

  void _splitTasks() {
    _activeTasks = _allTasks.where((t) => t.isPending).toList();
    _completedTasks = _allTasks.where((t) => t.isCompleted).toList();
  }

  @override
  void dispose() {
    _tasksSubscription?.cancel();
    super.dispose();
  }
}
