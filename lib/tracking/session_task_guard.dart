import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Thin Dart wrapper around the native [SessionTaskRemovalService].
///
/// When [start] is called, Android's `SessionTaskRemovalService` is bound to
/// the current task. If the user swipes the app out of the recent-apps list,
/// `onTaskRemoved` fires and the service auto-ends the active Firestore session
/// without needing the Flutter engine to be alive.
///
/// Must be stopped via [stop] when the session ends normally, so the service
/// does not fire a spurious auto-end after the user deliberately ends a session.
class SessionTaskGuard {
  SessionTaskGuard._();

  static const _channel = MethodChannel('izumi/app_lifecycle');

  /// Start the guard for [sessionId] / [employeeId] / [enterpriseId].
  ///
  /// Safe to call on non-Android platforms — does nothing.
  static Future<void> start({
    required String enterpriseId,
    required String employeeId,
    required String sessionId,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('startSessionTaskGuard', {
        'enterpriseId': enterpriseId,
        'userId': employeeId,
        'sessionId': sessionId,
      });
    } catch (error, stackTrace) {
      debugPrint(
        '[SessionTaskGuard] start failed: $error\n$stackTrace',
      );
    }
  }

  /// Stop the guard (call this after a normal session end).
  ///
  /// Safe to call on non-Android platforms — does nothing.
  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('stopSessionTaskGuard');
    } catch (error, stackTrace) {
      debugPrint(
        '[SessionTaskGuard] stop failed: $error\n$stackTrace',
      );
    }
  }
}
