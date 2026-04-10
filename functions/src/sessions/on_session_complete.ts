/**
 * onSessionComplete - Firestore Trigger
 *
 * Triggered when a document in /sessions/{sessionId} is updated.
 * When the status field changes to 'completed', this function:
 *   1. Reads all location documents from the /sessions/{sessionId}/locations subcollection
 *   2. Calculates total distance from the location trail
 *   3. Gathers unique location names visited
 *   4. Creates or updates the daily summary document at
 *      /dailySummaries/{employeeId}_{YYYY-MM-DD}
 */

import { onDocumentUpdated } from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";
import { logger } from "firebase-functions/v2";

/** Shape of a session document. */
interface SessionDocument {
  enterpriseId: string;
  employeeId: string;
  startTime: admin.firestore.Timestamp;
  endTime?: admin.firestore.Timestamp;
  status: "active" | "completed" | "auto_ended";
  totalDuration: number;
  totalDistance: number;
  photosCount: number;
  tasksCompleted: number;
  notes?: string;
  createdAt: admin.firestore.Timestamp;
}

/** Shape of a location sub-document. */
interface LocationDocument {
  latitude: number;
  longitude: number;
  address: string;
  timestamp: admin.firestore.Timestamp;
  type: "check_in" | "visit" | "check_out";
  title: string;
}

const MAX_REALISTIC_SPEED_KMH = 120;
const MAX_SEGMENT_DISTANCE_KM = 100;

/**
 * Calculate the distance in kilometres between two lat/lng pairs
 * using the Haversine formula.
 */
function haversineDistanceKm(
  lat1: number,
  lng1: number,
  lat2: number,
  lng2: number
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
      curr.longitude
    );

    const prevTs = prev.timestamp?.toMillis?.() ?? 0;
    const currTs = curr.timestamp?.toMillis?.() ?? 0;
    const elapsedHours = prevTs && currTs && currTs > prevTs ?
      (currTs - prevTs) / (1000 * 60 * 60) :
      0;
    const impliedSpeedKmh = elapsedHours > 0 ?
      segmentDistanceKm / elapsedHours :
      Number.POSITIVE_INFINITY;

    const isImplausibleJump =
      segmentDistanceKm > MAX_SEGMENT_DISTANCE_KM ||
      impliedSpeedKmh > MAX_REALISTIC_SPEED_KMH;

    if (isImplausibleJump) {
      skippedSegments++;
      logger.warn("onSessionComplete: Skipping implausible distance segment.", {
        from: prev.address || prev.title || null,
        to: curr.address || curr.title || null,
        segmentDistanceKm: Math.round(segmentDistanceKm * 100) / 100,
        impliedSpeedKmh:
          Number.isFinite(impliedSpeedKmh) ?
            Math.round(impliedSpeedKmh * 100) / 100 :
            null,
      });
      continue;
    }

    totalDistance += segmentDistanceKm;
  }

  return {
    totalDistance: Math.round(totalDistance * 100) / 100,
    skippedSegments,
  };
}

/**
 * Format a Firestore Timestamp to YYYY-MM-DD in IST (UTC+5:30).
 */
