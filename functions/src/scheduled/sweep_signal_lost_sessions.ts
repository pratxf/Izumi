import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions/v2";
import * as admin from "firebase-admin";
import { sendNotification } from "../utils/send_notification";

const SIGNAL_LOST_MAX_AGE_MS = 15 * 60 * 1000; // 15 minutes
const MAX_SESSION_DURATION_MS = 16 * 60 * 60 * 1000; // 16 hours

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
    schedule: "*/10 * * * *",
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
          // Check multiple staleness signals — if ALL are stale, end the session
          const presenceLastSeen = presence.lastSeen ?? 0;

          // Also check sessionHeartbeat and liveLocations for freshness
          let heartbeatLastSeen = 0;
          let liveLocationUpdatedAt = 0;
          try {
            const hbSnap = await rtdb
              .ref(`sessionHeartbeat/${enterpriseId}/${userId}/lastSeen`)
              .get();
            heartbeatLastSeen = (hbSnap.val() as number) ?? 0;
          } catch (_) {}
          try {
            const llSnap = await rtdb
              .ref(`liveLocations/${enterpriseId}/${userId}/updatedAt`)
              .get();
            liveLocationUpdatedAt = (llSnap.val() as number) ?? 0;
          } catch (_) {}

          // Use the most recent signal from any source
          const mostRecent = Math.max(
            presenceLastSeen,
            heartbeatLastSeen,
            liveLocationUpdatedAt,
          );
          const mostRecentAgeMs = now - mostRecent;

          if (mostRecent > 0 && mostRecentAgeMs >= SIGNAL_LOST_MAX_AGE_MS) {
            isStale = true;
            effectiveStaleTime = mostRecent;
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
        // Revalidate: check all freshness signals with latest data
        let latestMostRecent = latestPresence.lastSeen ?? 0;
        try {
          const hbSnap2 = await rtdb
            .ref(`sessionHeartbeat/${enterpriseId}/${userId}/lastSeen`)
            .get();
          const hb2 = (hbSnap2.val() as number) ?? 0;
          if (hb2 > latestMostRecent) latestMostRecent = hb2;
        } catch (_) {}
        try {
          const llSnap2 = await rtdb
            .ref(`liveLocations/${enterpriseId}/${userId}/updatedAt`)
            .get();
          const ll2 = (llSnap2.val() as number) ?? 0;
          if (ll2 > latestMostRecent) latestMostRecent = ll2;
        } catch (_) {}
        // Only skip if we have a RECENT signal — zero means no data = definitely stale
        if (latestMostRecent > 0 && (now - latestMostRecent) < SIGNAL_LOST_MAX_AGE_MS) {
          continue;
        }
        // If latestMostRecent is 0, fall through — no heartbeat data means stale

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
          if (session.status !== "active" && session.status !== "signal_lost") {
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

    // ── Force-end sessions exceeding 16 hours ──
    let forceEndedCount = 0;
    const maxDurationCutoff = admin.firestore.Timestamp.fromMillis(
      now - MAX_SESSION_DURATION_MS,
    );
    const [activeStale, signalLostStale] = await Promise.all([
      db.collection("sessions")
        .where("status", "==", "active")
        .where("startTime", "<", maxDurationCutoff)
        .get(),
      db.collection("sessions")
        .where("status", "==", "signal_lost")
        .where("startTime", "<", maxDurationCutoff)
        .get(),
    ]);
    const allStaleDocs = [...activeStale.docs, ...signalLostStale.docs];

    for (const sessionDoc of allStaleDocs) {
      const session = sessionDoc.data() as SessionDoc;
      const startTimeMs = session.startTime?.toMillis() ?? now;
      const totalDurationSecs = Math.max(
        0,
        Math.floor((now - startTimeMs) / 1000),
      );

      await sessionDoc.ref.update({
        endTime: admin.firestore.FieldValue.serverTimestamp(),
        status: "auto_ended",
        totalDuration: totalDurationSecs,
        totalDistance: session.totalDistance ?? 0,
        photosCount: session.photosCount ?? 0,
        tasksCompleted: session.tasksCompleted ?? 0,
        notes: "Auto-ended: exceeded maximum session duration (16 hours).",
        autoEndReason: "exceeded_max_duration",
        autoEndSource: "signal_lost_sweeper",
      });

      const activityRef = db.collection("activityLogs").doc(
        `session_auto_ended_${sessionDoc.id}`,
      );
      await activityRef.set({
        enterpriseId: session.enterpriseId,
        employeeId: session.employeeId,
        sessionId: sessionDoc.id,
        orgId: session.enterpriseId,
        type: "session_end",
        title: "Session Auto-Ended",
        detail: "Session exceeded maximum duration (16 hours).",
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        metadata: {
          reason: "exceeded_max_duration",
          source: "signal_lost_sweeper",
        },
      }, { merge: true });

      // Clean up RTDB
      if (session.enterpriseId && session.employeeId) {
        await Promise.all([
          rtdb.ref(`presence/${session.enterpriseId}/${session.employeeId}`).set({
            status: "offline",
            lastSeen: admin.database.ServerValue.TIMESTAMP,
            currentSessionId: null,
          }),
          rtdb.ref(`activeStats/${session.enterpriseId}/${session.employeeId}`).remove(),
          rtdb.ref(`sessionHeartbeat/${session.enterpriseId}/${session.employeeId}`).remove(),
          rtdb.ref(`liveLocations/${session.enterpriseId}/${session.employeeId}`).remove(),
        ]);
      }

      forceEndedCount++;
      logger.info("sweepSignalLostSessions: Force-ended stale session.", {
        sessionId: sessionDoc.id,
        employeeId: session.employeeId,
        enterpriseId: session.enterpriseId,
        durationHours: (totalDurationSecs / 3600).toFixed(1),
      });
    }

    // ── Clean up orphaned RTDB nodes ──
    // activeStats/sessionHeartbeat/liveLocations may survive if onDestroy
    // ended the Firestore session but failed to remove RTDB nodes.
    let orphanCleanedCount = 0;
    const activeStatsSnap = await rtdb.ref("activeStats").get();
    const activeStatsRoot = activeStatsSnap.val() as Record<
      string,
      Record<string, unknown>
    > | null;

    if (activeStatsRoot) {
      for (const [eid, employees] of Object.entries(activeStatsRoot ?? {})) {
        const cleanupUpdates: Record<string, null> = {};

        for (const empId of Object.keys(employees ?? {})) {
          const activeSessionSnap = await db
            .collection("sessions")
            .where("enterpriseId", "==", eid)
            .where("employeeId", "==", empId)
            .where("status", "==", "active")
            .limit(1)
            .get();

          if (activeSessionSnap.empty) {
            // No active Firestore session — RTDB node is orphaned
            cleanupUpdates[`activeStats/${eid}/${empId}`] = null;
            cleanupUpdates[`sessionHeartbeat/${eid}/${empId}`] = null;
            cleanupUpdates[`liveLocations/${eid}/${empId}`] = null;
            orphanCleanedCount++;
            logger.info("sweepSignalLostSessions: Cleaning orphaned RTDB nodes.", {
              enterpriseId: eid,
              employeeId: empId,
            });
          }
        }

        if (Object.keys(cleanupUpdates).length > 0) {
          await rtdb.ref().update(cleanupUpdates);
        }
      }
    }

    logger.info("sweepSignalLostSessions: Completed run.", {
      inspectedCount,
      autoEndedCount,
      forceEndedCount,
      orphanCleanedCount,
    });
  },
);
