import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../offline_queue/offline_queue_manager.dart';
import 'realtime_db_service.dart';

class ConnectivityMonitor {
  ConnectivityMonitor._();

  static final ConnectivityMonitor instance = ConnectivityMonitor._();

  final _connectivity = Connectivity();
  final _rtdb = RealtimeDbService();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  final _onlineController = StreamController<bool>.broadcast();
  bool _isOnline = true;
  bool _initialized = false;

  // Identity for connectivity writes to RTDB. Set by [bindUser] when a session
  // is active so the server-side sweep can distinguish "no network" from
  // "app dead". Cleared by [unbindUser] on session end / sign-out.
  String? _enterpriseId;
  String? _userId;

  /// Whether the device currently has network connectivity.
  bool get isOnline => _isOnline;

  /// Stream that emits whenever online/offline state changes.
  Stream<bool> get onlineStream => _onlineController.stream;

  Future<void> start() async {
    if (_initialized) return;
    _initialized = true;

    final results = await _connectivity.checkConnectivity();
    _isOnline = _hasNetwork(results);

    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      final wasOnline = _isOnline;
      _isOnline = _hasNetwork(results);

      if (!_onlineController.isClosed) {
        _onlineController.add(_isOnline);
      }

      // Best-effort write of the new state to RTDB. When transitioning to
      // offline this will fail (no network) — that's fine; the last
      // successfully-written "online" state is enough for the sweep.
      _writeConnectivityState(_isOnline);

      if (!wasOnline && _isOnline) {
        debugPrint('[ConnectivityMonitor] Back online — draining queue');
        unawaited(
          OfflineQueueManager.instance
              .processQueue(reason: 'connectivity_restored'),
        );
      }
    });
  }

  /// Bind a user context so connectivity transitions are recorded under that
  /// presence node. Call on session start and after sign-in.
  void bindUser({required String enterpriseId, required String userId}) {
    _enterpriseId = enterpriseId;
    _userId = userId;
    _writeConnectivityState(_isOnline);
  }

  /// Clear user context. Call on session end / sign-out so connectivity
  /// changes don't write to a stale presence node.
  void unbindUser() {
    _enterpriseId = null;
    _userId = null;
  }

  void _writeConnectivityState(bool isOnline) {
    final eid = _enterpriseId;
    final uid = _userId;
    if (eid == null || uid == null) return;
    unawaited(
      _rtdb
          .recordConnectivityChange(
        enterpriseId: eid,
        userId: uid,
        isOnline: isOnline,
      )
          .catchError((e) {
        debugPrint('[ConnectivityMonitor] connectivity write failed: $e');
      }),
    );
  }

  /// Mark a transient failure so the queue pauses until the next successful
  /// write or connectivity event.
  void markTransientFailure() {
    // We do not flip _isOnline to false here — connectivity_plus still
    // reports online. Instead, the queue manager's own backoff handles it.
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _onlineController.close();
    _initialized = false;
  }

  bool _hasNetwork(List<ConnectivityResult> results) {
    return results.any((r) => r != ConnectivityResult.none);
  }
}
