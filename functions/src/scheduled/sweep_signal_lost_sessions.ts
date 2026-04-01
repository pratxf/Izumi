import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions/v2";
import * as admin from "firebase-admin";
import { sendNotification } from "../utils/send_notification";

const SIGNAL_LOST_MAX_AGE_MS = 60 * 60 * 1000;

type PresenceNode = {
  status?: string;
  signalLostAt?: number;
  currentSessionId?: string | null;
  lastSeen?: number;
};

type SessionDoc = {
  employeeId?: string;
  enterpriseId?: string;
  startTime?: admin.firestore.Timestamp;
  status?: string;
  totalDistance?: number;
  photosCount?: number;
  tasksCompleted?: number;
};

export const sweepSignalLostSessions = onSchedule(
  {
    schedule: "*/30 * * * *",
    timeZone: "Asia/Kolkata",
    region: "asia-south1",
    retryCount: 1,
    timeoutSeconds: 300,
    memory: "512MiB",
  },
  async () => {
    const db = admin.firestore();
    const rtdb = admin.database();
    const now = Date.now();

    const presenceRootSnap = await rtdb.ref("presence").get();
    const presenceRoot = presenceRootSnap.val() as Record<
      string,
      Record<string, PresenceNode>
    > | null;

    if (!presenceRoot) {
      logger.info("sweepSignalLostSessions: No presence nodes found.");
      return;
    }

    let inspectedCount = 0;
    let autoEndedCount = 0;

    for (const [enterpriseId, enterprisePresence] of Object.entries(
      presenceRoot,
    )) {
      for (const [userId, presence] of Object.entries(
        enterprisePresence ?? {},
      )) {
        inspectedCount++;

        const status = presence?.status;

        // Skip offline/irrelevant statuses
        if (!status || status === "offline") {
          continue;
        }

        // For signal_lost: check signalLostAt age
        // For active/break: check lastSeen (heartbeat) staleness
        let isStale = false;
        let effectiveStaleTime = now;

        if (status === "signal_lost" && presence.signalLostAt) {
          const signalLostAgeMs = now - presence.signalLostAt;
          if (signalLostAgeMs >= SIGNAL_LOST_MAX_AGE_MS) {
            isStale = true;
            effectiveStaleTime = presence.signalLostAt;
          }
        } else if (status === "active" || status === "break") {
          // Stale heartbeat: lastSeen > 1 hour ago means service is dead
          const lastSeen = presence.lastSeen ?? 0;
          const lastSeenAgeMs = now - lastSeen;
          if (lastSeen > 0 && lastSeenAgeMs >= SIGNAL_LOST_MAX_AGE_MS) {
            isStale = true;
            effectiveStaleTime = lastSeen;
          }
        }

        if (!isStale) {
          continue;
        }

        // Re-check latest presence to avoid race conditions
        const latestPresenceSnap = await rtdb
          .ref(`presence/${enterpriseId}/${userId}`)
          .get();
        const latestPresence = latestPresenceSnap.val() as PresenceNode | null;
        if (!latestPresence) {
          continue;
        }
        // If status changed since we read, skip
        if (latestPresence.status === "offline") {
          continue;
        }
        // Revalidate staleness with latest data
        const latestLastSeen = latestPresence.lastSeen ?? 0;
        if (latestLastSeen > 0 && now - latestLastSeen < SIGNAL_LOST_MAX_AGE_MS) {
          continue;
        }

        let sessionRef: admin.firestore.DocumentReference | null = null;
        if (latestPresence.currentSessionId) {
          sessionRef = db
            .collection("sessions")
            .doc(latestPresence.currentSessionId);
        } else {
          const activeSessionSnap = await db
            .collection("sessions")
            .where("enterpriseId", "==", enterpriseId)
            .where("employeeId", "==", userId)
            .where("status", "==", "active")
            .limit(1)
            .get();
          if (!activeSessionSnap.empty) {
            sessionRef = activeSessionSnap.docs[0].ref;
          }
        }

        if (!sessionRef) {
          continue;
        }

        const autoEnded = await db.runTransaction(async (tx) => {
          const sessionSnap = await tx.get(sessionRef!);
          if (!sessionSnap.exists) {
            return null;
          }

          const session = sessionSnap.data() as SessionDoc;
          if (session.status !== "active") {
            return null;
          }

          const effectiveSignalLostAt = effectiveStaleTime;
          const startTimeMs =
            session.startTime?.toMillis() ?? effectiveSignalLostAt;
          const totalDurationSecs = Math.max(
            0,
            Math.floor((effectiveSignalLostAt - startTimeMs) / 1000),
          );

          tx.update(sessionRef!, {
            endTime: admin.firestore.Timestamp.fromMillis(
              effectiveSignalLostAt,
            ),
            status: "auto_ended",
            totalDuration: totalDurationSecs,
            totalDistance: session.totalDistance ?? 0,
            photosCount: session.photosCount ?? 0,
            tasksCompleted: session.tasksCompleted ?? 0,
            notes: "Auto-ended due to lost connection.",
            autoEndReason: "signal_lost",
            autoEndSource: "signal_lost_sweeper",
            locationLostAt: admin.firestore.Timestamp.fromMillis(
              effectiveSignalLostAt,
            ),
          });

          const endTimestamp = admin.firestore.Timestamp.fromMillis(
            effectiveSignalLostAt,
          );
          const endDate = new Date(effectiveSignalLostAt + 5.5 * 60 * 60 * 1000);
          const dateStr = endDate.toISOString().slice(0, 10);

          const activityRef = db.collection("activityLogs").doc(
            `session_auto_ended_${sessionRef!.id}`
          );
          tx.set(activityRef, {
            enterpriseId,
            employeeId: userId,
            sessionId: sessionRef!.id,
            orgId: enterpriseId,
            type: "session_end",
            title: "Session Auto-Ended",
            detail: "Your session was auto-ended due to lost connection.",
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
            date: dateStr,
            payload: {
              endTime: endTimestamp,
              durationSeconds: totalDurationSecs,
              distanceKm: session.totalDistance ?? 0,
              endReason: "auto_ended_by_sweeper",
            },
            metadata: {
              reason: "signal_lost",
              source: "signal_lost_sweeper",
              signalLostAt: effectiveSignalLostAt,
              staleAgeMs: now - effectiveStaleTime,
            },
          }, { merge: true });

          return {
            sessionId: sessionRef!.id,
            totalDurationSecs,
          };
        });

        if (!autoEnded) {
          continue;
        }

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
          sendNotification({
            userId,
            title: "Session Auto-Ended",
            body: "Your session was automatically ended after 1 hour of no signal.",
            type: "alert",
            data: {
              action: "SESSION_AUTO_ENDED",
              status: "auto_ended",
              sessionId: autoEnded.sessionId,
              employeeId: userId,
            },
          }),
        ]);

        autoEndedCount++;
        logger.info("sweepSignalLostSessions: Auto-ended session.", {
          enterpriseId,
          userId,
          sessionId: autoEnded.sessionId,
          presenceStatus: status,
          effectiveStaleTime: effectiveStaleTime,
          staleAgeMs: now - effectiveStaleTime,
        });
      }
    }

    logger.info("sweepSignalLostSessions: Completed run.", {
      inspectedCount,
      autoEndedCount,
    });
  },
);
