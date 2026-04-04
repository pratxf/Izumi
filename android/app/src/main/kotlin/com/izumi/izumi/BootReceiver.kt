package com.izumi.izumi

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.google.android.gms.tasks.Tasks
import com.google.firebase.FirebaseApp
import com.google.firebase.database.FirebaseDatabase
import com.google.firebase.database.ServerValue
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import java.util.concurrent.TimeUnit

/**
 * Handles device reboot: if an active session existed before the reboot,
 * auto-end it and clean up RTDB nodes. Uses the same SharedPreferences
 * key as [SessionTaskRemovalService].
 */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return

        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != "android.intent.action.QUICKBOOT_POWERON" &&
            action != "com.htc.intent.action.QUICKBOOT_POWERON"
        ) {
            return
        }

        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val sessionId = prefs.getString(KEY_SESSION_ID, null)
        val enterpriseId = prefs.getString(KEY_ENTERPRISE_ID, null)
        val userId = prefs.getString(KEY_USER_ID, null)

        if (sessionId.isNullOrBlank() ||
            enterpriseId.isNullOrBlank() ||
            userId.isNullOrBlank()
        ) {
            return
        }

        // Ensure Firebase is initialized
        try {
            if (FirebaseApp.getApps(context).isEmpty()) {
                FirebaseApp.initializeApp(context)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Firebase init failed: $e")
            return
        }

        val goAsync = goAsync()

        Thread {
            try {
                val db = FirebaseFirestore.getInstance()
                val rtdb = FirebaseDatabase.getInstance().reference
                val sessionRef = db.collection("sessions").document(sessionId)

                // Check if session is still active
                val snapshot = Tasks.await(sessionRef.get(), 10, TimeUnit.SECONDS)
                if (!snapshot.exists()) {
                    prefs.edit().clear().apply()
                    goAsync.finish()
                    return@Thread
                }

                val status = snapshot.getString("status")
                if (status != "active" && status != "signal_lost") {
                    // Already ended — just clean up RTDB
                    try {
                        val updates = hashMapOf<String, Any?>(
                            "activeStats/$enterpriseId/$userId" to null,
                            "sessionHeartbeat/$enterpriseId/$userId" to null,
                            "liveLocations/$enterpriseId/$userId" to null,
                        )
                        Tasks.await(rtdb.updateChildren(updates), 10, TimeUnit.SECONDS)
                    } catch (_: Exception) {}
                    prefs.edit().clear().apply()
                    goAsync.finish()
                    return@Thread
                }

                // Session still active — auto-end it
                val startTimestamp = snapshot.getTimestamp("startTime")
                val nowMillis = System.currentTimeMillis()
                val totalDuration = if (startTimestamp != null) {
                    ((nowMillis - startTimestamp.toDate().time) / 1000).coerceAtLeast(0)
                } else {
                    0
                }

                try {
                    Tasks.await(
                        sessionRef.update(
                            mapOf(
                                "endTime" to FieldValue.serverTimestamp(),
                                "status" to "auto_ended",
                                "totalDuration" to totalDuration,
                                "totalDistance" to (snapshot.getDouble("totalDistance") ?: 0.0),
                                "photosCount" to (snapshot.getLong("photosCount") ?: 0L),
                                "tasksCompleted" to (snapshot.getLong("tasksCompleted") ?: 0L),
                                "notes" to "Auto-ended: device rebooted.",
                                "autoEndReason" to "device_rebooted",
                                "autoEndSource" to "boot_receiver",
                            ),
                        ),
                        10, TimeUnit.SECONDS,
                    )
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to update session: $e")
                }

                // Write activity log
                try {
                    val activityRef = db.collection("activityLogs")
                        .document("session_auto_ended_$sessionId")
                    Tasks.await(
                        activityRef.set(
                            mapOf(
                                "enterpriseId" to enterpriseId,
                                "employeeId" to userId,
                                "sessionId" to sessionId,
                                "type" to "session_auto_ended",
                                "title" to "Session Auto-Ended",
                                "detail" to "Device was rebooted.",
                                "timestamp" to FieldValue.serverTimestamp(),
                                "metadata" to mapOf(
                                    "reason" to "device_rebooted",
                                    "source" to "boot_receiver",
                                ),
                            ),
                        ),
                        10, TimeUnit.SECONDS,
                    )
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to write activityLog: $e")
                }

                // Clean up RTDB
                try {
                    val updates = hashMapOf<String, Any?>(
                        "presence/$enterpriseId/$userId" to mapOf(
                            "status" to "offline",
                            "lastSeen" to ServerValue.TIMESTAMP,
                            "currentSessionId" to null,
                            "signalLostAt" to null,
                        ),
                        "activeStats/$enterpriseId/$userId" to null,
                        "sessionHeartbeat/$enterpriseId/$userId" to null,
                        "liveLocations/$enterpriseId/$userId" to null,
                    )
                    Tasks.await(rtdb.updateChildren(updates), 10, TimeUnit.SECONDS)
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to clean up RTDB: $e")
                }

                Log.i(TAG, "Auto-ended session $sessionId after device reboot")
            } catch (e: Exception) {
                Log.e(TAG, "BootReceiver failed: $e")
            } finally {
                prefs.edit().clear().apply()
                goAsync.finish()
            }
        }.start()
    }

    companion object {
        private const val TAG = "BootReceiver"
        // Same SharedPreferences as SessionTaskRemovalService
        private const val PREFS_NAME = "izumi_session_task_guard"
        private const val KEY_ENTERPRISE_ID = "enterprise_id"
        private const val KEY_USER_ID = "user_id"
        private const val KEY_SESSION_ID = "session_id"
    }
}
