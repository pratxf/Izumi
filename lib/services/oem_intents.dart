import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

/// OEM-specific Android intents for opening the AutoStart and Background
/// Activity settings. These are best-effort: the activity name varies by OS
/// version. We try each candidate in order and fall back to
/// [openAppSettings] if none resolve.
class OemIntents {
  OemIntents._();

  static List<_IntentSpec> _autoStart(String brand) {
    switch (brand) {
      case 'xiaomi':
      case 'redmi':
      case 'poco':
        return [
          _IntentSpec(
            'com.miui.securitycenter',
            'com.miui.permcenter.autostart.AutoStartManagementActivity',
          ),
          _IntentSpec(
            'com.miui.securitycenter',
            'com.miui.permcenter.permissions.PermissionsEditorActivity',
          ),
        ];
      case 'oppo':
      case 'realme':
        return [
          _IntentSpec(
            'com.coloros.safecenter',
            'com.coloros.safecenter.permission.startup.StartupAppListActivity',
          ),
          _IntentSpec(
            'com.oppo.safe',
            'com.oppo.safe.permission.startup.StartupAppListActivity',
          ),
          _IntentSpec(
            'com.coloros.safecenter',
            'com.coloros.privacypermissionsentry.PermissionTopActivity',
          ),
        ];
      case 'oneplus':
        return [
          _IntentSpec(
            'com.oneplus.security',
            'com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity',
          ),
          ..._autoStart('oppo'),
        ];
      case 'vivo':
      case 'iqoo':
        return [
          _IntentSpec(
            'com.vivo.permissionmanager',
            'com.vivo.permissionmanager.activity.BgStartUpManagerActivity',
          ),
          _IntentSpec(
            'com.iqoo.secure',
            'com.iqoo.secure.ui.phoneoptimize.BgStartUpManager',
          ),
        ];
      case 'huawei':
      case 'honor':
        return [
          _IntentSpec(
            'com.huawei.systemmanager',
            'com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity',
          ),
          _IntentSpec(
            'com.huawei.systemmanager',
            'com.huawei.systemmanager.appcontrol.activity.StartupAppControlActivity',
          ),
        ];
      default:
        return const [];
    }
  }

  static List<_IntentSpec> _background(String brand) {
    switch (brand) {
      case 'xiaomi':
      case 'redmi':
      case 'poco':
        return [
          _IntentSpec(
            'com.miui.powerkeeper',
            'com.miui.powerkeeper.ui.HiddenAppsConfigActivity',
          ),
        ];
      case 'samsung':
        return [
          _IntentSpec(
            'com.samsung.android.lool',
            'com.samsung.android.sm.battery.ui.usage.CheckableRecyclerActivity',
          ),
          _IntentSpec(
            'com.samsung.android.lool',
            'com.samsung.android.sm.battery.ui.BatteryActivity',
          ),
        ];
      case 'oppo':
      case 'realme':
      case 'oneplus':
        return [
          _IntentSpec(
            'com.coloros.oppoguardelf',
            'com.coloros.powermanager.fuelgaue.PowerUsageModelActivity',
          ),
        ];
      case 'vivo':
      case 'iqoo':
        return [
          _IntentSpec(
            'com.vivo.abe',
            'com.vivo.applicationbehaviorengine.ui.ExcessivePowerManagerActivity',
          ),
        ];
      case 'huawei':
      case 'honor':
        return [
          _IntentSpec(
            'com.huawei.systemmanager',
            'com.huawei.systemmanager.power.ui.HwPowerManagerActivity',
          ),
        ];
      default:
        return const [];
    }
  }

  static Future<void> openAutoStart(String brand) async {
    await _tryOpen(_autoStart(brand));
  }

  static Future<void> openBackgroundActivity(String brand) async {
    await _tryOpen(_background(brand));
  }

  static Future<void> _tryOpen(List<_IntentSpec> candidates) async {
    if (!Platform.isAndroid) {
      await ph.openAppSettings();
      return;
    }
    for (final spec in candidates) {
      try {
        await AndroidIntent(
          action: 'android.intent.action.MAIN',
          package: spec.package,
          componentName: spec.activity,
        ).launch();
        return;
      } catch (e) {
        debugPrint('[OemIntents] failed ${spec.package}/${spec.activity}: $e');
        continue;
      }
    }
    // Universal fallback: app settings.
    try {
      await ph.openAppSettings();
    } catch (_) {}
  }
}

class _IntentSpec {
  const _IntentSpec(this.package, this.activity);
  final String package;
  final String activity;
}
