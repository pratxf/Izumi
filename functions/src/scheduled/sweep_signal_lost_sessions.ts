/**
 * sweepSignalLostSessions — Scheduled backup sweep.
 *
 * Runs every 10 minutes. Three responsibilities, in order:
 *
 *   1. Connectivity-aware session health pass. For each active session where
 *      presence is NOT active/break, apply this decision tree:
 *         - offline && changedAt < 8h  → keep alive, mark "offline_tracking"
 *         - offline && changedAt ≥ 8h  → silent FCM kick first; auto-end only
 *                                         if kick was already sent > 15 min ago
 *         - online && heartbeat ≥ 45m  → write "signal_lost", keep alive;
 *                                         WorkManager watchdog handles restart
 *         - no lastConnectivity hint   → same as online path above
 *
 *   2. Hard 16-hour cutoff for zombie sessions.
 *
 *   3. Orphaned RTDB cleanup.
 */

import {onSchedule} from "firebase-functions/v2/scheduler";
import {logger} from "firebase-functions/v2";
import * as admin from "firebase-admin";
import {sendNotification} from "../utils/send_notification";

const HEARTBEAT_STALE_FALLBACK_MS = 90 * 60 * 1000;
const HEARTBEAT_STALE_ONLINE_MS = 45 * 60 * 1000;
const OFFLINE_GRACE_MS = 8 * 60 * 60 * 1000;
const MAX_SESSION_DURATION_MS = 16 * 60 * 60 * 1000;
// How long to wait after sending a silent FCM kick before auto-ending.
// Must be >= one sweep cycle (10 min) so the device has a chance to respond.
const KICK_GRACE_MS = 15 * 60 * 1000;

type LastConnectivity = {
  state?: "online" | "offline";
  changedAt?: number;
};

type PresenceRecord = {
  status?: string;
  lastSeen?: number;
  currentSessionId?: string | null;
  lastConnectivity?: LastConnectivity;
};

