/**
 * onPresenceOffline - RTDB Trigger
 *
 * Auto-ends active sessions only when:
 * 1) Presence becomes offline, and
 * 2) Session heartbeat is stale (>= 4 hours).
 *
 * This avoids ending sessions for users whose app is still running
 * in the background.
 */

import { onValueWritten } from "firebase-functions/v2/database";
import * as admin from "firebase-admin";
import { logger } from "firebase-functions/v2";

const HEARTBEAT_STALE_MS = 60 * 60 * 1000;

type PresenceRecord = {
  status?: string;
  lastSeen?: number;
  currentSessionId?: string | null;
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

    if (!after || after.status !== "offline") return;
    if (before?.status === "offline") return;

    const db = admin.firestore();
    const rtdb = admin.database();

    // Recheck current presence to avoid race with reconnect.
    const latestPresenceSnap = await rtdb
      .ref(`presence/${enterpriseId}/${userId}`)
      .get();
    const latestPresence = latestPresenceSnap.val() as PresenceRecord | null;
    if (!latestPresence || latestPresence.status !== "offline") return;

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
    if (ageMs < HEARTBEAT_STALE_MS) {
      logger.info("onPresenceOffline: Heartbeat fresh; no auto-end.", {
        enterpriseId,
        userId,
        sessionId,
        heartbeatAgeMs: ageMs,
      });
      return;
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
