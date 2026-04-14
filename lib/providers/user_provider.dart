import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../models/user_model.dart';
import 'enterprise_provider.dart';

/// Thin facade over [EnterpriseProvider].
///
/// Kept so existing screens (user_management, management, groups,
/// create_group, edit_group, create_chat_group, edit_chat_group) don't all
/// need migration at once. All data accessors delegate to the enterprise
/// provider — [UserProvider] owns no list of its own.
///
/// New code should depend on [EnterpriseProvider] directly.
class UserProvider extends ChangeNotifier {
  EnterpriseProvider? _enterprise;
  bool _isDeleting = false;
  String? _error;

  /// Attach the [EnterpriseProvider] that owns the user list. Called once
  /// during bootstrap in main.dart. Idempotent.
  void attachEnterprise(EnterpriseProvider enterprise) {
    if (identical(_enterprise, enterprise)) return;
    _enterprise?.removeListener(_onEnterpriseChanged);
    _enterprise = enterprise;
    _enterprise?.addListener(_onEnterpriseChanged);
  }

  void _onEnterpriseChanged() => notifyListeners();

  /// All users (includes admins). Backed by [EnterpriseProvider.users].
  List<UserModel> get users => _enterprise?.users ?? const [];

  /// Non-admin employees. Backed by [EnterpriseProvider.employees].
  List<UserModel> get employees => _enterprise?.employees ?? const [];

  /// Historically filtered by presence; now an alias for [users] since no
  /// caller filters on the dashboard side.
  List<UserModel> get activeUsers => users;

  bool get isLoading => !(_enterprise?.isReady ?? false) || _isDeleting;
  String? get error => _error ?? _enterprise?.error?.toString();

  /// Kept for API compatibility. Delegates to [EnterpriseProvider.refresh].
  Future<void> loadUsers(String _) async {
    await _enterprise?.refresh();
  }

  /// Kept for API compatibility. Delegates to [EnterpriseProvider.refresh].
  /// The original streaming behavior is no longer needed — data is
  /// pre-loaded by the splash-gated bootstrap.
  void streamUsers(String _) {
    unawaited(_enterprise?.refresh());
  }

  /// Delete a user via the backend Cloud Function, then refresh the
  /// enterprise directory so every consumer sees the updated list.
  Future<bool> deleteUser(String userId) async {
    _isDeleting = true;
    notifyListeners();
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-south1')
          .httpsCallable('deleteUser');
      await callable.call({'targetUserId': userId});
      await _enterprise?.refresh();
      _error = null;
      return true;
    } catch (e) {
      _error = e.toString();
      debugPrint('[UserProvider] deleteUser failed: $e');
      return false;
    } finally {
      _isDeleting = false;
      notifyListeners();
    }
  }

  UserModel? getUserById(String userId) {
    return _enterprise?.findById(userId);
  }

  List<UserModel> searchUsers(String query) {
    if (query.isEmpty) return users;
    final lowerQuery = query.toLowerCase();
    return users
        .where((u) =>
            u.name.toLowerCase().contains(lowerQuery) ||
            u.phone.contains(lowerQuery))
        .toList();
  }

  @override
  void dispose() {
    _enterprise?.removeListener(_onEnterpriseChanged);
    super.dispose();
  }
}
