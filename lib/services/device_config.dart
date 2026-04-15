import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

/// Setup wizard checks. Each device requires a different subset based on
/// which OEM customizations enforce extra background restrictions.
enum SetupCheck {
  locationAlways,
  batteryOptimization,
  notificationPermission,
  autoStart,
  backgroundActivity,
}

class DeviceProfile {
  const DeviceProfile({
    required this.brand,
    required this.model,
    required this.androidSdk,
    required this.requiredChecks,
  });

  final String brand;
  final String model;
  final int androidSdk;
  final List<SetupCheck> requiredChecks;

  bool get isAndroid => Platform.isAndroid;
}

class DeviceConfig {
  DeviceConfig._();

  static DeviceProfile? _cached;

  /// Returns a cached [DeviceProfile] for the running device. iOS devices
  /// always return a minimal profile (the OEM-specific checks are Android-only).
  static Future<DeviceProfile> get profile async {
    final cached = _cached;
    if (cached != null) return cached;

    if (!Platform.isAndroid) {
      _cached = const DeviceProfile(
        brand: 'apple',
        model: 'iOS',
        androidSdk: 0,
        requiredChecks: [
          SetupCheck.locationAlways,
          SetupCheck.notificationPermission,
        ],
      );
      return _cached!;
    }

    final info = await DeviceInfoPlugin().androidInfo;
    final brand = info.brand.toLowerCase();
    final model = info.model;
    final sdk = info.version.sdkInt;

    final checks = <SetupCheck>[
      SetupCheck.locationAlways,
      SetupCheck.batteryOptimization,
      if (sdk >= 33) SetupCheck.notificationPermission,
    ];

    switch (brand) {
      case 'xiaomi':
      case 'redmi':
      case 'poco':
        checks.add(SetupCheck.autoStart);
        checks.add(SetupCheck.backgroundActivity);
        break;
      case 'oppo':
      case 'realme':
      case 'oneplus':
        checks.add(SetupCheck.autoStart);
        checks.add(SetupCheck.backgroundActivity);
        break;
      case 'vivo':
      case 'iqoo':
        checks.add(SetupCheck.autoStart);
        checks.add(SetupCheck.backgroundActivity);
        break;
      case 'samsung':
        checks.add(SetupCheck.backgroundActivity);
        break;
      case 'huawei':
      case 'honor':
        checks.add(SetupCheck.autoStart);
        checks.add(SetupCheck.backgroundActivity);
        break;
    }

    _cached = DeviceProfile(
      brand: brand,
      model: model,
      androidSdk: sdk,
      requiredChecks: checks,
    );
    return _cached!;
  }
}
