/**
 * migrateHistoricalAnalytics - HTTPS Callable
 *
 * Backfills historical analytics data into the modern activityLogs collection
 * from older session and photo documents.
 *
 * This is intended as an admin-only one-time migration so the analytics detail
 * screen can rely on activityLogs without UI-level reconstruction logic.
 */

import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import {logger} from "firebase-functions/v2";

type SessionStatus = "active" | "completed" | "auto_ended";

interface SessionDocument {
  enterpriseId: string;
  employeeId: string;
  startTime?: admin.firestore.Timestamp;
  endTime?: admin.firestore.Timestamp;
  status?: SessionStatus;
  totalDuration?: number;
  totalDistance?: number;
  photosCount?: number;
  tasksCompleted?: number;
}

interface PhotoDocument {
  enterpriseId: string;
  employeeId: string;
  sessionId?: string;
  timestamp?: admin.firestore.Timestamp;
  location?: string;
  latitude?: number;
  longitude?: number;
  category?: string;
  customerName?: string;
}

interface SessionLocationDocument {
  latitude?: number;
  longitude?: number;
  address?: string;
  timestamp?: admin.firestore.Timestamp;
  type?: string;
  title?: string;
}

interface TaskDocument {
  enterpriseId: string;
  assignedTo: string;
  assignedBy?: string;
  title?: string;
  type?: "task" | "followup";
  priority?: "high" | "medium" | "low";
  status?: "pending" | "completed";
  createdAt?: admin.firestore.Timestamp;
  completedAt?: admin.firestore.Timestamp;
}

type MigrationResult = {
  dryRun: boolean;
  sessionsScanned: number;
  sessionsWithMissingStart: number;
  startLogsCreated: number;
  endLogsCreated: number;
  photoLogsCreated: number;
  locationLogsCreated: number;
  taskStartLogsCreated: number;
  taskCompletedLogsCreated: number;
  skippedExistingLogs: number;
  batchCommits: number;
};

const REGION = "asia-south1";
const BATCH_LIMIT = 400;

function assertAdmin(
  request: CallableRequest<unknown>,
): {enterpriseId: string} {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be authenticated.");
  }

  const callerRoles = request.auth.token.roles as string[] | undefined;
  const callerRole = request.auth.token.activeRole || request.auth.token.role;
  if (!(callerRoles && callerRoles.includes("admin")) && callerRole !== "admin") {
    throw new HttpsError("permission-denied", "Only admins can run this.");
  }

  const enterpriseId = request.auth.token.enterpriseId as string | undefined;
  if (!enterpriseId) {
    throw new HttpsError("failed-precondition", "No enterpriseId in claims.");
  }

  return {enterpriseId};
}

