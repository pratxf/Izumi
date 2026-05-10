package com.izumi.izumi

import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.work.Worker
import androidx.work.WorkerParameters

class TrackingWatchdogWorker(
    private val context: Context,
    workerParams: WorkerParameters,
) : Worker(context, workerParams) {

    companion object {
        private const val TAG = "TrackingWatchdog"
        private const val PREFS_NAME = "FlutterSharedPreferences"
        private const val TRACKING_ACTIVE_KEY = "flutter.izumi_tracking_active"
        private const val NEEDS_RESUME_KEY = "flutter.needs_resume"
        private const val KILLED_AT_KEY = "flutter.needs_resume_killed_at_ms"
        private const val EIGHT_HOURS_MS = 8L * 60 * 60 * 1000
        private const val FOREGROUND_SERVICE_CLASS =
            "com.pravera.flutter_foreground_task.service.ForegroundService"
    }

    override fun doWork(): Result {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

        // No active tracking session — nothing to do.
        val trackingActive = prefs.getBoolean(TRACKING_ACTIVE_KEY, false)
        if (!trackingActive) return Result.success()

        // needs_resume is false means the service is currently running normally.
        val needsResume = prefs.getBoolean(NEEDS_RESUME_KEY, false)
        if (!needsResume) return Result.success()

        // Gap >= 8h: server sweep handles auto-end; watchdog stays out.
        val killedAtMs = prefs.getLong(KILLED_AT_KEY, 0L)
        if (killedAtMs > 0L && System.currentTimeMillis() - killedAtMs >= EIGHT_HOURS_MS) {
            return Result.success()
        }

        // Service was killed and gap < 8h — attempt restart.
        Log.i(TAG, "Detected dead tracking service with active session; restarting.")
        return try {
            val intent = Intent().apply {
                setClassName(context.packageName, FOREGROUND_SERVICE_CLASS)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
            Log.i(TAG, "Foreground service restart requested.")
            Result.success()
        } catch (e: Exception) {
            val isFgsNotAllowed = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                e.javaClass.canonicalName ==
                    "android.app.ForegroundServiceStartNotAllowedException"
            if (isFgsNotAllowed) {
                Log.w(TAG, "Cannot start FGS from background on Android 12+: ${e.message}")
                // Write a flag so the app knows it needs to self-restart on next open.
                prefs.edit().putBoolean("flutter.watchdog_restart_failed", true).apply()
            } else {
                Log.w(TAG, "Failed to restart tracking service: ${e.message}")
            }
            Result.retry()
        }
    }
}
