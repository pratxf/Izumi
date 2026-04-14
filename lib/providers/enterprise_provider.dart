import 'package:flutter/foundation.dart';

import '../models/user_model.dart';
import '../repositories/user_repository.dart';

/// Single source of truth for enterprise-scoped reference data.
///
/// Holds the employee list and a pre-built migration chain index so that
/// [resolveLinkedIds] is an O(1) lookup. Must be loaded before the app shell
/// renders — [main.dart]'s splash gate waits for [isReady].
///
/// All other providers (Dashboard, Analytics, Team) and every screen that
/// needs enterprise employees should read from this provider instead of
/// fetching the list independently.
class EnterpriseProvider extends ChangeNotifier {
  final UserRepository _userRepo = UserRepository();

  List<UserModel> _users = const [];
  List<UserModel> _employees = const [];
  Map<String, List<String>> _linkedIdsIndex = const {};
  String? _enterpriseId;
  bool _isReady = false;
  Object? _error;

  /// All users for the current enterprise — includes admins.
  /// Consumers that only want field employees should use [employees] instead.
  List<UserModel> get users => _users;

  /// All non-admin employees for the current enterprise.
  List<UserModel> get employees => _employees;

  /// True once the initial load has completed (successfully or not).
  bool get isReady => _isReady;

  /// The enterprise ID this provider is loaded for, or null if not loaded.
  String? get enterpriseId => _enterpriseId;

  /// Any error from the most recent load attempt.
  Object? get error => _error;

  /// Load employees for [enterpriseId]. Awaitable — callers that need
  /// guaranteed-populated data should await this.
  ///
  /// Idempotent: if already loaded for this enterprise, returns immediately.
  /// If called with a different enterprise, reloads.
  Future<void> load(String enterpriseId) async {
    if (_isReady && _enterpriseId == enterpriseId) return;

    _enterpriseId = enterpriseId;
    _error = null;

    try {
      final fetched = await _userRepo.getUsersByEnterprise(enterpriseId);
      _users = fetched;
      _employees = fetched.where((u) => u.activeRole != 'admin').toList();
      _linkedIdsIndex = _buildLinkedIdsIndex(_employees);
      _isReady = true;
      notifyListeners();
    } catch (e, stackTrace) {
      debugPrint('[EnterpriseProvider] load failed: $e\n$stackTrace');
      _error = e;
      // Mark ready so the splash doesn't hang forever on a transient failure.
      // Screens will render with an empty list; a subsequent refresh can retry.
      _isReady = true;
      notifyListeners();
      rethrow;
    }
  }

  /// Force-refresh the employee list (e.g. after adding/removing a user).
  /// Does not toggle [isReady] back to false — the app stays usable.
  Future<void> refresh() async {
    final eid = _enterpriseId;
    if (eid == null) return;
    try {
      final fetched = await _userRepo.getUsersByEnterprise(eid);
      _users = fetched;
      _employees = fetched.where((u) => u.activeRole != 'admin').toList();
      _linkedIdsIndex = _buildLinkedIdsIndex(_employees);
      notifyListeners();
    } catch (e) {
      debugPrint('[EnterpriseProvider] refresh failed: $e');
    }
  }

  /// Resolve all IDs linked to [employeeId] via migration chains.
  /// O(1) map lookup. Returns [employeeId] itself if no links are known.
  ///
  /// [additionalIds] are merged into the result (deduplicated) and also
  /// have their own migration chains resolved. This covers cases where a
  /// caller passes in pre-computed links it wants to preserve.
  List<String> resolveLinkedIds(
    String employeeId, {
    Iterable<String> additionalIds = const [],
  }) {
    final result = <String>{};
    void expand(String id) {
      if (id.trim().isEmpty) return;
      result.add(id);
      final linked = _linkedIdsIndex[id];
      if (linked != null) result.addAll(linked);
    }

    expand(employeeId);
    for (final id in additionalIds) {
      expand(id);
    }

    return result.isEmpty ? [employeeId] : result.toList();
  }

  /// Find a user by ID (current or migrated). Searches the full user list
  /// including admins. Returns null if not found.
  UserModel? findById(String id) {
    for (final user in _users) {
      if (user.id == id) return user;
      if (user.migratedFrom == id) return user;
    }
    return null;
  }

  /// Reset state (called on logout).
  void clear() {
    _users = const [];
    _employees = const [];
    _linkedIdsIndex = const {};
    _enterpriseId = null;
    _isReady = false;
    _error = null;
    notifyListeners();
  }

  /// Build an index mapping every known ID (current + migratedFrom +
  /// migratedFromChain entries) to the full set of IDs linked to it.
  /// For an employee with UID `u`, [migratedFrom] = `old1`, and
  /// [migratedFromChain] = `[old2, old3]`, all four IDs map to the full
  /// set {u, old1, old2, old3}.
  static Map<String, List<String>> _buildLinkedIdsIndex(
    List<UserModel> employees,
  ) {
    final index = <String, Set<String>>{};

    for (final employee in employees) {
      final ids = <String>{employee.id};
      final migratedFrom = employee.migratedFrom?.trim();
      if (migratedFrom != null && migratedFrom.isNotEmpty) {
        ids.add(migratedFrom);
      }
      // Support multiple migration hops (employee had multiple historical UIDs)
      final chain = employee.migratedFromChain;
      if (chain != null) {
        for (final id in chain) {
          final trimmed = id.trim();
          if (trimmed.isNotEmpty) ids.add(trimmed);
        }
      }

      for (final id in ids) {
        index.putIfAbsent(id, () => <String>{}).addAll(ids);
      }
    }

    return index.map((key, value) => MapEntry(key, value.toList()));
  }
}
