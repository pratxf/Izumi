import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../models/task_model.dart';
import '../models/upload_status.dart';
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
  final Map<String, UploadStatus> _taskUploadStatuses = {};

  List<TaskModel> get allTasks => _allTasks;
  List<TaskModel> get activeTasks => _filteredActive;
  List<TaskModel> get completedTasks => _filteredCompleted;
  String get filterType => _filterType;
  bool get isLoading => _isLoading;
  String? get error => _error;

  int get pendingCount => _activeTasks.length;
  int get completedCount => _completedTasks.length;

  UploadStatus taskUploadStatus(String taskId) {
    return _taskUploadStatuses[taskId] ?? UploadStatus.success;
  }

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
    _isLoading = true;
    notifyListeners();
    _tasksSubscription?.cancel();
    _tasksSubscription = _taskRepo.streamTasksByEmployee(employeeId).listen(
      (tasks) {
        debugPrint(
            '[TaskProvider] streamTasks received ${tasks.length} tasks for $employeeId');
        _allTasks = tasks;
        _splitTasks();
        _isLoading = false;
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
    _isLoading = true;
    notifyListeners();
    _tasksSubscription?.cancel();
    _tasksSubscription = _taskRepo.streamTasksByEnterprise(enterpriseId).listen(
      (tasks) {
        _allTasks = tasks;
        _splitTasks();
        _isLoading = false;
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
    final taskIndex = _activeTasks.indexWhere((t) => t.id == taskId);
    if (taskIndex == -1) {
      return false;
    }

    final originalTask = _activeTasks[taskIndex];
    final optimisticTask = originalTask.copyWith(
      status: 'completed',
      completedAt: DateTime.now(),
      uploadStatus: UploadStatus.pending,
    );

    _taskUploadStatuses[taskId] = UploadStatus.pending;
    _activeTasks.removeAt(taskIndex);
    _completedTasks.insert(0, optimisticTask);
    notifyListeners();

    unawaited(_completeTaskInBackground(taskId, originalTask));
    return true;
  }

  Future<void> _completeTaskInBackground(
    String taskId,
    TaskModel originalTask,
  ) async {
    try {
      await _taskRepo.completeTask(taskId);
      _taskUploadStatuses[taskId] = UploadStatus.success;
      _replaceCompletedTaskStatus(taskId, UploadStatus.success);

      // Write task_completed activity log directly from the client.
      // The Cloud Function also writes one — duplicates are deduplicated
      // by the feed service using document ID.
      final now = DateTime.now();
      unawaited(
        FirebaseFirestore.instance
            .collection('activityLogs')
            .doc('task_completed_$taskId')
            .set({
          'enterpriseId': originalTask.enterpriseId,
          'employeeId': originalTask.assignedTo,
          'orgId': originalTask.enterpriseId,
          'type': 'task_completed',
          'title': 'Task Completed',
          'detail': originalTask.title,
          'timestamp': Timestamp.fromDate(now),
          'date': DateFormat('yyyy-MM-dd').format(now),
          'payload': {
            'taskId': taskId,
            'title': originalTask.title,
            'completedAt': Timestamp.fromDate(now),
          },
          'metadata': {
            'taskId': taskId,
            'taskType': originalTask.type,
            'priority': originalTask.priority,
            'assignedBy': originalTask.assignedBy,
            'source': 'client_direct',
          },
        }, SetOptions(merge: true)).catchError((e) {
          debugPrint('[TaskProvider] task_completed activity log failed: $e');
        }),
      );
    } catch (e) {
      _error = e.toString();
      _taskUploadStatuses[taskId] = UploadStatus.error;
      _restoreFailedTaskCompletion(taskId, originalTask);
    }
    notifyListeners();
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

  // Delete a task
  Future<bool> deleteTask(String taskId) async {
    try {
      await _taskRepo.deleteTask(taskId);
      _allTasks.removeWhere((t) => t.id == taskId);
      _splitTasks();
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      debugPrint('[TaskProvider] deleteTask error: $e');
      notifyListeners();
      return false;
    }
  }

  // Set filter type
  void setFilterType(String type) {
    _filterType = type;
    notifyListeners();
  }

  void _splitTasks() {
    final pendingStatuses = Map<String, UploadStatus>.from(_taskUploadStatuses);
    _activeTasks = _allTasks.where((t) => t.isPending).toList();
    _completedTasks = _allTasks
        .where((t) => t.isCompleted)
        .map((task) => task.copyWith(
              uploadStatus: pendingStatuses[task.id] ?? UploadStatus.success,
            ))
        .toList();
    // Clean up statuses for tasks that are done uploading AND for stale
    // entries whose task IDs no longer exist in the current task list.
    final allTaskIds = _allTasks.map((t) => t.id).toSet();
    _taskUploadStatuses.removeWhere(
      (taskId, status) =>
          !allTaskIds.contains(taskId) ||
          (status == UploadStatus.success &&
              _completedTasks.any((task) => task.id == taskId)),
    );
  }

  void _replaceCompletedTaskStatus(String taskId, UploadStatus status) {
    _completedTasks = _completedTasks.map((task) {
      if (task.id == taskId) {
        return task.copyWith(uploadStatus: status);
      }
      return task;
    }).toList();
  }

  void _restoreFailedTaskCompletion(String taskId, TaskModel originalTask) {
    _completedTasks.removeWhere((task) => task.id == taskId);
    if (_activeTasks.every((task) => task.id != taskId)) {
      _activeTasks.insert(
        0,
        originalTask.copyWith(uploadStatus: UploadStatus.error),
      );
    }
  }

  @override
  void dispose() {
    _tasksSubscription?.cancel();
    super.dispose();
  }
}
