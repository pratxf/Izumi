import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Session lifecycle guard for the Android "intentional background" flag.
///
/// Previously also started/stopped a native `SessionTaskRemovalService` that
/// auto-ended sessions when the user swiped the app from recents. That
/// service has been removed — auto-end on swipe is no longer desired.
///
/// [start] and [stop] are retained as no-ops so existing call sites compile
/// unchanged. [setIntentionalBackground] is the only live behaviour: it
/// writes a flag that [SessionTrackingTaskHandler.onDestroy] reads to decide
/// whether an OEM-triggered service death should auto-end the session.
class SessionTaskGuard {
  SessionTaskGuard._();

  /// Retained for API compatibility. No longer starts any native service.
  static Future<void> start({
    required String enterpriseId,
    required String employeeId,
    required String sessionId,
  }) async {
    // No-op: the former SessionTaskRemovalService has been removed.
  }

  /// Retained for API compatibility. No longer stops any native service.
  static Future<void> stop() async {
    // No-op: the former SessionTaskRemovalService has been removed.
  }

  /// Signal that the user intentionally backgrounded the app (via back button
  /// with an active session). Read by [SessionTrackingTaskHandler.onDestroy]
  /// so it can skip auto-end when the foreground service is later killed by
  /// the OEM after the user backgrounded the app.
  ///
  /// Stored in Flutter's [SharedPreferences] so the same backing store is
  /// used by writer (here) and reader (the foreground service task handler).
  static Future<void> setIntentionalBackground(bool value) async {
    if (!Platform.isAndroid) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value) {
        await prefs.setBool('intentional_background', true);
      } else {
        await prefs.remove('intentional_background');
      }
    } catch (error, stackTrace) {
      debugPrint(
        '[SessionTaskGuard] setIntentionalBackground failed: $error\n$stackTrace',
      );
    }
  }
}
