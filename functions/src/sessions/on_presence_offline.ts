/**
 * onPresenceOffline - RTDB Trigger
 *
 * Keeps sessions alive aggressively. Only auto-ends when there is strong,
 * multi-signal evidence the session is unrecoverable. OEM kills and network
 * drops must NEVER auto-end a session prematurely.
 *
 * Decision tree (in order):
 *   1. presence.lastConnectivity.state == "offline" AND changedAt < 8h ago
 *      → KEEP ALIVE. Mark presence.status = "offline_tracking".
 *   2. presence.lastConnectivity.state == "offline" AND changedAt ≥ 8h ago
 *      → AUTO-END. Device has been unreachable for 8 hours.
 *   3. presence.lastConnectivity.state == "online" AND heartbeat stale ≥ 45m
 *      → Write signal_lost to presence and RETURN. Never auto-end here.
 *        The sweep (every 10 min) and WorkManager watchdog handle recovery.
 *        Hard 16h cutoff in the sweep is the only auto-end for this case.
 *   4. lastConnectivity field absent (older client)
 *      → Same as case 3: write signal_lost and return. No auto-end.
 */

import { onValueWritten } from "firebase-functions/v2/database";
import * as admin from "firebase-admin";
import { logger } from "firebase-functions/v2";

// Legacy fallback for clients that don't yet write lastConnectivity.
const HEARTBEAT_STALE_FALLBACK_MS = 90 * 60 * 1000;
// Stricter cutoff when we KNOW the device is online — a stale heartbeat with
// network connectivity means the app process itself is dead.
const HEARTBEAT_STALE_ONLINE_MS = 45 * 60 * 1000;
// Maximum time a session may stay alive after the device went offline. Beyond
// this, assume the device is genuinely lost / dead and end the session.
const OFFLINE_GRACE_MS = 8 * 60 * 60 * 1000;

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
};

