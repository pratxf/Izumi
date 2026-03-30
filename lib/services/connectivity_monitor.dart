import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../offline_queue/offline_queue_manager.dart';

class ConnectivityMonitor {
  ConnectivityMonitor._();

  static final ConnectivityMonitor instance = ConnectivityMonitor._();

  final _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  final _onlineController = StreamController<bool>.broadcast();
  bool _isOnline = true;
  bool _initialized = false;

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

      if (!wasOnline && _isOnline) {
        debugPrint('[ConnectivityMonitor] Back online — draining queue');
        unawaited(
          OfflineQueueManager.instance
              .processQueue(reason: 'connectivity_restored'),
        );
      }
    });
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
