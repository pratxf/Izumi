import {onSchedule} from "firebase-functions/v2/scheduler";
import {logger} from "firebase-functions/v2";
import * as admin from "firebase-admin";

type SessionDoc = {
  employeeId?: string;
  enterpriseId?: string;
  startTime?: admin.firestore.Timestamp;
  status?: string;
  totalDistance?: number;
};

type ActiveStatsRecord = {
  sessionDuration?: number;
  distance?: number;
  photosToday?: number;
  tasksToday?: number;
};

type LocationDocument = {
  latitude: number;
  longitude: number;
  timestamp: admin.firestore.Timestamp;
  address?: string;
  title?: string;
  accuracy?: number;
};

const MAX_REALISTIC_SPEED_KMH = 90;
const MAX_SEGMENT_DISTANCE_KM = 10;
const MAX_ACCEPTED_ACCURACY_M = 50;
const MIN_CORRECTION_DELTA_KM = 0.5;

function haversineDistanceKm(
  lat1: number,
  lng1: number,
  lat2: number,
  lng2: number,
): number {
  const R = 6371;
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

function calculateTrustedDistanceKm(locations: LocationDocument[]): number {
  // Drop low-accuracy fixes from the distance calculation. They stay in
  // history (so the map still shows them) but are not summed.
  const usable = locations.filter(
    (loc) => loc.accuracy === undefined || loc.accuracy <= MAX_ACCEPTED_ACCURACY_M,
  );

  let totalDistance = 0;

  for (let i = 1; i < usable.length; i++) {
    const prev = usable[i - 1];
    const curr = usable[i];
    const segmentDistanceKm = haversineDistanceKm(
      prev.latitude,
      prev.longitude,
      curr.latitude,
      curr.longitude,
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
      logger.warn("sanitizeActiveStats: Skipping implausible active segment.", {
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

  return Math.round(totalDistance * 100) / 100;
}

export const sanitizeActiveStats = onSchedule(
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

    const activeSessionsSnap = await db
      .collection("sessions")
      .where("status", "==", "active")
      .get();

    if (activeSessionsSnap.empty) {
      logger.info("sanitizeActiveStats: No active sessions found.");
      return;
    }

    let correctedCount = 0;

    for (const sessionDoc of activeSessionsSnap.docs) {
      const session = sessionDoc.data() as SessionDoc;
      const enterpriseId = session.enterpriseId;
      const userId = session.employeeId;
      if (!enterpriseId || !userId) continue;

      const activeStatsSnap = await rtdb
        .ref(`activeStats/${enterpriseId}/${userId}`)
        .get();
      const activeStats = activeStatsSnap.val() as ActiveStatsRecord | null;
      if (!activeStats) continue;

      const locationsSnap = await db
        .collection("sessions")
        .doc(sessionDoc.id)
        .collection("locations")
        .orderBy("timestamp", "asc")
        .get();

      const locations = locationsSnap.docs.map(
        (doc) => doc.data() as LocationDocument,
      );

      const trustedDistance = calculateTrustedDistanceKm(locations);
      const currentDistance = Number(activeStats.distance ?? 0);
      const delta = Math.abs(currentDistance - trustedDistance);

      if (delta < MIN_CORRECTION_DELTA_KM) {
        continue;
      }

      await Promise.all([
        rtdb.ref(`activeStats/${enterpriseId}/${userId}`).update({
          distance: trustedDistance,
        }),
        sessionDoc.ref.update({
          totalDistance: trustedDistance,
        }),
      ]);

      correctedCount++;
      logger.info("sanitizeActiveStats: Corrected active distance.", {
        enterpriseId,
        userId,
        sessionId: sessionDoc.id,
        previousDistance: currentDistance,
        trustedDistance,
      });
    }

    logger.info("sanitizeActiveStats: Completed run.", {
      activeSessions: activeSessionsSnap.size,
      correctedCount,
    });
  },
);
