import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_activity_recognition/flutter_activity_recognition.dart'
    as ar;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/app_colors.dart';

import 'tracking_task_handler.dart';

class TrackingForegroundService {
  TrackingForegroundService._();

  static const String _notificationIconMetaData =
      'izumi_foreground_notification_icon';
  static const String _enterpriseIdKey = 'tracking.enterpriseId';
  static const String _employeeIdKey = 'tracking.employeeId';
  static const String _sessionIdKey = 'tracking.sessionId';
  static const String _startedAtKey = 'tracking.startedAtMs';
  static const String _employeeNameKey = 'tracking.employeeName';

  static const int _serviceId = 3207;
  static final Map<String, Completer<Map<String, dynamic>>> _commandRequests =
      <String, Completer<Map<String, dynamic>>>{};
  static bool _internalCallbackRegistered = false;

  static void initialize() {
    FlutterForegroundTask.initCommunicationPort();
    if (!_internalCallbackRegistered) {
      FlutterForegroundTask.addTaskDataCallback(_handleTaskData);
      _internalCallbackRegistered = true;
    }
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'izumi_tracking',
        channelName: 'Izumi Tracking',
        channelDescription:
            'Keeps field session tracking alive in the background.',
        channelImportance: NotificationChannelImportance.HIGH,
        priority: NotificationPriority.HIGH,
        onlyAlertOnce: true,
        enableVibration: false,
        playSound: false,
        showWhen: false,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(60000),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  static Future<void> ensureRuntimePermissions() async {
    final notificationPermission =
        await FlutterForegroundTask.checkNotificationPermission();
    if (notificationPermission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    ar.ActivityPermission activityPermission =
        await ar.FlutterActivityRecognition.instance.checkPermission();
    if (activityPermission == ar.ActivityPermission.DENIED) {
      activityPermission =
          await ar.FlutterActivityRecognition.instance.requestPermission();
    }

    if (activityPermission == ar.ActivityPermission.PERMANENTLY_DENIED) {
      throw Exception(
        'Activity recognition permission is permanently denied.',
      );
    }
  }

  static Future<void> startTracking({
    required String enterpriseId,
    required String employeeId,
    required String sessionId,
    String? employeeName,
    int? startTimeMs,
  }) async {
    await ensureRuntimePermissions();

    await FlutterForegroundTask.saveData(
      key: _enterpriseIdKey,
      value: enterpriseId,
    );
    await FlutterForegroundTask.saveData(
      key: _employeeIdKey,
      value: employeeId,
    );
    await FlutterForegroundTask.saveData(
      key: _sessionIdKey,
      value: sessionId,
    );
    await FlutterForegroundTask.saveData(
      key: _startedAtKey,
      value: startTimeMs ?? DateTime.now().millisecondsSinceEpoch,
    );
    if (employeeName != null) {
      await FlutterForegroundTask.saveData(
        key: _employeeNameKey,
        value: employeeName,
      );
    }

    // Mark tracking as active so the WorkManager watchdog knows there is a
    // session that should be running. Cleared in stopTracking().
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('izumi_tracking_active', true);
    } catch (_) {}

    final isRunning = await FlutterForegroundTask.isRunningService;
    if (isRunning) {
      // Service is already running — update context without restarting.
      // restartService() would fire onDestroy on the current handler, which
      // auto-ends the active session. Instead, just refresh the context.
      FlutterForegroundTask.sendDataToTask({
        'type': 'refresh_context',
        'enterpriseId': enterpriseId,
        'employeeId': employeeId,
        'sessionId': sessionId,
        'employeeName': employeeName,
      });
      return;
    }

    final result = await FlutterForegroundTask.startService(
      serviceId: _serviceId,
      serviceTypes: const [
        ForegroundServiceTypes.location,
        ForegroundServiceTypes.dataSync,
      ],
      notificationTitle: 'Izumi session active',
      notificationText: 'Optimizing GPS based on movement',
      notificationIcon: const NotificationIcon(
        metaDataName: _notificationIconMetaData,
        backgroundColor: AppColors.primary,
      ),
      callback: startTrackingCallback,
    );

    if (result is ServiceRequestFailure) {
      throw Exception(result.error);
    }
  }

  static Future<void> ensureTrackingRunning({
    required String enterpriseId,
    required String employeeId,
    required String sessionId,
    String? employeeName,
    int? startTimeMs,
  }) async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.saveData(
        key: _enterpriseIdKey,
        value: enterpriseId,
      );
      await FlutterForegroundTask.saveData(
        key: _employeeIdKey,
        value: employeeId,
      );
      await FlutterForegroundTask.saveData(
        key: _sessionIdKey,
        value: sessionId,
      );
      // Ensure _startedAtMs stays consistent with the Firestore session
      if (startTimeMs != null) {
        await FlutterForegroundTask.saveData(
          key: _startedAtKey,
          value: startTimeMs,
        );
      }
      if (employeeName != null) {
        await FlutterForegroundTask.saveData(
          key: _employeeNameKey,
          value: employeeName,
        );
      }
      FlutterForegroundTask.sendDataToTask({
        'type': 'refresh_context',
        'enterpriseId': enterpriseId,
        'employeeId': employeeId,
        'sessionId': sessionId,
        'employeeName': employeeName,
        'startTimeMs': startTimeMs,
      });
      return;
    }

