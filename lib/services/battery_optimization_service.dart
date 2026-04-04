import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Handles OEM-specific battery optimization settings that go beyond
/// Android's standard "ignore battery optimizations" dialog.
///
/// Many OEMs (Xiaomi, Huawei, Samsung, OnePlus, Oppo, Vivo) have their
/// own battery management that kills background services even when the
/// standard exemption is granted. This service opens OEM-specific settings
/// pages so the user can whitelist Izumi.
class BatteryOptimizationService {
  BatteryOptimizationService._();

  static const _channel = MethodChannel('izumi/app_lifecycle');
  static const _prefsKey = 'oem_battery_prompt_shown';

  /// Whether we've already shown the OEM-specific prompt.
  static Future<bool> hasPromptedBefore() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKey) ?? false;
  }

  /// Mark that we've shown the OEM-specific prompt.
  static Future<void> markAsPrompted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, true);
  }

  /// Check if the app is already exempt from standard battery optimization.
  static Future<bool> isExempted() async {
    if (!Platform.isAndroid) return true;
    try {
      return (await _channel.invokeMethod<bool>(
            'isIgnoringBatteryOptimizations',
          )) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Launch OEM-specific battery settings for the current device manufacturer.
  /// Returns true if an OEM intent was launched, false if no OEM-specific
  /// action was needed (stock Android or unknown manufacturer).
  static Future<bool> openOemBatterySettings() async {
    if (!Platform.isAndroid) return false;
    try {
      final result = await _channel.invokeMethod<bool>(
        'openOemBatterySettings',
      );
      return result ?? false;
    } catch (e) {
      debugPrint('[BatteryOptimizationService] openOemBatterySettings failed: $e');
      return false;
    }
  }
}
