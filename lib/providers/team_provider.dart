import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_model.dart';
import '../models/group_model.dart';
import '../models/task_model.dart';
import '../repositories/group_repository.dart';
import '../repositories/user_repository.dart';
import '../repositories/task_repository.dart';

class TeamProvider extends ChangeNotifier {
  final GroupRepository _groupRepo = GroupRepository();
  final UserRepository _userRepo = UserRepository();
  final TaskRepository _taskRepo = TaskRepository();

  GroupModel? _group;
  List<UserModel> _teamMembers = [];
  List<TaskModel> _teamTasks = [];
  bool _isLoading = false;
  String? _error;

  StreamSubscription? _tasksSubscription;

  GroupModel? get group => _group;
  List<UserModel> get teamMembers => _teamMembers;
  List<TaskModel> get teamTasks => _teamTasks;
  bool get isLoading => _isLoading;
  String? get error => _error;

  int get activeMemberCount => _teamMembers.length;
  int get totalTasks => _teamTasks.length;
  int get pendingTasks => _teamTasks.where((t) => t.isPending).length;
  int get completedTasks => _teamTasks.where((t) => t.isCompleted).length;

  /// Initialize team data for a team lead
  Future<void> initTeam(String enterpriseId, String leadId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _loadTeamData(enterpriseId, leadId);
    } catch (e) {
      // Query may fail if token claims aren't ready — refresh and retry once
      debugPrint('[TeamProvider] First load failed: $e — retrying with token refresh');
      try {
        await FirebaseAuth.instance.currentUser?.getIdToken(true);
        await _loadTeamData(enterpriseId, leadId);
      } catch (retryError) {
        _error = retryError.toString();
        debugPrint('[TeamProvider] Retry also failed: $retryError');
      }
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> _loadTeamData(String enterpriseId, String leadId) async {
    final groups = await _groupRepo.getGroupsByEnterprise(enterpriseId);
    _group = groups.where((g) => g.leadIds.contains(leadId)).firstOrNull;

    if (_group != null) {
      final allUsers = await _userRepo.getUsersByEnterprise(enterpriseId);
      _teamMembers = allUsers
          .where((u) => _group!.memberIds.contains(u.id))
          .toList();
      _streamTeamTasks(enterpriseId);
    }
  }

  void _streamTeamTasks(String enterpriseId) {
    _tasksSubscription?.cancel();
    _tasksSubscription = _taskRepo
        .streamTasksByEnterprise(enterpriseId)
        .listen((tasks) {
      if (_group != null) {
        // Filter tasks to only those assigned to team members
        final memberIds = _group!.memberIds.toSet();
        _teamTasks = tasks.where((t) => memberIds.contains(t.assignedTo)).toList();
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _tasksSubscription?.cancel();
    super.dispose();
  }
}
