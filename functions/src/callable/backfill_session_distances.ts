/**
 * backfillSessionDistances — One-time HTTPS Callable
 *
 * Corrects inflated totalDistance values on historical sessions.
 * onSessionComplete previously skipped auto_ended sessions, leaving the
 * uncorrected client-side distance in Firestore. This function recalculates
 * using the same trusted haversine + speed filter logic from on_session_complete.ts.
 *
 * Safety: deploy with DRY_RUN = true first, review logs, then redeploy with false.
 * Trigger: call via Firebase CLI or HTTP once. Not scheduled.
 */

import {onCall, HttpsError} from "firebase-functions/v2/https";
import {logger} from "firebase-functions/v2";
import * as admin from "firebase-admin";

// ═══════════════════════════════════════════════════════════════════════════
// SAFETY CONTROLS
// ═══════════════════════════════════════════════════════════════════════════

/** When true, logs what would change but writes nothing to Firestore. */
const DRY_RUN = true;

/** Sessions with corrected distance above this are skipped for manual review. */
const MAX_CORRECTED_DISTANCE_KM = 300;

/** Firestore batch size for session queries. */
const QUERY_BATCH_SIZE = 100;

// ═══════════════════════════════════════════════════════════════════════════
// HAVERSINE + SPEED FILTER — identical to on_session_complete.ts
// ═══════════════════════════════════════════════════════════════════════════

const MAX_REALISTIC_SPEED_KMH = 120;
const MAX_SEGMENT_DISTANCE_KM = 100;

interface LocationDocument {
  latitude: number;
  longitude: number;
  address?: string;
  timestamp?: admin.firestore.Timestamp;
  title?: string;
}