type HeartbeatRecord = {
  sessionId?: string;
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
  kickSentAt?: admin.firestore.Timestamp;
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

    let autoEndedCount = 0;
    let keptCount = 0;
    let forceEndedCount = 0;
    let orphanCleanedCount = 0;

    // ── 1. Connectivity-aware auto-end pass ───────────────────────────────
    const activeSnap = await db
      .collection("sessions")
      .where("status", "==", "active")
      .get();

    const inspectedCount = activeSnap.size;

    for (const sessionDoc of activeSnap.docs) {
      const session = sessionDoc.data() as SessionDoc;
      const enterpriseId = session.enterpriseId;
      const userId = session.employeeId;
      if (!enterpriseId || !userId) continue;

      const [presenceSnap, heartbeatSnap] = await Promise.all([
        rtdb.ref(`presence/${enterpriseId}/${userId}`).get(),
        rtdb.ref(`sessionHeartbeat/${enterpriseId}/${userId}`).get(),
      ]);
      const presence = presenceSnap.val() as PresenceRecord | null;
      const heartbeat = heartbeatSnap.val() as HeartbeatRecord | null;

      // Presence is healthy → skip; the trigger owns that case.
      if (presence?.status === "active" || presence?.status === "break") {
        continue;
      }
      if (!heartbeat?.lastSeen) continue;
      if (heartbeat.sessionId && heartbeat.sessionId !== sessionDoc.id) continue;

      const heartbeatAgeMs = now - heartbeat.lastSeen;
      const lastConn = presence?.lastConnectivity;

      let shouldEnd = false;
      let reason = "";

      if (lastConn?.state === "offline" && lastConn.changedAt) {
        const offlineForMs = now - lastConn.changedAt;
        if (offlineForMs < OFFLINE_GRACE_MS) {
          if (presence?.status !== "offline_tracking") {
            await rtdb
              .ref(`presence/${enterpriseId}/${userId}/status`)
              .set("offline_tracking");
          }
          keptCount++;
          continue;
        }
        shouldEnd = true;
        reason = "offline_grace_exceeded";
      } else if (lastConn?.state === "online") {
        // Device has internet but heartbeat is stale — app process is dead.
        // Mark signal_lost so the dashboard reflects this, but keep the session
        // alive. WorkManager watchdog will attempt a restart. The 16h cutoff
        // below is the only auto-end for this path.
        if (heartbeatAgeMs >= HEARTBEAT_STALE_ONLINE_MS) {
          await rtdb
            .ref(`presence/${enterpriseId}/${userId}/status`)
            .set("signal_lost");
          keptCount++;
        }
        continue;
      } else {
        // No lastConnectivity hint (legacy client) — same policy as online path.
        if (heartbeatAgeMs >= HEARTBEAT_STALE_FALLBACK_MS) {
          await rtdb
            .ref(`presence/${enterpriseId}/${userId}/status`)
            .set("signal_lost");
          keptCount++;
        }
        continue;
      }

      if (!shouldEnd) continue;

      // ── Silent FCM kick before auto-ending (offline path only) ───────────
      // Send a high-priority data-only message to wake the device. If the app
      // responds and restarts tracking, the next sweep cycle will see the
      // heartbeat fresh and skip this session. Only auto-end if we already sent
      // a kick and the device still hasn't responded after KICK_GRACE_MS.
      const kickSentAt = (session as SessionDoc).kickSentAt?.toMillis();

      if (kickSentAt && (now - kickSentAt) < KICK_GRACE_MS) {
        keptCount++;
        logger.info("sweep: kick sent recently, waiting for device response.", {
          enterpriseId, userId, sessionId: sessionDoc.id,
          kickAgeMs: now - kickSentAt,
        });
        continue;
      }

      if (!kickSentAt) {
        // First time we're about to auto-end this session — send kick first.
        const userSnap = await db.collection("users").doc(userId).get();
        const fcmToken = userSnap.data()?.fcmToken as string | undefined;

        if (fcmToken) {
          try {
            await admin.messaging().send({
              token: fcmToken,
              android: {priority: "high", ttl: 60000},
              apns: {
                payload: {aps: {contentAvailable: true}},
                headers: {"apns-priority": "5"},
              },
              data: {
                action: "RESTART_TRACKING",
                sessionId: sessionDoc.id,
                enterpriseId,
                employeeId: userId,
              },
            });

            await sessionDoc.ref.update({
              kickSentAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            keptCount++;
            logger.info("sweep: silent kick sent, deferring auto-end.", {
              enterpriseId, userId, sessionId: sessionDoc.id,
            });
            continue;
          } catch (e) {
            logger.warn("sweep: FCM kick failed, proceeding to auto-end.", {
              userId, error: e instanceof Error ? e.message : String(e),
            });
            // Fall through to auto-end
          }
        }
        // No FCM token — fall through to auto-end immediately
      }
      // kickSentAt exists and KICK_GRACE_MS has expired — fall through to auto-end

      const autoEnded = await db.runTransaction(async (tx) => {
        const fresh = await tx.get(sessionDoc.ref);
        if (!fresh.exists) return null;
        const data = fresh.data() as SessionDoc;
        if (data.status !== "active") return null;

        const startTime = data.startTime?.toDate();
        const totalDurationSecs = startTime ?
          Math.max(0, Math.floor((now - startTime.getTime()) / 1000)) :
          0;

        tx.update(sessionDoc.ref, {
          endTime: admin.firestore.FieldValue.serverTimestamp(),
          status: "auto_ended",
          totalDuration: totalDurationSecs,
          totalDistance: data.totalDistance ?? 0,
          photosCount: data.photosCount ?? 0,
          tasksCompleted: data.tasksCompleted ?? 0,
          notes: `Auto-ended by sweep: ${reason}.`,
          autoEndReason: reason,
          autoEndSource: "sweep_signal_lost_sessions",
          kickSentAt: admin.firestore.FieldValue.delete(),
        });

        const activityRef = db.collection("activityLogs").doc();
        tx.set(activityRef, {
          enterpriseId,
          employeeId: userId,
          sessionId: sessionDoc.id,
          orgId: enterpriseId,
          type: "session_auto_ended",
          title: "Session Auto-Ended",
          detail: `Sweep auto-end (${reason}).`,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          metadata: {
            reason,
            source: "sweep_signal_lost_sessions",
            heartbeatAgeMs,
            lastConnectivityState: lastConn?.state ?? null,
            lastConnectivityChangedAt: lastConn?.changedAt ?? null,
          },
        });

        return {sessionId: sessionDoc.id};
      });

      if (!autoEnded) continue;

      await Promise.all([
        rtdb.ref(`activeStats/${enterpriseId}/${userId}`).remove(),
        rtdb.ref(`sessionHeartbeat/${enterpriseId}/${userId}`).remove(),
        rtdb.ref(`liveLocations/${enterpriseId}/${userId}`).remove(),
        rtdb.ref(`presence/${enterpriseId}/${userId}`).update({
          status: "offline",
          currentSessionId: null,
          lastSeen: admin.database.ServerValue.TIMESTAMP,
        }),
        sendNotification({
          userId,
          title: "Session Auto-Ended",
          body:
            "Your tracking session was automatically ended. " +
            "Please start a new session to resume tracking.",
          type: "alert",
          data: {
            action: "SESSION_AUTO_ENDED",
            status: "auto_ended",
            sessionId: autoEnded.sessionId,
            employeeId: userId,
            reason,
          },
        }).catch((e) => {
          logger.warn("sweepSignalLostSessions: FCM notify failed.", {
            userId,
            error: e instanceof Error ? e.message : String(e),
          });
        }),
      ]);

      autoEndedCount++;
      logger.info("sweepSignalLostSessions: session auto-ended.", {
        enterpriseId,
        userId,
        sessionId: sessionDoc.id,
        reason,
        heartbeatAgeMs,
      });
    }

    // ── 2. Hard 16-hour cutoff for zombie sessions ────────────────────────
    // Belt-and-suspenders: catches sessions that somehow keep their heartbeat
    // alive forever (e.g. stuck emulator, clock drift).
    const cutoff = admin.firestore.Timestamp.fromMillis(
      now - MAX_SESSION_DURATION_MS,
    );
    const [activeStale, signalLostStale] = await Promise.all([
      db.collection("sessions")
        .where("status", "==", "active")
        .where("startTime", "<", cutoff)
        .get(),
      db.collection("sessions")
        .where("status", "==", "signal_lost")
        .where("startTime", "<", cutoff)
        .get(),
    ]);
    const staleDocs = [...activeStale.docs, ...signalLostStale.docs];

    for (const sessionDoc of staleDocs) {
      const session = sessionDoc.data() as SessionDoc;
      const enterpriseId = session.enterpriseId;
      const userId = session.employeeId;
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
        autoEndSource: "sweep_signal_lost_sessions",
      });

      const activityRef = db.collection("activityLogs").doc(
        `session_auto_ended_${sessionDoc.id}`,
      );
      await activityRef.set({
        enterpriseId: enterpriseId ?? null,
        employeeId: userId ?? null,
        sessionId: sessionDoc.id,
        orgId: enterpriseId ?? null,
        type: "session_auto_ended",
        title: "Session Auto-Ended",
        detail: "Session exceeded maximum duration (16 hours).",
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        metadata: {
          reason: "exceeded_max_duration",
          source: "sweep_signal_lost_sessions",
          durationHours: (totalDurationSecs / 3600).toFixed(1),
        },
      }, {merge: true});

      if (enterpriseId && userId) {
        await Promise.all([
          rtdb.ref(`presence/${enterpriseId}/${userId}`).update({
            status: "offline",
            currentSessionId: null,
            lastSeen: admin.database.ServerValue.TIMESTAMP,
          }),
          rtdb.ref(`activeStats/${enterpriseId}/${userId}`).remove(),
          rtdb.ref(`sessionHeartbeat/${enterpriseId}/${userId}`).remove(),
          rtdb.ref(`liveLocations/${enterpriseId}/${userId}`).remove(),
          sendNotification({
            userId,
            title: "Session Auto-Ended",
            body:
              "Your session exceeded 16 hours and was automatically ended. " +
              "Please start a new session.",
            type: "alert",
            data: {
              action: "SESSION_AUTO_ENDED",
              status: "auto_ended",
              sessionId: sessionDoc.id,
              employeeId: userId,
              reason: "exceeded_max_duration",
            },
          }).catch((e) => {
            logger.warn("sweepSignalLostSessions: FCM notify failed.", {
              userId,
              error: e instanceof Error ? e.message : String(e),
            });
          }),
        ]);
      }

      forceEndedCount++;
      logger.info("sweepSignalLostSessions: force-ended stale session.", {
        sessionId: sessionDoc.id,
        enterpriseId,
        employeeId: userId,
        durationHours: (totalDurationSecs / 3600).toFixed(1),
      });
    }

    // ── 3. Orphaned RTDB node cleanup ─────────────────────────────────────
    // activeStats / sessionHeartbeat / liveLocations may survive if a session
    // end flow failed to remove them. A node is considered orphaned when the
    // corresponding Firestore session with status "active" no longer exists.
    try {
      const activeStatsSnap = await rtdb.ref("activeStats").get();
      const activeStatsRoot = activeStatsSnap.val() as Record<
        string,
        Record<string, unknown>
      > | null;

      if (activeStatsRoot) {
        for (const [eid, employees] of Object.entries(activeStatsRoot)) {
          const cleanupUpdates: Record<string, null> = {};

          for (const empId of Object.keys(employees ?? {})) {
            const activeSnap = await db
              .collection("sessions")
              .where("enterpriseId", "==", eid)
              .where("employeeId", "==", empId)
              .where("status", "==", "active")
              .limit(1)
              .get();

            if (activeSnap.empty) {
              cleanupUpdates[`activeStats/${eid}/${empId}`] = null;
              cleanupUpdates[`sessionHeartbeat/${eid}/${empId}`] = null;
              cleanupUpdates[`liveLocations/${eid}/${empId}`] = null;
              orphanCleanedCount++;
              logger.info(
                "sweepSignalLostSessions: cleaning orphaned RTDB nodes.",
                {enterpriseId: eid, employeeId: empId},
              );
            }
          }

          if (Object.keys(cleanupUpdates).length > 0) {
            await rtdb.ref().update(cleanupUpdates);
          }
        }
      }
    } catch (e) {
      logger.warn("sweepSignalLostSessions: orphan cleanup failed.", {
        error: e instanceof Error ? e.message : String(e),
      });
    }

    logger.info("sweepSignalLostSessions: run complete.", {
      inspectedCount,
      autoEndedCount,
      keptCount,
      forceEndedCount,
      orphanCleanedCount,
    });
  },
);
