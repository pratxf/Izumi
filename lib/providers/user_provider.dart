import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import '../repositories/user_repository.dart';

class UserProvider extends ChangeNotifier {
  final UserRepository _userRepo = UserRepository();

  List<UserModel> _users = [];
  bool _isLoading = false;
  String? _error;
  StreamSubscription? _usersSubscription;

  List<UserModel> get users => _users;
  List<UserModel> get employees =>
      _users.where((u) => u.activeRole != 'admin').toList();
  List<UserModel> get activeUsers => _users; // Filtered by presence in dashboard
  bool get isLoading => _isLoading;
  String? get error => _error;

  // Load users for enterprise
  Future<void> loadUsers(String enterpriseId) async {
    _isLoading = true;
    notifyListeners();

    try {
      _users = await _userRepo.getUsersByEnterprise(enterpriseId);
    } catch (e) {
      _error = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  // Stream users for live updates
  void streamUsers(String enterpriseId) {
    _usersSubscription?.cancel();
    _usersSubscription =
        _userRepo.streamUsersByEnterprise(enterpriseId).listen(
      (users) {
        _users = users;
        _error = null;
        notifyListeners();
      },
      onError: (e) {
        _error = e.toString();
        debugPrint('[UserProvider] Stream error: $e');
        notifyListeners();
      },
    );
  }

  Future<bool> deleteUser(String userId) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-south1')
          .httpsCallable('deleteUser');
      await callable.call({'targetUserId': userId});
      _users.removeWhere((u) => u.id == userId);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      debugPrint('[UserProvider] deleteUser failed: $e');
      notifyListeners();
      return false;
    }
  }

  UserModel? getUserById(String userId) {
    try {
      return _users.firstWhere((u) => u.id == userId);
    } catch (_) {
      return null;
    }
  }

  List<UserModel> searchUsers(String query) {
    if (query.isEmpty) return _users;
    final lowerQuery = query.toLowerCase();
    return _users
        .where((u) =>
            u.name.toLowerCase().contains(lowerQuery) ||
            u.phone.contains(lowerQuery))
        .toList();
  }

  @override
  void dispose() {
    _usersSubscription?.cancel();
    super.dispose();
  }
}
