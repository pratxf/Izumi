import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import * as admin from "firebase-admin";

/**
 * One-time callable function to backfill missing activityLogs.
 *
 * Scans all sessions (and their locations) + all photos, and creates
 * activityLog documents for any that are missing.
 *
 * Idempotent — uses deterministic document IDs so re-running is safe.
 *
 * Call from Flutter:
 *   FirebaseFunctions.instanceFor(region: 'asia-south1')
 *       .httpsCallable('backfillActivityLogs')
 *       .call({'daysBack': 30});
 */
export const backfillActivityLogs = onCall(
  {
    region: "asia-south1",
    timeoutSeconds: 540,
    memory: "1GiB",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be authenticated.");
    }
    const claims = request.auth.token;
    const roles = claims.roles as string[] | undefined;
    if (!roles || !roles.includes("admin")) {
      throw new HttpsError("permission-denied", "Admin access required.");
    }

    const daysBack = (request.data?.daysBack as number) ?? 30;
    const cutoff = new Date();
    cutoff.setDate(cutoff.getDate() - daysBack);
    const cutoffTimestamp = admin.firestore.Timestamp.fromDate(cutoff);

    const db = admin.firestore();
    let sessionLogsCreated = 0;
    let locationLogsCreated = 0;
    let photoLogsCreated = 0;
    let skipped = 0;

    // ── Helper: IST date string ──
    function toDateStr(ts: admin.firestore.Timestamp): string {
      const d = ts.toDate();
      const ist = new Date(d.getTime() + 5.5 * 60 * 60 * 1000);
      return ist.toISOString().slice(0, 10);
    }

    // ── Helper: get employee name ──
    const nameCache: Record<string, string> = {};
    async function getEmployeeName(employeeId: string): Promise<string> {
      if (nameCache[employeeId]) return nameCache[employeeId];
      const snap = await db.collection("users").doc(employeeId).get();
      const name = snap.exists ? (snap.data()?.name as string) || "Employee" : "Employee";
      nameCache[employeeId] = name;
      return name;
    }

    // ══════════════════════════════════════════════════════════════════════
    // 1. Backfill session_start and session_end logs from sessions
    // ══════════════════════════════════════════════════════════════════════
    logger.info("backfillActivityLogs: Loading sessions...");

    const sessionsSnap = await db
      .collection("sessions")
      .where("startTime", ">=", cutoffTimestamp)
      .orderBy("startTime", "desc")
      .get();

    logger.info(`backfillActivityLogs: Found ${sessionsSnap.size} sessions.`);

    for (const sessionDoc of sessionsSnap.docs) {
      const session = sessionDoc.data();
      const sessionId = sessionDoc.id;
      const enterpriseId = session.enterpriseId as string;
      const employeeId = session.employeeId as string;
      if (!enterpriseId || !employeeId) continue;

      const startTime = session.startTime as admin.firestore.Timestamp | undefined;
      const endTime = session.endTime as admin.firestore.Timestamp | undefined;
      const status = session.status as string;
      const employeeName = await getEmployeeName(employeeId);

      // -- session_started --
      const startLogId = `session_started_${sessionId}`;
      const startExists = await db.collection("activityLogs").doc(startLogId).get();
      // Also check the old-style ID used by some client writes
      const altStartLogId = `session_start_${sessionId}`;
      const altStartExists = startExists.exists ? startExists : await db.collection("activityLogs").doc(altStartLogId).get();

      if (!startExists.exists && !altStartExists.exists && startTime) {
        await db.collection("activityLogs").doc(startLogId).set({
          enterpriseId,
          employeeId,
          sessionId,
          orgId: enterpriseId,
          type: "session_started",
          title: "Session Started",
          detail: `${employeeName} started a field session`,
          timestamp: startTime,
          date: toDateStr(startTime),
          payload: { startTime },
          metadata: { source: "backfill" },
        }, { merge: true });
        sessionLogsCreated++;
      } else {
        skipped++;
      }

      // -- session_ended / session_auto_ended --
      if (endTime && (status === "completed" || status === "auto_ended")) {
        const isAutoEnded = status === "auto_ended";
        const endType = isAutoEnded ? "session_auto_ended" : "session_ended";
        const endLogId = isAutoEnded
          ? `session_auto_ended_${sessionId}`
          : `session_ended_${sessionId}`;

        const endExists = await db.collection("activityLogs").doc(endLogId).get();
        // Also check the generic session_end ID
        const altEndLogId = `session_end_${sessionId}`;
        const altEndExists = endExists.exists ? endExists : await db.collection("activityLogs").doc(altEndLogId).get();

        if (!endExists.exists && !altEndExists.exists) {
          const durationSecs = (session.totalDuration as number) ?? 0;
          const distanceKm = (session.totalDistance as number) ?? 0;
          const title = isAutoEnded ? "Session Auto-Ended" : "Session Ended";
          const detail = isAutoEnded
            ? `${employeeName}'s session was auto-ended`
            : `${employeeName} ended the field session`;

          await db.collection("activityLogs").doc(endLogId).set({
            enterpriseId,
            employeeId,
            sessionId,
            orgId: enterpriseId,
            type: endType,
            title,
            detail,
            timestamp: endTime,
            date: toDateStr(endTime),
            payload: {
              endTime,
              durationSeconds: durationSecs,
              distanceKm,
              endReason: isAutoEnded ? (session.autoEndReason ?? "auto_ended") : "manual",
            },
            metadata: {
              status,
              source: "backfill",
            },
          }, { merge: true });
          sessionLogsCreated++;
        } else {
          skipped++;
        }
      }
    }

    logger.info(`backfillActivityLogs: Session logs done. Created: ${sessionLogsCreated}`);

    // ══════════════════════════════════════════════════════════════════════
    // 2. Backfill location_update logs from session locations
    // ══════════════════════════════════════════════════════════════════════
    logger.info("backfillActivityLogs: Loading session locations...");

    for (const sessionDoc of sessionsSnap.docs) {
      const session = sessionDoc.data();
      const sessionId = sessionDoc.id;
      const enterpriseId = session.enterpriseId as string;
      const employeeId = session.employeeId as string;
      if (!enterpriseId || !employeeId) continue;

      const locationsSnap = await db
        .collection("sessions")
        .doc(sessionId)
        .collection("locations")
        .orderBy("timestamp", "asc")
        .get();

      for (const locDoc of locationsSnap.docs) {
        const loc = locDoc.data();
        const locationId = locDoc.id;
        const logId = `location_update_${sessionId}_${locationId}`;

        const exists = await db.collection("activityLogs").doc(logId).get();
        if (exists.exists) {
          skipped++;
          continue;
        }

        const lat = (loc.latitude as number) ?? null;
        const lng = (loc.longitude as number) ?? null;
        const address = ((loc.address as string) ?? "").trim();
        const locTimestamp = loc.timestamp as admin.firestore.Timestamp | undefined;
        const title = ((loc.title as string) ?? "").trim() || "Tracked Location";
        const detail = address || (lat && lng ? `${lat}, ${lng}` : "Tracked location");
        const locType = (loc.type as string) ?? "location_update";

        if (!locTimestamp) {
          skipped++;
          continue;
        }

        await db.collection("activityLogs").doc(logId).set({
          enterpriseId,
          employeeId,
          sessionId,
          orgId: enterpriseId,
          type: "location_update",
          title,
          detail,
          timestamp: locTimestamp,
          date: toDateStr(locTimestamp),
          payload: {
            lat,
            lng,
            address,
          },
          metadata: {
            latitude: lat,
            longitude: lng,
            address,
            sourceLocationType: locType,
            sessionLocationId: locationId,
            source: "backfill",
          },
        }, { merge: true });
        locationLogsCreated++;
      }
    }

    logger.info(`backfillActivityLogs: Location logs done. Created: ${locationLogsCreated}`);

    // ══════════════════════════════════════════════════════════════════════
    // 3. Backfill photo_captured logs from photos collection
    // ══════════════════════════════════════════════════════════════════════
    logger.info("backfillActivityLogs: Loading photos...");

    const photosSnap = await db
      .collection("photos")
      .where("timestamp", ">=", cutoffTimestamp)
      .orderBy("timestamp", "desc")
      .get();

    logger.info(`backfillActivityLogs: Found ${photosSnap.size} photos.`);

    for (const photoDoc of photosSnap.docs) {
      const photo = photoDoc.data();
      const photoId = photoDoc.id;
      const logId = `photo_captured_${photoId}`;

      const exists = await db.collection("activityLogs").doc(logId).get();
      if (exists.exists) {
        skipped++;
        continue;
      }

      const enterpriseId = photo.enterpriseId as string;
      const employeeId = photo.employeeId as string;
      if (!enterpriseId || !employeeId) continue;

      const photoTimestamp = photo.timestamp as admin.firestore.Timestamp | undefined;
      if (!photoTimestamp) {
        skipped++;
        continue;
      }

      const location = ((photo.location as string) ?? "").trim();
      const category = ((photo.category as string) ?? "").trim();
      const customerName = ((photo.customerName as string) ?? "").trim();
      const detailParts = [location, category, customerName].filter(Boolean);
      const detail = detailParts.length > 0 ? detailParts.join(" · ") : "Photo uploaded";

      await db.collection("activityLogs").doc(logId).set({
        enterpriseId,
        employeeId,
        sessionId: (photo.sessionId as string) ?? null,
        orgId: enterpriseId,
        type: "photo_captured",
        title: "Photo Captured",
        detail,
        timestamp: photoTimestamp,
        date: toDateStr(photoTimestamp),
        payload: {
          photoId,
          photoUrl: (photo.imageUrl as string) ?? null,
          thumbnailUrl: (photo.thumbnailUrl as string) ?? null,
        },
        metadata: {
          photoId,
          location: location || null,
          category: category || null,
          customerName: customerName || null,
          customerPhone: ((photo.customerPhone as string) ?? "").trim() || null,
          notes: ((photo.notes as string) ?? "").trim() || null,
          latitude: (photo.latitude as number) ?? null,
          longitude: (photo.longitude as number) ?? null,
          imageUrl: (photo.imageUrl as string) ?? null,
          thumbnailUrl: (photo.thumbnailUrl as string) ?? null,
          source: "backfill",
        },
      }, { merge: true });
      photoLogsCreated++;
    }

    const summary = {
      sessionsScanned: sessionsSnap.size,
      photosScanned: photosSnap.size,
      sessionLogsCreated,
      locationLogsCreated,
      photoLogsCreated,
      totalCreated: sessionLogsCreated + locationLogsCreated + photoLogsCreated,
      skipped,
      daysBack,
    };

    logger.info("backfillActivityLogs: Complete.", summary);
    return summary;
  },
);
