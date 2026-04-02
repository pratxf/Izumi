import 'dart:io';
import 'dart:ui';
import 'package:disable_battery_optimization/disable_battery_optimization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_typography.dart';

class PermissionService {
  static const MethodChannel _appLifecycleChannel =
      MethodChannel('izumi/app_lifecycle');

  /// Request all permissions upfront. Called once after authentication.
  /// Non-blocking — the OS shows native dialogs; denied results are handled
  /// later by [ensurePermission] when a feature actually needs the permission.
  Future<void> requestAllPermissions() async {
    final permissions = <Permission>[
      if (!Platform.isIOS) Permission.camera,
      Permission.location,
      Permission.notification,
      if (Platform.isAndroid) ...[
        Permission.photos,
      ],
    ];
    await permissions.request();
    debugPrint('[PermissionService] Bulk permission request complete');
  }

  /// Check and re-request a specific permission. Returns true if granted.
  ///
  /// If the permission was denied (not permanently), shows an explanation
  /// dialog and re-requests. If permanently denied, guides the user to
  /// app settings.
  Future<bool> ensurePermission({
    required BuildContext context,
    required Permission permission,
    required String title,
    required String message,
  }) async {
    var status = await permission.status;
    if (!context.mounted) return false;
    if (_isUsable(status)) return true;

    if (_usesIosDeferredSettingsFlow(permission)) {
      return _ensureIosPermission(
        context: context,
        permission: permission,
        title: title,
        message: message,
        status: status,
      );
    }

    if (status.isPermanentlyDenied) {
      final opened = await _showSettingsDialog(
        context: context,
        title: title,
        message: '$message\n\nPlease enable it in app settings.',
      );
      if (!context.mounted) return false;
      if (opened) {
        status = await permission.status;
        if (!context.mounted) return false;
        return _isUsable(status);
      }
      return false;
    }

    // Denied but can re-request — show explanation first
    final shouldRequest = await _showExplanationDialog(
      context: context,
      title: title,
      message: message,
    );
    if (!context.mounted) return false;
    if (!shouldRequest) return false;

    status = await permission.request();
    if (!context.mounted) return false;
    if (_isUsable(status)) return true;

    // Became permanently denied after second denial
    if (status.isPermanentlyDenied) {
      final opened = await _showSettingsDialog(
        context: context,
        title: title,
        message: '$message\n\nPlease enable it in app settings.',
      );
      if (!context.mounted) return false;
      if (opened) {
        status = await permission.status;
        if (!context.mounted) return false;
        return _isUsable(status);
      }
    }

    return false;
  }

  Future<bool> _ensureIosPermission({
    required BuildContext context,
    required Permission permission,
    required String title,
    required String message,
    required PermissionStatus status,
  }) async {
    if (status.isRestricted || status.isPermanentlyDenied) {
      final opened = await _showSettingsDialog(
        context: context,
        title: title,
        message: message,
        dismissLabel: 'Not Now',
      );
      if (!context.mounted) return false;
      if (opened) {
        status = await permission.status;
        if (!context.mounted) return false;
        return _isUsable(status);
      }
      return false;
    }

    if (!status.isDenied) return false;

    status = await permission.request();
    if (!context.mounted) return false;
    if (_isUsable(status)) return true;

    if (status.isDenied || status.isRestricted || status.isPermanentlyDenied) {
      final opened = await _showSettingsDialog(
        context: context,
        title: title,
        message: message,
        dismissLabel: 'Not Now',
      );
      if (!context.mounted) return false;
      if (opened) {
        status = await permission.status;
        if (!context.mounted) return false;
        return _isUsable(status);
      }
    }

    return false;
  }

  Future<bool> ensurePhotoLibraryPermission({
    required BuildContext context,
    required String title,
    required String message,
  }) async {
    if (!Platform.isAndroid) {
      return ensurePermission(
        context: context,
        permission: Permission.photos,
        title: title,
        message: message,
      );
    }

    return _ensurePermissions(
      context: context,
      permissions: const [
        Permission.photos,
      ],
      title: title,
      message: message,
    );
  }

  Future<bool> ensurePhotoLibraryAddPermission({
    required BuildContext context,
    required String title,
    required String message,
  }) async {
    if (!Platform.isAndroid) {
      return ensurePermission(
        context: context,
        permission: Permission.photosAddOnly,
        title: title,
        message: message,
      );
    }

    return _ensurePermissions(
      context: context,
      permissions: const [
        Permission.photos,
      ],
      title: title,
      message: message,
    );
  }

  Future<bool> ensureBackgroundLocationAccess({
    required BuildContext context,
    required String title,
    required String message,
  }) async {
    if (!Platform.isIOS) return true;

    var status = await Permission.locationAlways.status;
    if (!context.mounted) return false;
    if (_isUsable(status)) return true;

    final shouldRequest = await _showExplanationDialog(
      context: context,
      title: title,
      message: message,
    );
    if (!context.mounted) return false;
    if (!shouldRequest) return false;

    status = await Permission.locationAlways.request();
    if (!context.mounted) return false;
    if (_isUsable(status)) return true;

    if (status.isPermanentlyDenied) {
      final opened = await _showSettingsDialog(
        context: context,
        title: title,
        message: '$message\n\nPlease enable Always Location in app settings.',
      );
      if (!context.mounted) return false;
      if (opened) {
        status = await Permission.locationAlways.status;
        if (!context.mounted) return false;
        return _isUsable(status);
      }
    }

    return false;
  }

