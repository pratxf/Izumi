/**
 * migrateHistoricalPhotos - HTTPS Callable
 *
 * Scans the photos collection for a given enterprise and:
 *   1. Backfills missing employeeId / date fields on photo documents.
 *   2. Creates missing photo_captured activityLog entries using the
 *      canonical schema (orgId, date, payload).
 *
 * Admin-only. Supports dryRun mode (default: true).
 */

import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { logger } from "firebase-functions/v2";

type PhotoDoc = {
  enterpriseId?: string;
  employeeId?: string;
  sessionId?: string | null;
  timestamp?: admin.firestore.Timestamp;
  location?: string;
  category?: string;
  customerName?: string;
  customerPhone?: string;
  notes?: string;
  latitude?: number;
  longitude?: number;
  imageUrl?: string;
  thumbnailUrl?: string;
  date?: string;
};

type MigrationResult = {
  dryRun: boolean;
  photosScanned: number;
  photosBackfilled: number;
  activityLogsCreated: number;
  skippedExistingLogs: number;
  batchCommits: number;
};

const REGION = "asia-south1";
const BATCH_LIMIT = 400;

function assertAdmin(
  request: CallableRequest<unknown>,
): { enterpriseId: string } {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be authenticated.");
  }

  const callerRoles = request.auth.token.roles as string[] | undefined;
  const callerRole = request.auth.token.activeRole || request.auth.token.role;
  if (
    !(callerRoles && callerRoles.includes("admin")) &&
    callerRole !== "admin"
  ) {
    throw new HttpsError("permission-denied", "Only admins can run this.");
  }

  const enterpriseId = request.auth.token.enterpriseId as string | undefined;
  if (!enterpriseId) {
    throw new HttpsError("failed-precondition", "No enterpriseId in claims.");
  }

  return { enterpriseId };
}

function deriveDate(ts: admin.firestore.Timestamp): string {
  const d = ts.toDate();
  const ist = new Date(d.getTime() + 5.5 * 60 * 60 * 1000);
  return ist.toISOString().slice(0, 10);
}

export const migrateHistoricalPhotos = onCall(
  { region: REGION, timeoutSeconds: 540, memory: "512MiB" },
  async (request): Promise<MigrationResult> => {
    const { enterpriseId } = assertAdmin(request);
    const data = (request.data || {}) as { dryRun?: boolean };
    const dryRun = data.dryRun ?? true;

    const db = admin.firestore();
    const photosSnapshot = await db
      .collection("photos")
      .where("enterpriseId", "==", enterpriseId)
      .get();

    let batch = db.batch();
    let pendingWrites = 0;
    let batchCommits = 0;
    let photosBackfilled = 0;
    let activityLogsCreated = 0;
    let skippedExistingLogs = 0;

    const flushBatch = async () => {
      if (dryRun || pendingWrites === 0) return;
      await batch.commit();
      batch = db.batch();
      pendingWrites = 0;
      batchCommits++;
    };

    for (const photoDoc of photosSnapshot.docs) {
      const photoId = photoDoc.id;
      const photo = photoDoc.data() as PhotoDoc;

      if (!photo.employeeId || !photo.enterpriseId) continue;

      // ── 1. Backfill missing fields on the photo document ────────────
      const backfillUpdates: Record<string, unknown> = {};

      if (!photo.date && photo.timestamp) {
        backfillUpdates.date = deriveDate(photo.timestamp);
      }

      if (Object.keys(backfillUpdates).length > 0) {
        if (!dryRun) {
          batch.update(photoDoc.ref, backfillUpdates);
          pendingWrites++;
        }
        photosBackfilled++;
      }

      // ── 2. Create missing activityLog entry ─────────────────────────
      const activityLogId = `photo_captured_${photoId}`;
      const existingLog = await db
        .collection("activityLogs")
        .doc(activityLogId)
        .get();

      if (existingLog.exists) {
        skippedExistingLogs++;
      } else {
        if (!photo.timestamp) continue;

        const detailParts: string[] = [];
        if (photo.location?.trim()) detailParts.push(photo.location.trim());
        if (photo.category?.trim()) detailParts.push(photo.category.trim());
        if (photo.customerName?.trim()) {
          detailParts.push(photo.customerName.trim());
        }

        const dateStr = photo.date || deriveDate(photo.timestamp);

        const logData = {
          enterpriseId: photo.enterpriseId,
          employeeId: photo.employeeId,
          sessionId: photo.sessionId ?? null,
          orgId: photo.enterpriseId,
          type: "photo_captured",
          title: "Photo Captured",
          detail:
            detailParts.length > 0
              ? detailParts.join(" \u2022 ")
              : "Photo uploaded",
          timestamp: photo.timestamp,
          date: dateStr,
          payload: {
            photoId,
            photoUrl: photo.imageUrl ?? null,
            thumbnailUrl: photo.thumbnailUrl ?? null,
          },
          metadata: {
            source: "historical_photo_migration",
            migratedAt: admin.firestore.FieldValue.serverTimestamp(),
            photoId,
            location: photo.location ?? null,
            category: photo.category ?? null,
            customerName: photo.customerName ?? null,
            customerPhone: photo.customerPhone ?? null,
            notes: photo.notes ?? null,
            latitude: photo.latitude ?? null,
            longitude: photo.longitude ?? null,
            imageUrl: photo.imageUrl ?? null,
            thumbnailUrl: photo.thumbnailUrl ?? null,
          },
        };

        if (!dryRun) {
          batch.set(
            db.collection("activityLogs").doc(activityLogId),
            logData,
          );
          pendingWrites++;
        }
        activityLogsCreated++;
      }

      if (pendingWrites >= BATCH_LIMIT) {
        await flushBatch();
      }
    }

    await flushBatch();

    const result: MigrationResult = {
      dryRun,
      photosScanned: photosSnapshot.size,
      photosBackfilled,
      activityLogsCreated,
      skippedExistingLogs,
      batchCommits,
    };

    logger.info("migrateHistoricalPhotos completed.", {
      enterpriseId,
      ...result,
    });

    return result;
  },
);
