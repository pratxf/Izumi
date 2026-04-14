import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import * as admin from "firebase-admin";
import { sendNotification } from "../utils/send_notification";

/**
 * Force-end ALL active sessions across the enterprise.
 *
 * For every employee with a non-offline RTDB presence OR an active Firestore
 * session:
 *   1. Sets the Firestore session status to "auto_ended"
 *   2. Writes an activityLog entry
 *   3. Sets RTDB presence to offline
 *   4. Clears activeStats, sessionHeartbeat, liveLocations from RTDB
 *   5. Sends a push notification telling the employee to start a new session
 *
 * Admin-only.
 */
export const forceEndAllSessions = onCall(
  {
    region: "asia-south1",
    timeoutSeconds: 300,
    memory: "512MiB",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be authenticated.");
    }
    const claims = request.auth.token;
    const roles = claims.roles as string[] | undefined;
    if (!roles || !roles.includes("admin")) {
      throw new HttpsError("permission-denied", "Admin access required.");
    }

    const db = admin.firestore();
    const rtdb = admin.database();
    const now = Date.now();

    let endedCount = 0;
    const results: Array<{
      enterpriseId: string;
      userId: string;
      sessionId: string;
    }> = [];

    // ── 1. Find all active Firestore sessions ──
    const activeSessions = await db
      .collection("sessions")
      .where("status", "==", "active")
      .get();

    const allSessions = [...activeSessions.docs];
    const processedUserKeys = new Set<string>();

    for (const sessionDoc of allSessions) {
      const session = sessionDoc.data();
      const enterpriseId = session.enterpriseId as string | undefined;
      const userId = session.employeeId as string | undefined;

      if (!enterpriseId || !userId) continue;

      const startTimeMs = session.startTime?.toMillis?.() ?? now;
      const totalDurationSecs = Math.max(
        0,
        Math.floor((now - startTimeMs) / 1000),
      );

      // End the session
      await sessionDoc.ref.update({
        endTime: admin.firestore.Timestamp.fromMillis(now),
        status: "auto_ended",
        totalDuration: totalDurationSecs,
        totalDistance: session.totalDistance ?? 0,
        photosCount: session.photosCount ?? 0,
        tasksCompleted: session.tasksCompleted ?? 0,
        notes: "Force-ended by admin (end all sessions).",
        autoEndReason: "admin_force_end_all",
        autoEndSource: "force_end_all_sessions",
      });

      // Write activityLog
      const endDate = new Date(now + 5.5 * 60 * 60 * 1000);
      const dateStr = endDate.toISOString().slice(0, 10);

      await db
        .collection("activityLogs")
        .doc(`session_auto_ended_${sessionDoc.id}`)
        .set(
          {
            enterpriseId,
            employeeId: userId,
            sessionId: sessionDoc.id,
            orgId: enterpriseId,
            type: "session_auto_ended",
            title: "Session Ended by Admin",
            detail: "Your session was ended by an admin. Please start a new session.",
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
            date: dateStr,
            metadata: {
              reason: "admin_force_end_all",
              source: "force_end_all_sessions",
            },
          },
          { merge: true },
        );

      const userKey = `${enterpriseId}/${userId}`;

      // Clean up RTDB and send notification (once per user)
      if (!processedUserKeys.has(userKey)) {
        processedUserKeys.add(userKey);

        await Promise.all([
          rtdb.ref(`presence/${enterpriseId}/${userId}`).set({
            status: "offline",
            lastSeen: admin.database.ServerValue.TIMESTAMP,
            currentSessionId: null,
          }),
          rtdb.ref(`activeStats/${enterpriseId}/${userId}`).remove(),
          rtdb.ref(`sessionHeartbeat/${enterpriseId}/${userId}`).remove(),
          rtdb.ref(`liveLocations/${enterpriseId}/${userId}`).remove(),
          sendNotification({
            userId,
            title: "Session Ended",
            body: "Your session was ended by an admin. Please start a new session to continue tracking.",
            type: "alert",
            data: {
              action: "SESSION_FORCE_ENDED",
              status: "auto_ended",
              sessionId: sessionDoc.id,
              employeeId: userId,
            },
          }),
        ]);
      }

      results.push({ enterpriseId, userId, sessionId: sessionDoc.id });
      endedCount++;

      logger.info("forceEndAllSessions: Ended session.", {
        enterpriseId,
        userId,
        sessionId: sessionDoc.id,
        previousStatus: session.status,
      });
    }

    // ── 2. Clean up any remaining non-offline RTDB presence nodes ──
    // (employees whose Firestore session was already ended but RTDB is stuck)
    const presenceRootSnap = await rtdb.ref("presence").get();
    const presenceRoot = presenceRootSnap.val() as Record<
      string,
      Record<string, { status?: string }>
    > | null;

    let rtdbCleanedCount = 0;
    if (presenceRoot) {
      for (const [enterpriseId, employees] of Object.entries(presenceRoot)) {
        for (const [userId, presence] of Object.entries(employees ?? {})) {
          if (!presence?.status || presence.status === "offline") continue;

          const userKey = `${enterpriseId}/${userId}`;
          if (processedUserKeys.has(userKey)) continue;

          await Promise.all([
            rtdb.ref(`presence/${enterpriseId}/${userId}`).set({
              status: "offline",
              lastSeen: admin.database.ServerValue.TIMESTAMP,
              currentSessionId: null,
            }),
            rtdb.ref(`activeStats/${enterpriseId}/${userId}`).remove(),
            rtdb.ref(`sessionHeartbeat/${enterpriseId}/${userId}`).remove(),
            rtdb.ref(`liveLocations/${enterpriseId}/${userId}`).remove(),
            sendNotification({
              userId,
              title: "Session Ended",
              body: "Your session was ended by an admin. Please start a new session to continue tracking.",
              type: "alert",
              data: {
                action: "SESSION_FORCE_ENDED",
                status: "auto_ended",
                employeeId: userId,
              },
            }),
          ]);

          rtdbCleanedCount++;
        }
      }
    }

    logger.info("forceEndAllSessions: Complete.", {
      endedCount,
      rtdbCleanedCount,
    });

    return {
      ended: endedCount,
      rtdbCleaned: rtdbCleanedCount,
      sessions: results,
      message: `Ended ${endedCount} session(s), cleaned ${rtdbCleanedCount} stale presence node(s).`,
    };
  },
);