  Future<bool> ensureBatteryOptimizationExemption({
    required BuildContext context,
    required String title,
    required String message,
  }) async {
    if (!Platform.isAndroid) return true;

    bool isIgnoring = await _isIgnoringBatteryOptimizations();
    if (!context.mounted) return false;

    if (isIgnoring) return true;

    final shouldRequest = await _showExplanationDialog(
      context: context,
      title: title,
      message: message,
    );
    if (!context.mounted) return false;
    if (!shouldRequest) return false;

    try {
      final opened = await DisableBatteryOptimization
          .showDisableBatteryOptimizationSettings();
      if (opened != true) {
        await _appLifecycleChannel.invokeMethod<void>(
          'requestIgnoreBatteryOptimizations',
        );
      }
    } catch (_) {
      try {
        await _appLifecycleChannel.invokeMethod<void>(
          'requestIgnoreBatteryOptimizations',
        );
      } catch (_) {
        return false;
      }
    }

    // Give Android a moment to switch to settings and back before re-checking.
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (!context.mounted) return false;
    isIgnoring = await _isIgnoringBatteryOptimizations();
    return isIgnoring;
  }

  Future<bool> _isIgnoringBatteryOptimizations() async {
    if (!Platform.isAndroid) return true;

    try {
      return await DisableBatteryOptimization.isBatteryOptimizationDisabled ??
          false;
    } catch (_) {
      try {
        return (await _appLifecycleChannel.invokeMethod<bool>(
              'isIgnoringBatteryOptimizations',
            )) ??
            false;
      } catch (_) {
        return false;
      }
    }
  }

  bool _isUsable(PermissionStatus status) {
    return status.isGranted || status.isLimited;
  }

  bool _usesIosDeferredSettingsFlow(Permission permission) {
    if (!Platform.isIOS) return false;

    return permission == Permission.camera ||
        permission == Permission.photos ||
        permission == Permission.photosAddOnly;
  }

  Future<bool> _ensurePermissions({
    required BuildContext context,
    required List<Permission> permissions,
    required String title,
    required String message,
  }) async {
    var statuses = await _readStatuses(permissions);
    if (!context.mounted) return false;
    if (statuses.values.every(_isUsable)) return true;

    final hasPermanentDenial =
        statuses.values.any((status) => status.isPermanentlyDenied);
    if (hasPermanentDenial) {
      final opened = await _showSettingsDialog(
        context: context,
        title: title,
        message: '$message\n\nPlease enable it in app settings.',
      );
      if (!context.mounted) return false;
      if (opened) {
        statuses = await _readStatuses(permissions);
        if (!context.mounted) return false;
        return statuses.values.every(_isUsable);
      }
      return false;
    }

    final shouldRequest = await _showExplanationDialog(
      context: context,
      title: title,
      message: message,
    );
    if (!context.mounted) return false;
    if (!shouldRequest) return false;

    statuses = await permissions.request();
    if (!context.mounted) return false;
    if (statuses.values.every(_isUsable)) return true;

    if (statuses.values.any((status) => status.isPermanentlyDenied)) {
      final opened = await _showSettingsDialog(
        context: context,
        title: title,
        message: '$message\n\nPlease enable it in app settings.',
      );
      if (!context.mounted) return false;
      if (opened) {
        statuses = await _readStatuses(permissions);
        if (!context.mounted) return false;
        return statuses.values.every(_isUsable);
      }
    }

    return false;
  }

  Future<Map<Permission, PermissionStatus>> _readStatuses(
    List<Permission> permissions,
  ) async {
    final statuses = <Permission, PermissionStatus>{};
    for (final permission in permissions) {
      statuses[permission] = await permission.status;
    }
    return statuses;
  }

  Future<bool> _showExplanationDialog({
    required BuildContext context,
    required String title,
    required String message,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: AlertDialog(
          backgroundColor: AppColors.glassStrong,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Text(
            title,
            style: AppTypography.h3.copyWith(color: AppColors.textPrimary),
          ),
          content: Text(
            message,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'Not Now',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                'Allow',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return result ?? false;
  }

  /// Check if location services (GPS) are enabled. If not, show a dialog
  /// prompting the user to enable them and open location settings.
  /// Returns true if location services are enabled after the check.
  Future<bool> ensureLocationEnabled(BuildContext context) async {
    if (await Geolocator.isLocationServiceEnabled()) return true;
    if (!context.mounted) return false;

    final result = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: AlertDialog(
          backgroundColor: AppColors.glassStrong,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Text(
            'Location Disabled',
            style: AppTypography.h3.copyWith(color: AppColors.textPrimary),
          ),
          content: Text(
            'Your location services are turned off. Please enable location (GPS) to start a session.',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'Cancel',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                'Enable Location',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return false;

    if (result == true) {
      await Geolocator.openLocationSettings();
      if (!context.mounted) return false;
      // Recheck after user returns from settings
      return await Geolocator.isLocationServiceEnabled();
    }
    return false;
  }

  Future<bool> _showSettingsDialog({
    required BuildContext context,
    required String title,
    required String message,
    String dismissLabel = 'Cancel',
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: AlertDialog(
          backgroundColor: AppColors.glassStrong,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Text(
            title,
            style: AppTypography.h3.copyWith(color: AppColors.textPrimary),
          ),
          content: Text(
            message,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                dismissLabel,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                'Open Settings',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return false;
    if (result == true) {
      await openAppSettings();
      if (!context.mounted) return false;
      return true;
    }
    return false;
  }
}
