package com.izumi.izumi

import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import com.google.firebase.database.FirebaseDatabase
import com.google.firebase.database.ServerValue
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.SetOptions
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class SessionTaskRemovalService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> persistSessionContext(intent)
            ACTION_STOP -> {
                clearSessionContext()
                stopSelf()
            }
        }
        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        val prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
        val enterpriseId = prefs.getString(KEY_ENTERPRISE_ID, null)
        val userId = prefs.getString(KEY_USER_ID, null)
        val sessionId = prefs.getString(KEY_SESSION_ID, null)

        if (!enterpriseId.isNullOrBlank() &&
            !userId.isNullOrBlank() &&
            !sessionId.isNullOrBlank()
        ) {
            // Delay 3 seconds to let onDestroy() complete first.
            // If onDestroy already set presence to offline, skip cleanup.
            Handler(Looper.getMainLooper()).postDelayed({
                safetyNetCleanup(enterpriseId, userId, sessionId)
            }, 3000)
        } else {
            stopSelf()
        }

        super.onTaskRemoved(rootIntent)
    }

    private fun persistSessionContext(intent: Intent) {
        val enterpriseId = intent.getStringExtra(EXTRA_ENTERPRISE_ID)
        val userId = intent.getStringExtra(EXTRA_USER_ID)
        val sessionId = intent.getStringExtra(EXTRA_SESSION_ID)

        if (enterpriseId.isNullOrBlank() ||
            userId.isNullOrBlank() ||
            sessionId.isNullOrBlank()
        ) {
            return
        }

        getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
            .edit()
            .putString(KEY_ENTERPRISE_ID, enterpriseId)
            .putString(KEY_USER_ID, userId)
            .putString(KEY_SESSION_ID, sessionId)
            .apply()
    }

    private fun clearSessionContext() {
        getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
            .edit()
            .clear()
            .apply()
    }

    private fun safetyNetCleanup(
        enterpriseId: String,
        userId: String,
        sessionId: String,
    ) {
        val rtdb = FirebaseDatabase.getInstance().reference

        // Check if onDestroy already cleaned up by reading RTDB presence.
        rtdb.child("presence/$enterpriseId/$userId/status").get()
            .addOnSuccessListener { snapshot ->
                val currentStatus = snapshot.getValue(String::class.java)

                if (currentStatus == "offline") {
                    // onDestroy already handled cleanup — nothing to do.
                    Log.d(TAG, "Presence already offline, skipping safety-net cleanup")
                    clearSessionContext()
                    stopSelf()
                    return@addOnSuccessListener
                }

                // Presence is still active or signal_lost — onDestroy failed.
                // Fire-and-forget: write session end to Firestore directly (no read).
                Log.d(TAG, "Presence is '$currentStatus', running safety-net cleanup")

                val firestore = FirebaseFirestore.getInstance()

                val todayDate = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(Date())

                // Fire-and-forget: end session in Firestore
                firestore.collection("sessions").document(sessionId).set(
                    mapOf(
                        "endTime" to FieldValue.serverTimestamp(),
                        "status" to "auto_ended",
                        "autoEndReason" to "app_removed_from_recents",
                        "autoEndSource" to "android_task_removed_service_safety_net",
                        "recalculateOnComplete" to true,
                    ),
                    SetOptions.merge(),
                ).addOnFailureListener { e ->
                    Log.e(TAG, "Failed to write session end: $e")
                }

                // Fire-and-forget: write activityLog
                firestore.collection("activityLogs")
                    .document("session_auto_ended_$sessionId").set(
                        mapOf(
                            "enterpriseId" to enterpriseId,
                            "employeeId" to userId,
                            "sessionId" to sessionId,
                            "orgId" to enterpriseId,
                            "type" to "session_auto_ended",
                            "title" to "Session Auto-Ended",
                            "detail" to "Session was auto-ended (app removed from recents)",
                            "date" to todayDate,
                            "timestamp" to FieldValue.serverTimestamp(),
                            "metadata" to mapOf(
                                "reason" to "app_removed_from_recents",
                                "source" to "android_task_removed_service_safety_net",
                            ),
                        ),
                        SetOptions.merge(),
                    ).addOnFailureListener { e ->
                        Log.e(TAG, "Failed to write activityLog: $e")
                    }

                // Fire-and-forget: set presence to offline, clear dashboard nodes
                val updates = hashMapOf<String, Any?>(
                    "presence/$enterpriseId/$userId/status" to "offline",
                    "presence/$enterpriseId/$userId/signalLostAt" to null,
                    "presence/$enterpriseId/$userId/currentSessionId" to null,
                    "presence/$enterpriseId/$userId/lastSeen" to ServerValue.TIMESTAMP,
                    "activeStats/$enterpriseId/$userId" to null,
                    "sessionHeartbeat/$enterpriseId/$userId" to null,
                    "liveLocations/$enterpriseId/$userId" to null,
                )
                rtdb.updateChildren(updates).addOnFailureListener { e ->
                    Log.e(TAG, "Failed to update RTDB: $e")
                }

                clearSessionContext()
                stopSelf()
            }
            .addOnFailureListener { e ->
                // RTDB read failed — proceed with cleanup anyway to avoid stuck state.
                Log.e(TAG, "Failed to read presence, proceeding with cleanup: $e")

                val firestore = FirebaseFirestore.getInstance()

                firestore.collection("sessions").document(sessionId).set(
                    mapOf(
                        "endTime" to FieldValue.serverTimestamp(),
                        "status" to "auto_ended",
                        "autoEndReason" to "app_removed_from_recents",
                        "autoEndSource" to "android_task_removed_service_safety_net",
                        "recalculateOnComplete" to true,
                    ),
                    SetOptions.merge(),
                )

                val updates = hashMapOf<String, Any?>(
                    "presence/$enterpriseId/$userId/status" to "offline",
                    "presence/$enterpriseId/$userId/signalLostAt" to null,
                    "presence/$enterpriseId/$userId/currentSessionId" to null,
                    "presence/$enterpriseId/$userId/lastSeen" to ServerValue.TIMESTAMP,
                    "activeStats/$enterpriseId/$userId" to null,
                    "sessionHeartbeat/$enterpriseId/$userId" to null,
                    "liveLocations/$enterpriseId/$userId" to null,
                )
                rtdb.updateChildren(updates)

                clearSessionContext()
                stopSelf()
            }
    }

    companion object {
        private const val TAG = "SessionTaskRemoval"
        private const val PREFS_NAME = "izumi_session_task_guard"
        private const val KEY_ENTERPRISE_ID = "enterprise_id"
        private const val KEY_USER_ID = "user_id"
        private const val KEY_SESSION_ID = "session_id"

        private const val ACTION_START = "com.izumi.izumi.action.START_SESSION_GUARD"
        private const val ACTION_STOP = "com.izumi.izumi.action.STOP_SESSION_GUARD"

        const val EXTRA_ENTERPRISE_ID = "enterpriseId"
        const val EXTRA_USER_ID = "userId"
        const val EXTRA_SESSION_ID = "sessionId"

        fun startIntent(
            context: Context,
            enterpriseId: String,
            userId: String,
            sessionId: String,
        ): Intent = Intent(context, SessionTaskRemovalService::class.java).apply {
            action = ACTION_START
            putExtra(EXTRA_ENTERPRISE_ID, enterpriseId)
            putExtra(EXTRA_USER_ID, userId)
            putExtra(EXTRA_SESSION_ID, sessionId)
        }

        fun stopIntent(context: Context): Intent =
            Intent(context, SessionTaskRemovalService::class.java).apply {
                action = ACTION_STOP
            }
    }
}
