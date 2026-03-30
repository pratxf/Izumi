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
                else -> result.notImplemented()
            }
        }
    }
}
