import 'package:disable_battery_optimization/disable_battery_optimization.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import '../../core/constants/app_colors.dart';
import '../../services/device_config.dart';
import '../../services/device_health_monitor.dart';
import '../../services/oem_intents.dart';

/// Mandatory device setup wizard. Displayed once on first launch (or when
/// re-triggered by [SessionProvider] because a session start failed the
/// blocking checks). Walks the employee through all OEM-specific settings
/// needed to keep the foreground tracking service alive.
class SetupWizardScreen extends StatefulWidget {
  const SetupWizardScreen({super.key, this.onComplete});

  final VoidCallback? onComplete;

  @override
  State<SetupWizardScreen> createState() => _SetupWizardScreenState();
}

class _SetupWizardScreenState extends State<SetupWizardScreen> {
  DeviceProfile? _profile;
  HealthResult? _result;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    final p = await DeviceConfig.profile;
    final r = await DeviceHealthMonitor.runAllChecks();
    if (!mounted) return;
    setState(() {
      _profile = p;
      _result = r;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    final result = _result;
    if (profile == null || result == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Set up your phone')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: AppColors.primary.withValues(alpha: 0.08),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                'Izumi needs a few settings to track your location reliably '
                'throughout the day. This takes about 2 minutes.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
          const SizedBox(height: 16),
          for (final check in profile.requiredChecks)
            _StepTile(
              check: check,
              passed: !result.failures.contains(check),
              brand: profile.brand,
              busy: _busy,
              onChanged: _refresh,
            ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: result.allPassed
                ? () {
                    widget.onComplete?.call();
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop(true);
                    }
                  }
                : null,
            child: Text(result.allPassed ? 'All set — continue' : 'Complete all steps to continue'),
          ),
        ],
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({
    required this.check,
    required this.passed,
    required this.brand,
    required this.busy,
    required this.onChanged,
  });

  final SetupCheck check;
  final bool passed;
  final String brand;
  final bool busy;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  passed ? Icons.check_circle : Icons.warning_amber_rounded,
                  color: passed ? Colors.green : AppColors.warning,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _title(check),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(_explanation(check, brand)),
            if (!passed) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: _actions(context),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _actions(BuildContext context) {
    switch (check) {
      case SetupCheck.locationAlways:
        return [
          ElevatedButton(
            onPressed: busy
                ? null
                : () async {
                    final result = await ph.Permission.locationAlways.request();
                    if (!result.isGranted) await ph.openAppSettings();
                    onChanged();
                  },
            child: const Text('Grant Always'),
          ),
        ];
      case SetupCheck.batteryOptimization:
        return [
          ElevatedButton(
            onPressed: busy
                ? null
                : () async {
                    try {
                      await DisableBatteryOptimization
                          .showDisableBatteryOptimizationSettings();
                    } catch (_) {
                      await ph.openAppSettings();
                    }
                    onChanged();
                  },
            child: const Text('Disable battery optimization'),
          ),
        ];
      case SetupCheck.notificationPermission:
        return [
          ElevatedButton(
            onPressed: busy
                ? null
                : () async {
                    final r = await ph.Permission.notification.request();
                    if (!r.isGranted) await ph.openAppSettings();
                    onChanged();
                  },
            child: const Text('Allow notifications'),
          ),
        ];
      case SetupCheck.autoStart:
        return [
          ElevatedButton(
            onPressed: busy
                ? null
                : () async {
                    await OemIntents.openAutoStart(brand);
                  },
            child: const Text('Open AutoStart settings'),
          ),
          OutlinedButton(
            onPressed: busy
                ? null
                : () async {
                    await DeviceHealthMonitor.setAutoStartConfirmed(true);
                    onChanged();
                  },
            child: const Text("I've enabled it"),
          ),
        ];
      case SetupCheck.backgroundActivity:
        return [
          ElevatedButton(
            onPressed: busy
                ? null
                : () async {
                    await OemIntents.openBackgroundActivity(brand);
                  },
            child: const Text('Open background settings'),
          ),
          OutlinedButton(
            onPressed: busy
                ? null
                : () async {
                    await DeviceHealthMonitor
                        .setBackgroundActivityConfirmed(true);
                    onChanged();
                  },
            child: const Text("I've enabled it"),
          ),
        ];
    }
  }

  static String _title(SetupCheck c) {
    switch (c) {
      case SetupCheck.locationAlways:
        return 'Location permission (Always)';
      case SetupCheck.batteryOptimization:
        return 'Disable battery optimization';
      case SetupCheck.notificationPermission:
        return 'Allow notifications';
      case SetupCheck.autoStart:
        return 'Enable Auto-start';
      case SetupCheck.backgroundActivity:
        return 'Allow background activity';
    }
  }

  static String _explanation(SetupCheck c, String brand) {
    switch (c) {
      case SetupCheck.locationAlways:
        return 'Izumi needs location access all the time so it can track your '
            'field visits even when the app is in the background.';
      case SetupCheck.batteryOptimization:
        return "Your phone's battery saver will stop Izumi from tracking. "
            'Turn it off for this app.';
      case SetupCheck.notificationPermission:
        return 'A persistent notification is shown while tracking. Without '
            'notifications, Android will stop the tracking service.';
      case SetupCheck.autoStart:
        return 'Your $brand phone stops apps from running in the background. '
            "Enable Auto-start so Izumi can keep tracking even after you've "
            'used other apps.';
      case SetupCheck.backgroundActivity:
        return 'Some $brand devices apply additional restrictions on top of '
            'battery optimization. Allow background activity for Izumi.';
    }
  }
}
