import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import * as admin from "firebase-admin";

type PresenceNode = {
  status?: string;
  signalLostAt?: number;
  currentSessionId?: string | null;
  lastSeen?: number;
};

/**
 * One-time callable function to force-end ALL signal_lost ghost sessions.
 *
 * For every employee whose RTDB presence is "signal_lost":
 *   1. Finds their active Firestore session and sets status → auto_ended
 *   2. Writes an activityLog entry
 *   3. Sets RTDB presence → offline
 *   4. Clears activeStats, sessionHeartbeat, liveLocations from RTDB
 *
 * Admin-only. Call from Flutter:
 *   FirebaseFunctions.instanceFor(region: 'asia-south1')
 *       .httpsCallable('forceEndGhostSessions')
 *       .call();
 */
export const forceEndGhostSessions = onCall(
  {
    region: "asia-south1",
    timeoutSeconds: 300,
    memory: "512MiB",
  },
  async (request) => {
    // Admin-only guard
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

    const presenceRootSnap = await rtdb.ref("presence").get();
    const presenceRoot = presenceRootSnap.val() as Record<
      string,
      Record<string, PresenceNode>
    > | null;

    if (!presenceRoot) {
      return { ended: 0, message: "No presence nodes found." };
    }

    let endedCount = 0;
    const results: Array<{
      enterpriseId: string;
      userId: string;
      sessionId: string;
    }> = [];

    for (const [enterpriseId, enterprisePresence] of Object.entries(
      presenceRoot,
    )) {
      for (const [userId, presence] of Object.entries(
        enterprisePresence ?? {},
      )) {
        // Skip offline
        if (!presence?.status || presence.status === "offline") continue;

        // For "active" presences, only clean up if heartbeat is stale (>15 min)
        // to avoid killing genuinely active sessions
        if (presence.status === "active") {
          const lastSeen = presence.lastSeen ?? 0;
          const ageMs = now - lastSeen;
          if (lastSeen > 0 && ageMs < 15 * 60 * 1000) continue; // fresh heartbeat — skip
        }

        // Find active session — try presence.currentSessionId first, then query
        let sessionRef: admin.firestore.DocumentReference | null = null;

        if (presence.currentSessionId) {
          const snap = await db
            .collection("sessions")
            .doc(presence.currentSessionId)
            .get();
          if (snap.exists && snap.data()?.status === "active") {
            sessionRef = snap.ref;
          }
        }

        if (!sessionRef) {
          const activeSnap = await db
            .collection("sessions")
            .where("enterpriseId", "==", enterpriseId)
            .where("employeeId", "==", userId)
            .where("status", "==", "active")
            .limit(1)
            .get();
          if (!activeSnap.empty) {
            sessionRef = activeSnap.docs[0].ref;
          }
        }

        // End the session if found
        if (sessionRef) {
          const sessionSnap = await sessionRef.get();
          const session = sessionSnap.data();

          if (session && (session.status === "active" || session.status === "signal_lost")) {
            const startTimeMs = session.startTime?.toMillis?.() ?? now;
            const effectiveEndTime = presence.signalLostAt ?? now;
            const totalDurationSecs = Math.max(
              0,
              Math.floor((effectiveEndTime - startTimeMs) / 1000),
            );

            await sessionRef.update({
              endTime: admin.firestore.Timestamp.fromMillis(effectiveEndTime),
              status: "auto_ended",
              totalDuration: totalDurationSecs,
              totalDistance: session.totalDistance ?? 0,
              photosCount: session.photosCount ?? 0,
              tasksCompleted: session.tasksCompleted ?? 0,
              notes: "Force-ended ghost session (admin cleanup).",
              autoEndReason: "ghost_session_cleanup",
              autoEndSource: "force_end_ghost_sessions",
            });

            // Write activityLog
            const endDate = new Date(effectiveEndTime + 5.5 * 60 * 60 * 1000);
            const dateStr = endDate.toISOString().slice(0, 10);

            await db
              .collection("activityLogs")
              .doc(`session_auto_ended_${sessionRef.id}`)
              .set(
                {
                  enterpriseId,
                  employeeId: userId,
                  sessionId: sessionRef.id,
                  orgId: enterpriseId,
                  type: "session_auto_ended",
                  title: "Session Auto-Ended",
                  detail: "Ghost session force-ended by admin.",
                  timestamp: admin.firestore.FieldValue.serverTimestamp(),
                  date: dateStr,
                  metadata: {
                    reason: "ghost_session_cleanup",
                    source: "force_end_ghost_sessions",
                  },
                },
                { merge: true },
              );

            results.push({
              enterpriseId,
              userId,
              sessionId: sessionRef.id,
            });
          }
        }

        // Set presence offline & clean up RTDB regardless of session
        await Promise.all([
          rtdb.ref(`presence/${enterpriseId}/${userId}`).set({
            status: "offline",
            lastSeen: admin.database.ServerValue.TIMESTAMP,
            currentSessionId: null,
            signalLostAt: null,
          }),
          rtdb.ref(`activeStats/${enterpriseId}/${userId}`).remove(),
          rtdb.ref(`sessionHeartbeat/${enterpriseId}/${userId}`).remove(),
          rtdb.ref(`liveLocations/${enterpriseId}/${userId}`).remove(),
        ]);

        endedCount++;
        logger.info("forceEndGhostSessions: Cleaned up.", {
          enterpriseId,
          userId,
          sessionId: sessionRef?.id ?? "none",
        });
      }
    }

    logger.info("forceEndGhostSessions: Complete.", {
      endedCount,
    });

    return {
      ended: endedCount,
      sessions: results,
      message: `Force-ended ${endedCount} ghost session(s).`,
    };
  },
);