    await startTracking(
      enterpriseId: enterpriseId,
      employeeId: employeeId,
      sessionId: sessionId,
      employeeName: employeeName,
      startTimeMs: startTimeMs,
    );
  }

  static const String _sessionStatusKey = 'tracking.sessionStatus';

  static Future<void> stopTracking({bool clearContext = false}) async {
    if (clearContext) {
      // Mark as 'ending' FIRST so onDestroy sees it and skips auto-end,
      // closing the race window where OEM kills service between
      // stopTracking() call and context being fully cleared.
      await FlutterForegroundTask.saveData(
        key: _sessionStatusKey,
        value: 'ending',
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await Future.wait([
        FlutterForegroundTask.removeData(key: _enterpriseIdKey),
        FlutterForegroundTask.removeData(key: _employeeIdKey),
        FlutterForegroundTask.removeData(key: _sessionIdKey),
        FlutterForegroundTask.removeData(key: _startedAtKey),
        FlutterForegroundTask.removeData(key: _sessionStatusKey),
      ]);

      // Clear the watchdog flag so the WorkManager worker no-ops when
      // there is no active session.
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('izumi_tracking_active');
      } catch (_) {}
    }

    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }

    // Force-clear any lingering foreground notification. On some OEM
    // devices (Samsung, Xiaomi) stopService does not immediately remove
    // the notification — cancel it explicitly to avoid showing stale
    // "Tracking active" after the session has ended.
    try {
      final flnp = FlutterLocalNotificationsPlugin();
      await flnp.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_izumi'),
          iOS: DarwinInitializationSettings(),
        ),
      );
      // Cancel the foreground service notification (serviceId used as notif id)
      await flnp.cancel(_serviceId);
    } catch (_) {
      // Best-effort; don't block session end if this fails
    }
  }

  static void addTaskDataCallback(void Function(Object data) callback) {
    FlutterForegroundTask.addTaskDataCallback(callback);
  }

  static void removeTaskDataCallback(void Function(Object data) callback) {
    FlutterForegroundTask.removeTaskDataCallback(callback);
  }

  static Future<void> requestImmediateHeartbeat() async {
    FlutterForegroundTask.sendDataToTask(const {'type': 'heartbeat'});
  }

  static Future<Map<String, dynamic>> flushNow() {
    return _sendCommandAndWait(command: 'flush_now');
  }

  static Future<Map<String, dynamic>> finalFlush() {
    return _sendCommandAndWait(command: 'final_flush');
  }

  static Future<void> requestLocationSnapshot() async {
    FlutterForegroundTask.sendDataToTask(const {'type': 'poll_now'});
  }

  static Future<void> updateForegroundNotification({
    required String title,
    required String text,
  }) async {
    try {
      await FlutterForegroundTask.updateService(
        notificationTitle: title,
        notificationText: text,
        notificationIcon: const NotificationIcon(
          metaDataName: _notificationIconMetaData,
          backgroundColor: AppColors.primary,
        ),
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[TrackingForegroundService] update notification failed: $error\n$stackTrace',
      );
    }
  }

  static Future<Map<String, dynamic>> _sendCommandAndWait({
    required String command,
  }) async {
    if (!await FlutterForegroundTask.isRunningService) {
      return {
        'flushed': false,
        'command': command,
        'error': 'Tracking service is not running.',
      };
    }

    final requestId = _nextRequestId();
    final completer = Completer<Map<String, dynamic>>();
    _commandRequests[requestId] = completer;

    FlutterForegroundTask.sendDataToTask({
      'type': command,
      'requestId': requestId,
    });

    try {
      return await completer.future.timeout(const Duration(seconds: 25));
    } on TimeoutException {
      _commandRequests.remove(requestId);
      return {
        'flushed': false,
        'command': command,
        'requestId': requestId,
        'error': 'Timed out waiting for $command.',
      };
    }
  }

  static void _handleTaskData(Object data) {
    if (data is! Map) {
      return;
    }

    if (data['type'] != 'command_result') {
      return;
    }

    final requestId = data['requestId']?.toString();
    if (requestId == null) {
      return;
    }

    final completer = _commandRequests.remove(requestId);
    if (completer != null && !completer.isCompleted) {
      completer.complete(Map<String, dynamic>.from(data));
    }
  }

  static String _nextRequestId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final random = Random().nextInt(1 << 20);
    return '$now-$random';
  }
}
