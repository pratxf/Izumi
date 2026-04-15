import 'package:disable_battery_optimization/disable_battery_optimization.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:shared_preferences/shared_preferences.dart';

import 'device_config.dart';

class HealthResult {
  HealthResult({
    required this.locationAlways,
    required this.batteryOptimization,
    required this.notification,
    required this.autoStartConfirmed,
    required this.backgroundActivityConfirmed,
    required this.requiredChecks,
  });

  final bool locationAlways;
  final bool batteryOptimization;
  final bool notification;
  final bool autoStartConfirmed;
  final bool backgroundActivityConfirmed;
  final List<SetupCheck> requiredChecks;

  /// Whether each required check passed. Returns the failing checks.
  List<SetupCheck> get failures {
    final f = <SetupCheck>[];
    for (final c in requiredChecks) {
      switch (c) {
        case SetupCheck.locationAlways:
          if (!locationAlways) f.add(c);
          break;
        case SetupCheck.batteryOptimization:
          if (!batteryOptimization) f.add(c);
          break;
        case SetupCheck.notificationPermission:
          if (!notification) f.add(c);
          break;
        case SetupCheck.autoStart:
          if (!autoStartConfirmed) f.add(c);
          break;
        case SetupCheck.backgroundActivity:
          if (!backgroundActivityConfirmed) f.add(c);
          break;
      }
    }
    return f;
  }

  /// Strict failures — the kind that hard-block session start because the
  /// service literally cannot run without them.
  List<SetupCheck> get blockingFailures => failures
      .where((c) =>
          c == SetupCheck.locationAlways ||
          c == SetupCheck.batteryOptimization ||
          c == SetupCheck.notificationPermission)
      .toList();

  bool get allPassed => failures.isEmpty;
  bool get hasBlockingFailures => blockingFailures.isNotEmpty;
}

class DeviceHealthMonitor {
  DeviceHealthMonitor._();

  static const _autoStartKey = 'device_setup.autostart_confirmed';
  static const _backgroundKey = 'device_setup.background_confirmed';
  static const _autoStartTsKey = 'device_setup.autostart_confirmed_at_ms';
  static const _backgroundTsKey = 'device_setup.background_confirmed_at_ms';

  static Future<bool> _readFlag(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(key) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setAutoStartConfirmed(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoStartKey, value);
    await prefs.setInt(_autoStartTsKey, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<void> setBackgroundActivityConfirmed(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_backgroundKey, value);
    await prefs.setInt(_backgroundTsKey, DateTime.now().millisecondsSinceEpoch);
  }

  /// Run all required checks for the current device. Result includes which
  /// checks are required so the wizard can render the right step list.
  static Future<HealthResult> runAllChecks() async {
    final profile = await DeviceConfig.profile;

    final locationAlwaysStatus = await ph.Permission.locationAlways.status;
    final notificationStatus = profile.androidSdk >= 33
        ? await ph.Permission.notification.status
        : ph.PermissionStatus.granted;

    bool batteryOptDisabled = true;
    try {
      final isIgnoring =
          await DisableBatteryOptimization.isBatteryOptimizationDisabled;
      batteryOptDisabled = isIgnoring ?? false;
    } catch (_) {
      batteryOptDisabled = false;
    }

    return HealthResult(
      locationAlways: locationAlwaysStatus.isGranted,
      batteryOptimization: batteryOptDisabled,
      notification: notificationStatus.isGranted,
      autoStartConfirmed: await _readFlag(_autoStartKey),
      backgroundActivityConfirmed: await _readFlag(_backgroundKey),
      requiredChecks: profile.requiredChecks,
    );
  }
}