export const onPresenceOffline = onValueWritten(
  {
    ref: "/presence/{enterpriseId}/{userId}",
    region: "asia-southeast1",
  },
  async (event) => {
    const enterpriseId = event.params.enterpriseId as string;
    const userId = event.params.userId as string;
    const before = event.data.before.val() as PresenceRecord | null;
    const after = event.data.after.val() as PresenceRecord | null;

    // Trigger only when status transitions INTO "offline".
    // signal_lost is now written more frequently by the sweep as a
    // "stale but alive" marker — re-triggering on every sweep write would
    // create a feedback loop. The sweep owns the signal_lost → auto-end path.
    const isTerminalish = (s?: string) => s === "offline";
    if (!after || !isTerminalish(after.status)) return;
    if (isTerminalish(before?.status)) return;

    const db = admin.firestore();
    const rtdb = admin.database();

    // Recheck current presence to avoid race with reconnect.
    const latestPresenceSnap = await rtdb
      .ref(`presence/${enterpriseId}/${userId}`)
      .get();
    const latestPresence = latestPresenceSnap.val() as PresenceRecord | null;
    if (!latestPresence || !isTerminalish(latestPresence.status)) return;

    const activeSessionSnap = await db
      .collection("sessions")
      .where("enterpriseId", "==", enterpriseId)
      .where("employeeId", "==", userId)
      .where("status", "==", "active")
      .limit(1)
      .get();

    if (activeSessionSnap.empty) return;

    const sessionRef = activeSessionSnap.docs[0].ref;
    const sessionId = sessionRef.id;

    const heartbeatSnap = await rtdb
      .ref(`sessionHeartbeat/${enterpriseId}/${userId}`)
      .get();
    const heartbeat = heartbeatSnap.val() as HeartbeatRecord | null;
    if (!heartbeat?.lastSeen) {
      logger.info("onPresenceOffline: Missing heartbeat; skipping auto-end.", {
        enterpriseId,
        userId,
        sessionId,
      });
      return;
    }

    if (heartbeat.sessionId && heartbeat.sessionId !== sessionId) {
      logger.info("onPresenceOffline: Heartbeat session mismatch; skipping.", {
        enterpriseId,
        userId,
        sessionId,
        heartbeatSessionId: heartbeat.sessionId,
      });
      return;
    }

    const ageMs = Date.now() - heartbeat.lastSeen;

    // Connectivity-aware decision tree. The presence node is what just
    // changed; re-read it (already done above as latestPresence) so we
    // get the freshest lastConnectivity hint.
    const lastConnectivity = latestPresence.lastConnectivity;
    const now = Date.now();

    if (lastConnectivity?.state === "offline" && lastConnectivity.changedAt) {
      const offlineForMs = now - lastConnectivity.changedAt;

      if (offlineForMs < OFFLINE_GRACE_MS) {
        // Employee went offline recently — keep tracking locally on device.
        // Surface this to admins as a distinct status so they don't mistake
        // it for a dead app.
        await rtdb.ref(`presence/${enterpriseId}/${userId}`).update({
          status: "offline_tracking",
        });
        logger.info(
          "onPresenceOffline: Device offline within grace; session kept alive.",
          {
            enterpriseId,
            userId,
            sessionId,
            offlineForMs,
            heartbeatAgeMs: ageMs,
          },
        );
        return;
      }
      // offlineForMs >= OFFLINE_GRACE_MS → fall through to auto-end.
      logger.info(
        "onPresenceOffline: Device offline beyond grace; auto-ending.",
        { enterpriseId, userId, sessionId, offlineForMs },
      );
    } else if (lastConnectivity?.state === "online") {
      // Device has internet but heartbeat is stale → app process is dead.
      // Write signal_lost so the dashboard shows the right status, but do NOT
      // auto-end. The WorkManager watchdog and sweep handle recovery.
      // The 16h hard cutoff in the sweep is the only auto-end for this path.
      if (ageMs >= HEARTBEAT_STALE_ONLINE_MS) {
        await rtdb.ref(`presence/${enterpriseId}/${userId}`).update({
          status: "signal_lost",
        });
        logger.info(
          "onPresenceOffline: online + stale heartbeat → signal_lost, kept alive.",
          { enterpriseId, userId, sessionId, heartbeatAgeMs: ageMs },
        );
      }
      return; // Never auto-end here.
    } else {
      // No lastConnectivity hint → legacy client. Same policy: mark signal_lost
      // and let the sweep / watchdog recover. No auto-end from this trigger.
      if (ageMs >= HEARTBEAT_STALE_FALLBACK_MS) {
        await rtdb.ref(`presence/${enterpriseId}/${userId}`).update({
          status: "signal_lost",
        });
        logger.info(
          "onPresenceOffline: no connectivity hint + stale heartbeat → signal_lost.",
          { enterpriseId, userId, sessionId, heartbeatAgeMs: ageMs },
        );
      }
      return; // Never auto-end here either.
    }

    await db.runTransaction(async (tx) => {
      const latestSessionSnap = await tx.get(sessionRef);
      if (!latestSessionSnap.exists) return;
      const latestSession = latestSessionSnap.data() as SessionDoc;
      if (latestSession.status !== "active") return;

      const startTime = latestSession.startTime?.toDate();
      const totalDurationSecs = startTime
        ? Math.max(0, Math.floor((Date.now() - startTime.getTime()) / 1000))
        : 0;

      tx.update(sessionRef, {
        endTime: admin.firestore.FieldValue.serverTimestamp(),
        status: "auto_ended",
        totalDuration: totalDurationSecs,
        totalDistance: latestSession.totalDistance ?? 0,
        photosCount: latestSession.photosCount ?? 0,
        tasksCompleted: latestSession.tasksCompleted ?? 0,
        notes: "Auto-ended by system due to app disconnect and stale heartbeat.",
        autoEndReason: "app_killed_or_disconnected",
        autoEndSource: "presence_disconnect",
      });

      const activityRef = db.collection("activityLogs").doc();
      tx.set(activityRef, {
        enterpriseId,
        employeeId: userId,
        sessionId,
        type: "session_auto_ended",
        title: "Session Auto-Ended",
        detail: "App disconnect detected with stale heartbeat.",
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        metadata: {
          reason: "app_killed_or_disconnected",
          source: "presence_disconnect",
          heartbeatLastSeen: heartbeat.lastSeen,
          heartbeatAgeMs: ageMs,
        },
      });
    });

    await Promise.all([
      rtdb.ref(`activeStats/${enterpriseId}/${userId}`).remove(),
      rtdb.ref(`sessionHeartbeat/${enterpriseId}/${userId}`).remove(),
    ]);

    logger.info("onPresenceOffline: Session auto-ended.", {
      enterpriseId,
      userId,
      sessionId,
      heartbeatAgeMs: ageMs,
    });
  }
);
