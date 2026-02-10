import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import '../models/group_model.dart';
import '../repositories/group_repository.dart';

class GroupProvider extends ChangeNotifier {
  final GroupRepository _groupRepo = GroupRepository();

  List<GroupModel> _groups = [];
  bool _isLoading = false;
  String? _error;
  StreamSubscription? _groupsSubscription;

  List<GroupModel> get groups => _groups;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // Load groups for enterprise
  Future<void> loadGroups(String enterpriseId) async {
    _isLoading = true;
    notifyListeners();

    try {
      _groups = await _groupRepo.getGroupsByEnterprise(enterpriseId);
    } catch (e) {
      _error = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  // Stream groups for live updates
  void streamGroups(String enterpriseId) {
    _groupsSubscription?.cancel();
    _groupsSubscription =
        _groupRepo.streamGroupsByEnterprise(enterpriseId).listen(
      (groups) {
        _groups = groups;
        notifyListeners();
      },
      onError: (e) {
        debugPrint('[GroupProvider] streamGroups error: $e');
        // Fallback to one-time fetch if stream fails
        loadGroups(enterpriseId);
      },
    );
  }

  // Create a new group
  Future<String?> createGroup(GroupModel group) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final groupId = await _groupRepo.createGroup(group);
      _isLoading = false;
      notifyListeners();
      return groupId;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  // Update a group
  Future<bool> updateGroup(String groupId, Map<String, dynamic> data) async {
    try {
      await _groupRepo.updateGroup(groupId, data);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  // Delete a group
  Future<bool> deleteGroup(String groupId) async {
    try {
      await _groupRepo.deleteGroup(groupId);
      _groups.removeWhere((g) => g.id == groupId);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  // Add member to group
  Future<bool> addMember(String groupId, String userId) async {
    try {
      await _groupRepo.addMember(groupId, userId);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  // Remove member from group
  Future<bool> removeMember(String groupId, String userId) async {
    try {
      await _groupRepo.removeMember(groupId, userId);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  GroupModel? getGroupById(String groupId) {
    try {
      return _groups.firstWhere((g) => g.id == groupId);
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _groupsSubscription?.cancel();
    super.dispose();
  }
}
