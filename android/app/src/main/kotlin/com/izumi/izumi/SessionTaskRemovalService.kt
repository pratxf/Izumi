package com.izumi.izumi

import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.IBinder
import com.google.firebase.database.FirebaseDatabase
import com.google.firebase.database.ServerValue
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore

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
            autoEndSession(enterpriseId, userId, sessionId)
        }

        stopSelf()
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

    private fun autoEndSession(
        enterpriseId: String,
        userId: String,
        sessionId: String,
    ) {
        val firestore = FirebaseFirestore.getInstance()
        val rtdb = FirebaseDatabase.getInstance().reference
        val sessionRef = firestore.collection("sessions").document(sessionId)

        sessionRef.get().addOnSuccessListener { snapshot ->
            if (!snapshot.exists()) {
                clearSessionContext()
                return@addOnSuccessListener
            }

            val status = snapshot.getString("status")
            val sessionEnterpriseId = snapshot.getString("enterpriseId")
            val sessionEmployeeId = snapshot.getString("employeeId")
            if (status != "active" ||
                sessionEnterpriseId != enterpriseId ||
                sessionEmployeeId != userId
            ) {
                clearSessionContext()
                return@addOnSuccessListener
            }

            val startTimestamp = snapshot.getTimestamp("startTime")
            val totalDistance = snapshot.getDouble("totalDistance") ?: 0.0
            val photosCount = snapshot.getLong("photosCount") ?: 0L
            val tasksCompleted = snapshot.getLong("tasksCompleted") ?: 0L
            val nowMillis = System.currentTimeMillis()
            val totalDuration = if (startTimestamp != null) {
                ((nowMillis - startTimestamp.toDate().time) / 1000).coerceAtLeast(0)
            } else {
                0
            }

            val batch = firestore.batch()
            batch.update(
                sessionRef,
                mapOf(
                    "endTime" to FieldValue.serverTimestamp(),
                    "status" to "auto_ended",
                    "totalDuration" to totalDuration,
                    "totalDistance" to totalDistance,
                    "photosCount" to photosCount,
                    "tasksCompleted" to tasksCompleted,
                    "notes" to "Auto-ended because the app was removed from recent apps.",
                    "autoEndReason" to "app_removed_from_recents",
                    "autoEndSource" to "android_task_removed_service",
                ),
            )

            val activityRef = firestore.collection("activityLogs").document("session_auto_ended_$sessionId")
            batch.set(
                activityRef,
                mapOf(
                    "enterpriseId" to enterpriseId,
                    "employeeId" to userId,
                    "sessionId" to sessionId,
                    "type" to "session_auto_ended",
                    "title" to "Session Auto-Ended",
                    "detail" to "App was removed from recent apps.",
                    "timestamp" to FieldValue.serverTimestamp(),
                    "metadata" to mapOf(
                        "reason" to "app_removed_from_recents",
                        "source" to "android_task_removed_service",
                    ),
                ),
            )

            batch.commit().addOnCompleteListener {
                rtdb.child("presence/$enterpriseId/$userId").setValue(
                    mapOf(
                        "status" to "offline",
                        "lastSeen" to ServerValue.TIMESTAMP,
                        "currentSessionId" to null,
                    ),
                )
                rtdb.child("activeStats/$enterpriseId/$userId").removeValue()
                rtdb.child("sessionHeartbeat/$enterpriseId/$userId").removeValue()
                clearSessionContext()
            }
        }.addOnFailureListener {
            clearSessionContext()
        }
    }

    companion object {
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