function buildSessionStartLog(
  sessionId: string,
  session: SessionDocument,
): Record<string, unknown> | null {
  if (!session.startTime) return null;

  return {
    enterpriseId: session.enterpriseId,
    employeeId: session.employeeId,
    sessionId,
    type: "session_started",
    title: "Session Started",
    detail: "Field session started",
    timestamp: session.startTime,
    metadata: {
      source: "historical_session_migration",
      migratedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
  };
}

function buildSessionEndLog(
  sessionId: string,
  session: SessionDocument,
): Record<string, unknown> | null {
  if (!session.endTime) return null;

  const isAutoEnded = session.status === "auto_ended";
  const totalDuration = session.totalDuration ?? 0;
  const hours = Math.floor(totalDuration / 3600);
  const minutes = Math.floor((totalDuration % 3600) / 60);
  const durationText = hours > 0 ? `${hours}h ${minutes}m` : `${minutes}m`;

  return {
    enterpriseId: session.enterpriseId,
    employeeId: session.employeeId,
    sessionId,
    type: isAutoEnded ? "session_auto_ended" : "session_ended",
    title: isAutoEnded ? "Session Auto Ended" : "Session Ended",
    detail: `Duration: ${durationText}`,
    timestamp: session.endTime,
    metadata: {
      source: "historical_session_migration",
      migratedAt: admin.firestore.FieldValue.serverTimestamp(),
      totalDistance: session.totalDistance ?? 0,
      photosCount: session.photosCount ?? 0,
      tasksCompleted: session.tasksCompleted ?? 0,
    },
  };
}

function buildPhotoLog(
  photoId: string,
  photo: PhotoDocument,
): Record<string, unknown> | null {
  if (!photo.timestamp) return null;

  return {
    enterpriseId: photo.enterpriseId,
    employeeId: photo.employeeId,
    sessionId: photo.sessionId ?? null,
    type: "photo_captured",
    title: "Photo Captured",
    detail: photo.customerName?.trim() ||
      photo.location?.trim() ||
      "Work proof photo captured",
    timestamp: photo.timestamp,
    metadata: {
      source: "historical_photo_migration",
      migratedAt: admin.firestore.FieldValue.serverTimestamp(),
      photoId,
      category: photo.category ?? null,
      latitude: photo.latitude ?? null,
      longitude: photo.longitude ?? null,
      location: photo.location ?? null,
    },
  };
}

function buildLocationLog(
  sessionId: string,
  locationId: string,
  session: SessionDocument,
  location: SessionLocationDocument,
): Record<string, unknown> | null {
  if (!location.timestamp) return null;

  const rawType = (location.type || "location_update").trim();
  let type = "location_update";
  if (rawType === "location_lost" || rawType === "location_recovered") {
    type = rawType;
  }

  const title = location.title?.trim() ||
    location.address?.trim() ||
    "Location update";

  return {
    enterpriseId: session.enterpriseId,
    employeeId: session.employeeId,
    sessionId,
    type,
    title,
    detail: location.address?.trim() || title,
    timestamp: location.timestamp,
    metadata: {
      source: "historical_location_migration",
      migratedAt: admin.firestore.FieldValue.serverTimestamp(),
      locationId,
      rawType,
      latitude: location.latitude ?? null,
      longitude: location.longitude ?? null,
      address: location.address ?? null,
    },
  };
}

function buildTaskStartedLog(
  taskId: string,
  task: TaskDocument,
): Record<string, unknown> | null {
  if (!task.createdAt || !task.enterpriseId || !task.assignedTo) return null;

  return {
    enterpriseId: task.enterpriseId,
    employeeId: task.assignedTo,
    type: "task_started",
    title: "New Task Assigned",
    detail: (task.title?.trim().length ?? 0) > 0 ?
      `"${task.title!.trim()}" assigned` :
      "Task assigned",
    timestamp: task.createdAt,
    metadata: {
      source: "historical_task_migration",
      migratedAt: admin.firestore.FieldValue.serverTimestamp(),
      taskId,
      taskType: task.type ?? "task",
      priority: task.priority ?? "medium",
      assignedBy: task.assignedBy ?? null,
    },
  };
}

function buildTaskCompletedLog(
  taskId: string,
  task: TaskDocument,
): Record<string, unknown> | null {
  if (!task.completedAt || !task.enterpriseId || !task.assignedTo) return null;

  return {
    enterpriseId: task.enterpriseId,
    employeeId: task.assignedTo,
    type: "task_completed",
    title: "Task Completed",
    detail: (task.title?.trim().length ?? 0) > 0 ?
      `"${task.title!.trim()}" completed` :
      "Task completed",
    timestamp: task.completedAt,
    metadata: {
      source: "historical_task_migration",
      migratedAt: admin.firestore.FieldValue.serverTimestamp(),
      taskId,
      taskType: task.type ?? "task",
      priority: task.priority ?? "medium",
      assignedBy: task.assignedBy ?? null,
    },
  };
}

export const migrateHistoricalAnalytics = onCall(
  {region: REGION, timeoutSeconds: 540, memory: "512MiB"},
  async (request): Promise<MigrationResult> => {
    const {enterpriseId} = assertAdmin(request);
    const data = (request.data || {}) as {dryRun?: boolean};
    const dryRun = data.dryRun ?? true;

    const db = admin.firestore();
    const sessionsSnapshot = await db
      .collection("sessions")
      .where("enterpriseId", "==", enterpriseId)
      .get();

    let batch = db.batch();
    let pendingWrites = 0;
    let batchCommits = 0;
    let sessionsWithMissingStart = 0;
    let startLogsCreated = 0;
    let endLogsCreated = 0;
    let photoLogsCreated = 0;
    let locationLogsCreated = 0;
    let taskStartLogsCreated = 0;
    let taskCompletedLogsCreated = 0;
    let skippedExistingLogs = 0;

    const flushBatch = async () => {
      if (dryRun || pendingWrites == 0) return;
      await batch.commit();
      batch = db.batch();
      pendingWrites = 0;
      batchCommits++;
    };

    for (const sessionDoc of sessionsSnapshot.docs) {
      const sessionId = sessionDoc.id;
      const session = sessionDoc.data() as SessionDocument;

      if (!session.employeeId || !session.enterpriseId) continue;

      const startLogId = `session_started_${sessionId}`;
      const endLogId = `session_ended_${sessionId}`;
      const autoEndLogId = `session_auto_ended_${sessionId}`;

      const [startLogSnap, endLogSnap, autoEndLogSnap, photosSnapshot, locationsSnapshot] =
        await Promise.all([
          db.collection("activityLogs").doc(startLogId).get(),
          db.collection("activityLogs").doc(endLogId).get(),
          db.collection("activityLogs").doc(autoEndLogId).get(),
          db.collection("photos")
            .where("sessionId", "==", sessionId)
            .get(),
          db.collection("sessions")
            .doc(sessionId)
            .collection("locations")
            .get(),
        ]);

      const startLog = buildSessionStartLog(sessionId, session);
      if (startLog) {
        if (startLogSnap.exists) {
          skippedExistingLogs++;
        } else if (!dryRun) {
          batch.set(db.collection("activityLogs").doc(startLogId), startLog);
          pendingWrites++;
          startLogsCreated++;
        } else {
          startLogsCreated++;
        }
      } else {
        sessionsWithMissingStart++;
      }

      const endLog = buildSessionEndLog(sessionId, session);
      if (endLog) {
        const targetId = session.status === "auto_ended" ? autoEndLogId : endLogId;
        const exists = session.status === "auto_ended" ?
          autoEndLogSnap.exists :
          endLogSnap.exists;
        if (exists) {
          skippedExistingLogs++;
        } else if (!dryRun) {
          batch.set(db.collection("activityLogs").doc(targetId), endLog);
          pendingWrites++;
          endLogsCreated++;
        } else {
          endLogsCreated++;
        }
      }

      for (const photoDoc of photosSnapshot.docs) {
        const photoId = photoDoc.id;
        const activityLogId = `photo_captured_${photoId}`;
        const activityDoc = await db.collection("activityLogs").doc(activityLogId).get();
        if (activityDoc.exists) {
          skippedExistingLogs++;
          continue;
        }

        const photoLog = buildPhotoLog(photoId, photoDoc.data() as PhotoDocument);
        if (!photoLog) continue;

        if (!dryRun) {
          batch.set(db.collection("activityLogs").doc(activityLogId), photoLog);
          pendingWrites++;
        }
        photoLogsCreated++;

        if (pendingWrites >= BATCH_LIMIT) {
          await flushBatch();
        }
      }

      for (const locationDoc of locationsSnapshot.docs) {
        const locationLogId = `session_location_${sessionId}_${locationDoc.id}`;
        const existingLocationLog = await db
          .collection("activityLogs")
          .doc(locationLogId)
          .get();
        if (existingLocationLog.exists) {
          skippedExistingLogs++;
          continue;
        }

        const locationLog = buildLocationLog(
          sessionId,
          locationDoc.id,
          session,
          locationDoc.data() as SessionLocationDocument,
        );
        if (!locationLog) continue;

        if (!dryRun) {
          batch.set(db.collection("activityLogs").doc(locationLogId), locationLog);
          pendingWrites++;
        }
        locationLogsCreated++;

        if (pendingWrites >= BATCH_LIMIT) {
          await flushBatch();
        }
      }

      if (pendingWrites >= BATCH_LIMIT) {
        await flushBatch();
      }
    }

    const tasksSnapshot = await db
      .collection("tasks")
      .where("enterpriseId", "==", enterpriseId)
      .get();

    for (const taskDoc of tasksSnapshot.docs) {
      const task = taskDoc.data() as TaskDocument;
      const taskId = taskDoc.id;

      const taskStartedId = `task_started_${taskId}`;
      const taskCompletedId = `task_completed_${taskId}`;

      const [taskStartedSnap, taskCompletedSnap] = await Promise.all([
        db.collection("activityLogs").doc(taskStartedId).get(),
        db.collection("activityLogs").doc(taskCompletedId).get(),
      ]);

      const taskStartedLog = buildTaskStartedLog(taskId, task);
      if (taskStartedLog) {
        if (taskStartedSnap.exists) {
          skippedExistingLogs++;
        } else if (!dryRun) {
          batch.set(db.collection("activityLogs").doc(taskStartedId), taskStartedLog);
          pendingWrites++;
          taskStartLogsCreated++;
        } else {
          taskStartLogsCreated++;
        }
      }

      const taskCompletedLog = buildTaskCompletedLog(taskId, task);
      if (taskCompletedLog) {
        if (taskCompletedSnap.exists) {
          skippedExistingLogs++;
        } else if (!dryRun) {
          batch.set(
            db.collection("activityLogs").doc(taskCompletedId),
            taskCompletedLog,
          );
          pendingWrites++;
          taskCompletedLogsCreated++;
        } else {
          taskCompletedLogsCreated++;
        }
      }

      if (pendingWrites >= BATCH_LIMIT) {
        await flushBatch();
      }
    }

    await flushBatch();

    const result: MigrationResult = {
      dryRun,
      sessionsScanned: sessionsSnapshot.size,
      sessionsWithMissingStart,
      startLogsCreated,
      endLogsCreated,
      photoLogsCreated,
      locationLogsCreated,
      taskStartLogsCreated,
      taskCompletedLogsCreated,
      skippedExistingLogs,
      batchCommits,
    };

    logger.info("migrateHistoricalAnalytics completed.", {
      enterpriseId,
      ...result,
    });

    return result;
  },
);
