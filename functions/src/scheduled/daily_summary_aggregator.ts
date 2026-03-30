/**
 * dailySummaryAggregator - Scheduled Function
 *
 * Runs daily at 23:59 IST (18:29 UTC).
 * For each enterprise, queries all completed sessions for the current day,
 * aggregates statistics per employee, and creates/updates dailySummaries
 * documents.
 *
 * This serves as a safety net to ensure daily summaries are accurate even
 * if the onSessionComplete trigger missed or double-counted anything.
 */

import { onSchedule } from "firebase-functions/v2/scheduler";
import * as admin from "firebase-admin";
import { logger } from "firebase-functions/v2";

/** Shape of session document fields we need. */
interface SessionData {
  enterpriseId: string;
  employeeId: string;
  startTime: admin.firestore.Timestamp;
  endTime?: admin.firestore.Timestamp;
  status: string;
  totalDuration: number;
  totalDistance: number;
  photosCount: number;
  tasksCompleted: number;
}

/** Accumulated stats per employee for the day. */
interface EmployeeStats {
  enterpriseId: string;
  totalDuration: number;
  totalDistance: number;
  photosCount: number;
  tasksCompleted: number;
  locationsVisited: Set<string>;
  sessionIds: string[];
}

/**
 * Get the start and end of today in IST as Firestore Timestamps.
 * IST = UTC + 5:30.
 */
function getTodayBoundsIST(): {
  startOfDay: admin.firestore.Timestamp;
  endOfDay: admin.firestore.Timestamp;
  dateStr: string;
} {
  const now = new Date();
  const istOffsetMs = 330 * 60_000; // 5h30m in ms
  const utcMs = now.getTime() + now.getTimezoneOffset() * 60_000;
  const istNow = new Date(utcMs + istOffsetMs);

  const year = istNow.getFullYear();
  const month = istNow.getMonth(); // 0-based
  const day = istNow.getDate();

  // Start of today in IST -> convert back to UTC for Firestore
  const startIST = new Date(year, month, day, 0, 0, 0, 0);
  const startUTC = new Date(startIST.getTime() - istOffsetMs);

  // End of today in IST -> convert back to UTC
  const endIST = new Date(year, month, day, 23, 59, 59, 999);
  const endUTC = new Date(endIST.getTime() - istOffsetMs);

  const dateStr = `${year}-${String(month + 1).padStart(2, "0")}-${String(day).padStart(2, "0")}`;

  return {
    startOfDay: admin.firestore.Timestamp.fromDate(startUTC),
    endOfDay: admin.firestore.Timestamp.fromDate(endUTC),
    dateStr,
  };
}

export const dailySummaryAggregator = onSchedule(
  {
    // 23:59 IST = 18:29 UTC
    schedule: "29 18 * * *",
    timeZone: "Asia/Kolkata",
    region: "asia-south1",
    retryCount: 2,
    // Allow up to 5 minutes for large enterprises
    timeoutSeconds: 300,
    memory: "512MiB",
  },
  async (_event) => {
    logger.info("dailySummaryAggregator: Starting daily aggregation.");

    const db = admin.firestore();
    const { startOfDay, endOfDay, dateStr } = getTodayBoundsIST();

    logger.info("dailySummaryAggregator: Date range.", {
      dateStr,
      startOfDay: startOfDay.toDate().toISOString(),
      endOfDay: endOfDay.toDate().toISOString(),
    });

    // ── 1. Get all enterprises ───────────────────────────────────────────
    const enterprisesSnap = await db.collection("enterprises").get();

    if (enterprisesSnap.empty) {
      logger.info("dailySummaryAggregator: No enterprises found.");
      return;
    }

    let totalSummariesWritten = 0;

    for (const enterpriseDoc of enterprisesSnap.docs) {
      const enterpriseId = enterpriseDoc.id;

      logger.info("dailySummaryAggregator: Processing enterprise.", {
        enterpriseId,
      });

      // ── 2. Query all completed sessions for this enterprise today ──────
      const sessionsSnap = await db
        .collection("sessions")
        .where("enterpriseId", "==", enterpriseId)
        .where("status", "==", "completed")
        .where("startTime", ">=", startOfDay)
        .where("startTime", "<=", endOfDay)
        .get();

      if (sessionsSnap.empty) {
        logger.info(
          "dailySummaryAggregator: No completed sessions for enterprise.",
          { enterpriseId }
        );
        continue;
      }

      // ── 3. Aggregate stats per employee ────────────────────────────────
      const employeeStatsMap = new Map<string, EmployeeStats>();

      for (const sessionDoc of sessionsSnap.docs) {
        const session = sessionDoc.data() as SessionData;
        const employeeId = session.employeeId;

        if (!employeeStatsMap.has(employeeId)) {
          employeeStatsMap.set(employeeId, {
            enterpriseId,
            totalDuration: 0,
            totalDistance: 0,
            photosCount: 0,
            tasksCompleted: 0,
            locationsVisited: new Set<string>(),
            sessionIds: [],
          });
        }

        const stats = employeeStatsMap.get(employeeId)!;
        stats.totalDuration += session.totalDuration || 0;
        stats.totalDistance += session.totalDistance || 0;
        stats.photosCount += session.photosCount || 0;
        stats.tasksCompleted += session.tasksCompleted || 0;
        stats.sessionIds.push(sessionDoc.id);

        // Read locations visited from this session's subcollection
        try {
          const locationsSnap = await db
            .collection("sessions")
            .doc(sessionDoc.id)
            .collection("locations")
            .get();

          for (const locDoc of locationsSnap.docs) {
            const locData = locDoc.data();
            const locationName = locData.address || locData.title;
            if (locationName && locationName.trim().length > 0) {
              stats.locationsVisited.add(locationName.trim());
            }
          }
        } catch (err) {
          logger.warn(
            "dailySummaryAggregator: Failed to read locations subcollection.",
            {
              sessionId: sessionDoc.id,
              error: err instanceof Error ? err.message : String(err),
            }
          );
        }
      }

      // ── 4. Write daily summary documents ───────────────────────────────
      const batch = db.batch();
      let batchCount = 0;
      const MAX_BATCH_SIZE = 450; // Leave room under 500 limit

      for (const [employeeId, stats] of employeeStatsMap.entries()) {
        const summaryId = `${employeeId}_${dateStr}`;
        const summaryRef = db.collection("dailySummaries").doc(summaryId);

        batch.set(
          summaryRef,
          {
            enterpriseId,
            employeeId,
            date: startOfDay,
            totalDuration: stats.totalDuration,
            totalDistance: Math.round(stats.totalDistance * 100) / 100,
            photosCount: stats.photosCount,
            tasksCompleted: stats.tasksCompleted,
            locationsVisited: [...stats.locationsVisited],
            sessionIds: stats.sessionIds,
            isOffDuty: false,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: false } // Overwrite for accuracy at end of day
        );

        batchCount++;
        totalSummariesWritten++;

        // Commit in chunks if we approach the batch limit
        if (batchCount >= MAX_BATCH_SIZE) {
          await batch.commit();
          batchCount = 0;
          logger.info(
            "dailySummaryAggregator: Intermediate batch committed.",
            { enterpriseId }
          );
        }
      }

      // Commit remaining writes
      if (batchCount > 0) {
        await batch.commit();
      }

      logger.info("dailySummaryAggregator: Enterprise processed.", {
        enterpriseId,
        employeeCount: employeeStatsMap.size,
      });
    }

    logger.info("dailySummaryAggregator: Aggregation complete.", {
      enterpriseCount: enterprisesSnap.size,
      totalSummariesWritten,
    });
  }
);