function formatDateIST(timestamp: admin.firestore.Timestamp): string {
  const date = timestamp.toDate();
  // IST is UTC + 5:30 = 330 minutes
  const istOffset = 330;
  const utcMs = date.getTime() + date.getTimezoneOffset() * 60_000;
  const istDate = new Date(utcMs + istOffset * 60_000);

  const year = istDate.getFullYear();
  const month = String(istDate.getMonth() + 1).padStart(2, "0");
  const day = String(istDate.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

export const onSessionComplete = onDocumentUpdated(
  {
    document: "sessions/{sessionId}",
    region: "asia-south1",
  },
  async (event) => {
    const beforeData = event.data?.before.data() as SessionDocument | undefined;
    const afterData = event.data?.after.data() as SessionDocument | undefined;

    if (!beforeData || !afterData) {
      logger.warn("onSessionComplete: Missing before/after data, skipping.");
      return;
    }

    // Proceed when the status transitions to 'completed' or 'auto_ended'
    const isTerminal =
      afterData.status === "completed" || afterData.status === "auto_ended";
    const wasAlreadyTerminal =
      beforeData.status === "completed" || beforeData.status === "auto_ended";
    if (!isTerminal || wasAlreadyTerminal) {
      return;
    }

    const sessionId = event.params.sessionId;
    const {
      enterpriseId,
      employeeId,
      startTime,
      endTime,
      photosCount,
      tasksCompleted,
    } = afterData;

    logger.info("onSessionComplete: Processing completed session.", {
      sessionId,
      employeeId,
    });

    const db = admin.firestore();

    // ── 1. Read all locations from the subcollection ─────────────────────
    const locationsSnap = await db
      .collection("sessions")
      .doc(sessionId)
      .collection("locations")
      .orderBy("timestamp", "asc")
      .get();

    const locations: LocationDocument[] = locationsSnap.docs.map(
      (doc) => doc.data() as LocationDocument
    );

    // ── 2. Calculate total distance from location trail ──────────────────
    const {
      totalDistance,
      skippedSegments,
    } = calculateTrustedDistanceKm(locations);

    // ── 3. Calculate total duration ──────────────────────────────────────
    let totalDuration = afterData.totalDuration || 0;
    if (startTime && endTime) {
      totalDuration = Math.round(
        (endTime.toMillis() - startTime.toMillis()) / 1000
      );
    }

    // ── 4. Gather unique location names ──────────────────────────────────
    const locationsVisited: string[] = [
      ...new Set(
        locations
          .map((loc) => loc.address || loc.title)
          .filter((name) => name && name.trim().length > 0)
      ),
    ];

    // ── 5. Update the session document with calculated stats ─────────────
    await db.collection("sessions").doc(sessionId).update({
      totalDistance,
      totalDuration,
    });

    logger.info("onSessionComplete: Session stats updated.", {
      sessionId,
      totalDistance,
      totalDuration,
      locationsVisited: locationsVisited.length,
      skippedSegments,
    });

    // ── 6. Create or update the daily summary ────────────────────────────
    const dateStr = formatDateIST(startTime);
    const summaryId = `${employeeId}_${dateStr}`;
    const summaryRef = db.collection("dailySummaries").doc(summaryId);

    await db.runTransaction(async (transaction) => {
      const summarySnap = await transaction.get(summaryRef);

      if (summarySnap.exists) {
        // Merge with existing summary
        const existing = summarySnap.data()!;
        const existingSessionIds: string[] = existing.sessionIds || [];

        // Avoid duplicate entries if function retries
        if (existingSessionIds.includes(sessionId)) {
          logger.warn(
            "onSessionComplete: Session already recorded in daily summary, skipping merge.",
            { sessionId, summaryId }
          );
          return;
        }

        transaction.update(summaryRef, {
          totalDuration: (existing.totalDuration || 0) + totalDuration,
          totalDistance:
            Math.round(
              ((existing.totalDistance || 0) + totalDistance) * 100
            ) / 100,
          photosCount: (existing.photosCount || 0) + (photosCount || 0),
          tasksCompleted:
            (existing.tasksCompleted || 0) + (tasksCompleted || 0),
          locationsVisited: [
            ...new Set([
              ...(existing.locationsVisited || []),
              ...locationsVisited,
            ]),
          ],
          sessionIds: [...existingSessionIds, sessionId],
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      } else {
        // Create a new daily summary
        // Build the start-of-day timestamp in IST
        const [year, month, day] = dateStr.split("-").map(Number);
        // Create a date at 00:00 IST (which is previous day 18:30 UTC)
        const startOfDayIST = new Date(
          Date.UTC(year, month - 1, day, 0, 0, 0) - 330 * 60_000
        );

        transaction.set(summaryRef, {
          enterpriseId,
          employeeId,
          date: admin.firestore.Timestamp.fromDate(startOfDayIST),
          totalDuration,
          totalDistance,
          photosCount: photosCount || 0,
          tasksCompleted: tasksCompleted || 0,
          locationsVisited,
          sessionIds: [sessionId],
          isOffDuty: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    });

    logger.info("onSessionComplete: Daily summary updated.", {
      summaryId,
      sessionId,
    });
  }
);