function haversineDistanceKm(
  lat1: number,
  lng1: number,
  lat2: number,
  lng2: number,
): number {
  const R = 6371; // Earth radius in km
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLng = ((lng2 - lng1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos((lat1 * Math.PI) / 180) *
      Math.cos((lat2 * Math.PI) / 180) *
      Math.sin(dLng / 2) *
      Math.sin(dLng / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

function calculateTrustedDistanceKm(locations: LocationDocument[]): {
  totalDistance: number;
  skippedSegments: number;
} {
  let totalDistance = 0;
  let skippedSegments = 0;

  for (let i = 1; i < locations.length; i++) {
    const prev = locations[i - 1];
    const curr = locations[i];
    const segmentDistanceKm = haversineDistanceKm(
      prev.latitude,
      prev.longitude,
      curr.latitude,
      curr.longitude,
    );

    const prevTs = prev.timestamp?.toMillis?.() ?? 0;
    const currTs = curr.timestamp?.toMillis?.() ?? 0;
    const elapsedHours =
      prevTs && currTs && currTs > prevTs
        ? (currTs - prevTs) / (1000 * 60 * 60)
        : 0;
    const impliedSpeedKmh =
      elapsedHours > 0
        ? segmentDistanceKm / elapsedHours
        : Number.POSITIVE_INFINITY;

    const isImplausibleJump =
      segmentDistanceKm > MAX_SEGMENT_DISTANCE_KM ||
      impliedSpeedKmh > MAX_REALISTIC_SPEED_KMH;

    if (isImplausibleJump) {
      skippedSegments++;
      continue;
    }

    totalDistance += segmentDistanceKm;
  }

  return {
    totalDistance: Math.round(totalDistance * 100) / 100,
    skippedSegments,
  };
}

// ═══════════════════════════════════════════════════════════════════════════
// IST DATE — identical to on_session_complete.ts
// ═══════════════════════════════════════════════════════════════════════════

function formatDateIST(timestamp: admin.firestore.Timestamp): string {
  const date = timestamp.toDate();
  const istOffset = 330;
  const utcMs = date.getTime() + date.getTimezoneOffset() * 60_000;
  const istDate = new Date(utcMs + istOffset * 60_000);

  const year = istDate.getFullYear();
  const month = String(istDate.getMonth() + 1).padStart(2, "0");
  const day = String(istDate.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

// ═══════════════════════════════════════════════════════════════════════════
// MAIN FUNCTION
// ═══════════════════════════════════════════════════════════════════════════

export const backfillSessionDistances = onCall(
  {
    region: "asia-south1",
    timeoutSeconds: 540,
    memory: "1GiB",
  },
  async (request) => {
    // Auth check — admin only
    const claims = request.auth?.token;
    if (
      !claims ||
      !(claims.roles as string[] | undefined)?.includes("admin")
    ) {
      throw new HttpsError(
        "permission-denied",
        "Admin role required.",
      );
    }

    const db = admin.firestore();

    logger.info("backfillSessionDistances: Starting.", {dryRun: DRY_RUN});

    // ── 1. Query sessions to fix ───────────────────────────────────���──

    // 1a. All auto_ended sessions (never had distance recalculated)
    const autoEndedSnap = await db
      .collection("sessions")
      .where("status", "==", "auto_ended")
      .get();

    // 1b. Completed sessions with suspiciously high distance (> 500 km)
    const inflatedCompletedSnap = await db
      .collection("sessions")
      .where("status", "==", "completed")
      .where("totalDistance", ">", 500)
      .get();

    const allDocs = [
      ...autoEndedSnap.docs,
      ...inflatedCompletedSnap.docs,
    ];

    // Deduplicate by session ID (a session could match both queries)
    const seen = new Set<string>();
    const sessionDocs = allDocs.filter((doc) => {
      if (seen.has(doc.id)) return false;
      seen.add(doc.id);
      return true;
    });

    logger.info("backfillSessionDistances: Sessions to process.", {
      autoEnded: autoEndedSnap.size,
      inflatedCompleted: inflatedCompletedSnap.size,
      totalAfterDedup: sessionDocs.length,
    });

    // ── 2. Process in batches ─────────────────────────────────────────

    let totalProcessed = 0;
    let totalCorrected = 0;
    let totalDistanceRemoved = 0;
    let totalSkippedManualReview = 0;
    let totalSkippedNoChange = 0;

    // Track daily summaries that need recalculation: key = summaryId
    const summariesToRecalc = new Map<
      string,
      {employeeId: string; enterpriseId: string; dateStr: string}
    >();

    for (let i = 0; i < sessionDocs.length; i += QUERY_BATCH_SIZE) {
      const batch = sessionDocs.slice(i, i + QUERY_BATCH_SIZE);

      for (const sessionDoc of batch) {
        const sessionId = sessionDoc.id;
        const session = sessionDoc.data();
        const oldDistance = Number(session.totalDistance ?? 0);
        const employeeId = session.employeeId as string;
        const enterpriseId = session.enterpriseId as string;
        const startTime = session.startTime as
          | admin.firestore.Timestamp
          | undefined;

        if (!employeeId || !startTime) {
          logger.warn(
            "backfillSessionDistances: Skipping session with missing data.",
            {sessionId, employeeId, hasStartTime: !!startTime},
          );
          totalProcessed++;
          continue;
        }

        // Fetch location subcollection
        const locationsSnap = await db
          .collection("sessions")
          .doc(sessionId)
          .collection("locations")
          .orderBy("timestamp", "asc")
          .get();

        const locations = locationsSnap.docs.map(
          (doc) => doc.data() as LocationDocument,
        );

        // Calculate trusted distance
        let correctedDistance: number;
        let skippedSegments = 0;

        if (locations.length < 2) {
          correctedDistance = 0;
        } else {
          const result = calculateTrustedDistanceKm(locations);
          correctedDistance = result.totalDistance;
          skippedSegments = result.skippedSegments;
        }

        totalProcessed++;

        // Safety cap — skip for manual review
        if (correctedDistance > MAX_CORRECTED_DISTANCE_KM) {
          logger.warn(
            "backfillSessionDistances: SKIPPED — corrected distance exceeds cap.",
            {
              sessionId,
              employeeId,
              oldDistance,
              correctedDistance,
              cap: MAX_CORRECTED_DISTANCE_KM,
              locationPoints: locations.length,
            },
          );
          totalSkippedManualReview++;
          continue;
        }

        // Skip if no meaningful change (within 0.1 km)
        const delta = Math.abs(oldDistance - correctedDistance);
        if (delta < 0.1) {
          totalSkippedNoChange++;
          continue;
        }

        const dateStr = formatDateIST(startTime);
        const summaryId = `${employeeId}_${dateStr}`;

        logger.info("backfillSessionDistances: Session processed.", {
          sessionId,
          employeeId,
          dateStr,
          status: session.status,
          oldDistance,
          correctedDistance,
          distanceRemoved: Math.round((oldDistance - correctedDistance) * 100) / 100,
          locationPoints: locations.length,
          skippedSegments,
          dryRun: DRY_RUN,
        });

        if (!DRY_RUN) {
          await db.collection("sessions").doc(sessionId).update({
            totalDistance: correctedDistance,
          });
        }

        totalCorrected++;
        totalDistanceRemoved += oldDistance - correctedDistance;

        // Track this summary for recalculation
        summariesToRecalc.set(summaryId, {
          employeeId,
          enterpriseId,
          dateStr,
        });
      }
    }

    // ── 3. Recalculate daily summaries ────────────────────────────────

    let summariesUpdated = 0;

    const summaryEntries = Array.from(summariesToRecalc.entries());
    for (const [summaryId, meta] of summaryEntries) {
      const {employeeId, enterpriseId, dateStr} = meta;

      // Query ALL sessions for this employee on this date to get the
      // correct aggregate, not just the one we corrected.
      const [year, month, day] = dateStr.split("-").map(Number);
      const istOffset = 330;
      const startOfDayIST = new Date(year, month - 1, day, 0, 0, 0, 0);
      const startOfDayUTC = new Date(
        startOfDayIST.getTime() - istOffset * 60_000,
      );
      const endOfDayIST = new Date(year, month - 1, day, 23, 59, 59, 999);
      const endOfDayUTC = new Date(
        endOfDayIST.getTime() - istOffset * 60_000,
      );

      const daySessionsSnap = await db
        .collection("sessions")
        .where("employeeId", "==", employeeId)
        .where("startTime", ">=", admin.firestore.Timestamp.fromDate(startOfDayUTC))
        .where("startTime", "<=", admin.firestore.Timestamp.fromDate(endOfDayUTC))
        .get();

      let dayTotalDistance = 0;
      for (const daySessionDoc of daySessionsSnap.docs) {
        dayTotalDistance += Number(daySessionDoc.data().totalDistance ?? 0);
      }
      dayTotalDistance = Math.round(dayTotalDistance * 100) / 100;

      logger.info("backfillSessionDistances: Daily summary recalculated.", {
        summaryId,
        employeeId,
        dateStr,
        sessionsOnDay: daySessionsSnap.size,
        newTotalDistance: dayTotalDistance,
        dryRun: DRY_RUN,
      });

      if (!DRY_RUN) {
        const summaryRef = db.collection("dailySummaries").doc(summaryId);
        const summarySnap = await summaryRef.get();
        if (summarySnap.exists) {
          await summaryRef.update({
            totalDistance: dayTotalDistance,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        } else {
          // Create a minimal summary if one doesn't exist
          await summaryRef.set(
            {
              enterpriseId,
              employeeId,
              date: admin.firestore.Timestamp.fromDate(startOfDayUTC),
              totalDistance: dayTotalDistance,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            {merge: true},
          );
        }
        summariesUpdated++;
      }
    }

    // ── 4. Final summary ──────────────────────────────────────────────

    const summary = {
      dryRun: DRY_RUN,
      totalSessionsQueried: sessionDocs.length,
      totalProcessed,
      totalCorrected,
      totalSkippedNoChange,
      totalSkippedManualReview,
      totalDistanceRemovedKm:
        Math.round(totalDistanceRemoved * 100) / 100,
      dailySummariesRecalculated: DRY_RUN
        ? summariesToRecalc.size
        : summariesUpdated,
    };

    logger.info("backfillSessionDistances: Complete.", summary);

    return summary;
  },
);
