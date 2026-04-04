package com.izumi.izumi

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private lateinit var lifecycleChannel: MethodChannel

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        lifecycleChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "izumi/app_lifecycle"
        )
        lifecycleChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startSessionTaskGuard" -> {
                    val enterpriseId = call.argument<String>("enterpriseId")
                    val userId = call.argument<String>("userId")
                    val sessionId = call.argument<String>("sessionId")

                    if (enterpriseId.isNullOrBlank() ||
                        userId.isNullOrBlank() ||
                        sessionId.isNullOrBlank()
                    ) {
                        result.error(
                            "invalid_args",
                            "enterpriseId, userId, and sessionId are required.",
                            null,
                        )
                        return@setMethodCallHandler
                    }

                    val intent = SessionTaskRemovalService.startIntent(
                        this,
                        enterpriseId,
                        userId,
                        sessionId,
                    )
                    startService(intent)
                    result.success(null)
                }
                "stopSessionTaskGuard" -> {
                    val intent = SessionTaskRemovalService.stopIntent(this)
                    stopService(intent)
                    result.success(null)
                }
                "isIgnoringBatteryOptimizations" -> {
                    val powerManager =
                        getSystemService(Context.POWER_SERVICE) as PowerManager
                    val packageName = applicationContext.packageName
                    result.success(
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            powerManager.isIgnoringBatteryOptimizations(packageName)
                        } else {
                            true
                        }
                    )
                }
                "requestIgnoreBatteryOptimizations" -> {
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
                        result.success(true)
                        return@setMethodCallHandler
                    }

                    val packageName = applicationContext.packageName
                    val powerManager =
                        getSystemService(Context.POWER_SERVICE) as PowerManager
                    if (powerManager.isIgnoringBatteryOptimizations(packageName)) {
                        result.success(true)
                        return@setMethodCallHandler
                    }

                    val intent = Intent(
                        Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                        Uri.parse("package:$packageName")
                    )
                    startActivity(intent)
                    result.success(true)
                }
                "openOemBatterySettings" -> {
                    result.success(openOemBatterySettings())
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Opens OEM-specific battery/autostart settings based on device manufacturer.
     * Returns true if an OEM intent was successfully launched.
     */
    private fun openOemBatterySettings(): Boolean {
        val manufacturer = Build.MANUFACTURER.lowercase()
        val brand = Build.BRAND.lowercase()
        val packageName = applicationContext.packageName

        val intents = mutableListOf<Intent>()

        when {
            // Xiaomi / Redmi / POCO
            manufacturer.contains("xiaomi") || brand.contains("redmi") || brand.contains("poco") -> {
                // AutoStart manager
                intents.add(Intent().apply {
                    component = android.content.ComponentName(
                        "com.miui.securitycenter",
                        "com.miui.permcenter.autostart.AutoStartManagementActivity",
                    )
                })
                // Battery saver whitelist
                intents.add(Intent().apply {
                    component = android.content.ComponentName(
                        "com.miui.powerkeeper",
                        "com.miui.powerkeeper.ui.HiddenAppsConfigActivity",
                    )
                    putExtra("package_name", packageName)
                    putExtra("package_label", "Izumi")
                })
            }

            // Huawei / Honor
            manufacturer.contains("huawei") || brand.contains("honor") -> {
                // Startup manager
                intents.add(Intent().apply {
                    component = android.content.ComponentName(
                        "com.huawei.systemmanager",
                        "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
                    )
                })
                // Protected apps
                intents.add(Intent().apply {
                    component = android.content.ComponentName(
                        "com.huawei.systemmanager",
                        "com.huawei.systemmanager.optimize.process.ProtectActivity",
                    )
                })
            }

            // Samsung
            manufacturer.contains("samsung") -> {
                // Battery optimization settings
                intents.add(Intent().apply {
                    component = android.content.ComponentName(
                        "com.samsung.android.lool",
                        "com.samsung.android.sm.battery.ui.BatteryActivity",
                    )
                })
                intents.add(Intent().apply {
                    component = android.content.ComponentName(
                        "com.samsung.android.lool",
                        "com.samsung.android.sm.ui.battery.BatteryActivity",
                    )
                })
            }

            // OnePlus
            manufacturer.contains("oneplus") -> {
                intents.add(Intent().apply {
                    component = android.content.ComponentName(
                        "com.oneplus.security",
                        "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity",
                    )
                })
            }

            // Oppo / Realme
            manufacturer.contains("oppo") || brand.contains("realme") -> {
                intents.add(Intent().apply {
                    component = android.content.ComponentName(
                        "com.coloros.safecenter",
                        "com.coloros.safecenter.startupapp.StartupAppListActivity",
                    )
                })
                intents.add(Intent().apply {
                    component = android.content.ComponentName(
                        "com.oppo.safe",
                        "com.oppo.safe.permission.startup.StartupAppListActivity",
                    )
                })
            }

            // Vivo
            manufacturer.contains("vivo") -> {
                intents.add(Intent().apply {
                    component = android.content.ComponentName(
                        "com.vivo.permissionmanager",
                        "com.vivo.permissionmanager.activity.BgStartUpManagerActivity",
                    )
                })
                intents.add(Intent().apply {
                    component = android.content.ComponentName(
                        "com.iqoo.secure",
                        "com.iqoo.secure.ui.phoneoptimize.BgStartUpManager",
                    )
                })
            }

            else -> return false
        }

        // Fallback: app details settings (always works)
        intents.add(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.parse("package:$packageName")
        })

        for (intent in intents) {
            try {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                return true
            } catch (_: Exception) {
                continue
            }
        }
        return false
    }
}
