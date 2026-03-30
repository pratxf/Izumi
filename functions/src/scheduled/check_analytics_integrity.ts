import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions/v2";
import * as admin from "firebase-admin";

const LOOKBACK_DAYS = 7;
const RECENT_LOCATION_GRACE_MS = 30 * 60 * 1000;

type SessionDoc = {
  status?: string;
  employeeId?: string;
  enterpriseId?: string;
  startTime?: admin.firestore.Timestamp;
};

type TaskDoc = {
  employeeId?: string;
  assignedTo?: string;
  enterpriseId?: string;
  status?: string;
  createdAt?: admin.firestore.Timestamp;
  updatedAt?: admin.firestore.Timestamp;
};

export const checkAnalyticsIntegrity = onSchedule(
  {
    schedule: "0 */6 * * *",
    timeZone: "Asia/Kolkata",
    region: "asia-south1",
    retryCount: 1,
    timeoutSeconds: 300,
    memory: "512MiB",
  },
  async () => {
    const db = admin.firestore();
    const now = Date.now();
    const lookbackStart = admin.firestore.Timestamp.fromMillis(
      now - LOOKBACK_DAYS * 24 * 60 * 60 * 1000
    );

    const missingStartLogs: string[] = [];
    const missingEndLogs: string[] = [];
    const missingPhotoLogs: string[] = [];
    const missingTaskStartedLogs: string[] = [];
    const missingTaskCompletedLogs: string[] = [];
    const activeSessionsWithoutRecentLocation: string[] = [];

    const sessionsSnap = await db
      .collection("sessions")
      .where("startTime", ">=", lookbackStart)
      .get();

    for (const doc of sessionsSnap.docs) {
      const sessionId = doc.id;
      const session = doc.data() as SessionDoc;

      const startLog = await db
        .collection("activityLogs")
        .doc(`session_started_${sessionId}`)
        .get();
      if (!startLog.exists) {
        missingStartLogs.push(sessionId);
      }

      if (session.status === "completed" || session.status === "auto_ended") {
        const endedLogId =
          session.status === "auto_ended" ?
            `session_auto_ended_${sessionId}` :
            `session_ended_${sessionId}`;
        const endedLog = await db.collection("activityLogs").doc(endedLogId).get();
        if (!endedLog.exists) {
          missingEndLogs.push(sessionId);
        }
      }

      if (session.status === "active") {
        const latestLocationLog = await db
          .collection("activityLogs")
          .where("sessionId", "==", sessionId)
          .where("type", "==", "location_update")
          .orderBy("timestamp", "desc")
          .limit(1)
          .get();
        const latestTimestamp =
          latestLocationLog.empty ?
            null :
            latestLocationLog.docs[0].get("timestamp") as
              | admin.firestore.Timestamp
              | undefined;
        const ageMs = latestTimestamp ? now - latestTimestamp.toMillis() : null;
        if (ageMs == null || ageMs > RECENT_LOCATION_GRACE_MS) {
          activeSessionsWithoutRecentLocation.push(sessionId);
        }
      }
    }

    const photosSnap = await db
      .collection("photos")
      .where("timestamp", ">=", lookbackStart)
      .get();
    for (const doc of photosSnap.docs) {
      const logSnap = await db
        .collection("activityLogs")
        .doc(`photo_captured_${doc.id}`)
        .get();
      if (!logSnap.exists) {
        missingPhotoLogs.push(doc.id);
      }
    }

    const tasksSnap = await db
      .collection("tasks")
      .where("createdAt", ">=", lookbackStart)
      .get();
    for (const doc of tasksSnap.docs) {
      const task = doc.data() as TaskDoc;
      const startLog = await db
        .collection("activityLogs")
        .doc(`task_started_${doc.id}`)
        .get();
      if (!startLog.exists) {
        missingTaskStartedLogs.push(doc.id);
      }

      if (task.status === "completed") {
        const completedLog = await db
          .collection("activityLogs")
          .doc(`task_completed_${doc.id}`)
          .get();
        if (!completedLog.exists) {
          missingTaskCompletedLogs.push(doc.id);
        }
      }
    }

    logger.info("checkAnalyticsIntegrity: completed", {
      lookbackDays: LOOKBACK_DAYS,
      sessionsScanned: sessionsSnap.size,
      photosScanned: photosSnap.size,
      tasksScanned: tasksSnap.size,
      missingStartLogs: missingStartLogs.length,
      missingEndLogs: missingEndLogs.length,
      missingPhotoLogs: missingPhotoLogs.length,
      missingTaskStartedLogs: missingTaskStartedLogs.length,
      missingTaskCompletedLogs: missingTaskCompletedLogs.length,
      activeSessionsWithoutRecentLocation:
        activeSessionsWithoutRecentLocation.length,
    });

    if (
      missingStartLogs.length > 0 ||
      missingEndLogs.length > 0 ||
      missingPhotoLogs.length > 0 ||
      missingTaskStartedLogs.length > 0 ||
      missingTaskCompletedLogs.length > 0 ||
      activeSessionsWithoutRecentLocation.length > 0
    ) {
      logger.warn("checkAnalyticsIntegrity: inconsistencies detected", {
        missingStartLogs: missingStartLogs.slice(0, 20),
        missingEndLogs: missingEndLogs.slice(0, 20),
        missingPhotoLogs: missingPhotoLogs.slice(0, 20),
        missingTaskStartedLogs: missingTaskStartedLogs.slice(0, 20),
        missingTaskCompletedLogs: missingTaskCompletedLogs.slice(0, 20),
        activeSessionsWithoutRecentLocation:
          activeSessionsWithoutRecentLocation.slice(0, 20),
      });
    }
  }
);
