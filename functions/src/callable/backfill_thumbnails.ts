/**
 * backfillThumbnails — Admin-only callable.
 *
 * Photos uploaded before the on_photo_upload fix store the thumbnailUrl as
 * a legacy `https://storage.googleapis.com/...` public URL that returns 403
 * on buckets with Uniform Bucket-Level Access enabled. This callable scans
 * recent photos for that URL shape and rewrites the field to a tokenized
 * `https://firebasestorage.googleapis.com/v0/b/.../o/...?alt=media&token=...`
 * URL — regenerating the thumbnail file from the original if it is missing.
 *
 * Idempotent: runs that touch a photo whose thumbnailUrl is already
 * tokenized are skipped by the legacy-prefix filter.
 *
 * Call from Flutter:
 *   FirebaseFunctions.instanceFor(region: 'asia-south1')
 *     .httpsCallable('backfillThumbnails')
 *     .call({
 *       'enterpriseId': '...',
 *       'dryRun': true,        // optional, default false
 *       'daysBack': 90,        // optional, default 90
 *       'limit': 500,          // optional, default 500
 *     });
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import * as admin from "firebase-admin";
import {
  deriveThumbPath,
  extractStoragePath,
  generateAndUploadThumbnail,
  refreshThumbnailToken,
} from "../photos/thumbnail_utils";

const LEGACY_PREFIX = "https://storage.googleapis.com/";
const BATCH_SIZE = 50;

interface BackfillResult {
  success: boolean;
  dryRun: boolean;
  enterpriseId: string;
  daysBack: number;
  scanned: number;
  affected: number;
  processed: number;
  updated: number;
  skipped: number;
  failed: number;
  errors: { photoId: string; error: string }[];
}

export const backfillThumbnails = onCall(
  {
    region: "asia-south1",
    timeoutSeconds: 540,
    memory: "1GiB",
  },
  async (request): Promise<BackfillResult> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be authenticated.");
    }
    const claims = request.auth.token;
    const roles = claims.roles as string[] | undefined;
    if (!roles || !roles.includes("admin")) {
      throw new HttpsError("permission-denied", "Admin access required.");
    }

    const enterpriseId = (request.data?.enterpriseId as string | undefined)?.trim();
    if (!enterpriseId) {
      throw new HttpsError("invalid-argument", "enterpriseId is required.");
    }

    const dryRun = (request.data?.dryRun as boolean | undefined) ?? false;
    const daysBack = (request.data?.daysBack as number | undefined) ?? 90;
    const limit = (request.data?.limit as number | undefined) ?? 500;

    const cutoff = new Date();
    cutoff.setDate(cutoff.getDate() - daysBack);
    const cutoffTs = admin.firestore.Timestamp.fromDate(cutoff);

    const db = admin.firestore();
    const bucket = admin.storage().bucket();

    logger.info("backfillThumbnails: starting", {
      enterpriseId, dryRun, daysBack, limit,
    });

    // Firestore can't do startsWith filtering, so we pull the recent slice
    // and filter the legacy-URL ones in memory.
    const photosSnap = await db
      .collection("photos")
      .where("enterpriseId", "==", enterpriseId)
      .where("timestamp", ">", cutoffTs)
      .orderBy("timestamp", "desc")
      .limit(limit)
      .get();

    const legacy = photosSnap.docs.filter((doc) => {
      const url = (doc.data().thumbnailUrl as string | undefined) ?? "";
      return url.startsWith(LEGACY_PREFIX);
    });

    logger.info("backfillThumbnails: scan complete", {
      scanned: photosSnap.size,
      affected: legacy.length,
    });

    if (dryRun) {
      return {
        success: true,
        dryRun: true,
        enterpriseId,
        daysBack,
        scanned: photosSnap.size,
        affected: legacy.length,
        processed: 0,
        updated: 0,
        skipped: 0,
        failed: 0,
        errors: [],
      };
    }

    let processed = 0;
    let updated = 0;
    let skipped = 0;
    let failed = 0;
    const errors: { photoId: string; error: string }[] = [];

    for (let i = 0; i < legacy.length; i += BATCH_SIZE) {
      const batch = legacy.slice(i, i + BATCH_SIZE);
      await Promise.all(batch.map(async (doc) => {
        processed++;
        try {
          const data = doc.data();
          const imageUrl = (data.imageUrl as string | undefined) ?? "";
          const originalPath = extractStoragePath(imageUrl);
          if (!originalPath) {
            skipped++;
            logger.warn("backfillThumbnails: cannot extract storage path", {
              photoId: doc.id, imageUrl,
            });
            return;
          }
          const thumbPath = deriveThumbPath(originalPath);
          const thumbFile = bucket.file(thumbPath);
          const [exists] = await thumbFile.exists();

          let newUrl: string;
          if (exists) {
            newUrl = await refreshThumbnailToken(bucket, thumbPath, originalPath);
          } else {
            // Thumbnail file is gone — regenerate from the original.
            const [origExists] = await bucket.file(originalPath).exists();
            if (!origExists) {
              skipped++;
              logger.warn("backfillThumbnails: original missing, cannot regenerate", {
                photoId: doc.id, originalPath,
              });
              return;
            }
            newUrl = await generateAndUploadThumbnail(bucket, originalPath, thumbPath);
          }

          await doc.ref.update({
            thumbnailUrl: newUrl,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          updated++;
        } catch (err) {
          failed++;
          const message = err instanceof Error ? err.message : String(err);
          errors.push({ photoId: doc.id, error: message });
          logger.error("backfillThumbnails: failed for photo", {
            photoId: doc.id, error: message,
          });
        }
      }));
    }

    const summary: BackfillResult = {
      success: true,
      dryRun: false,
      enterpriseId,
      daysBack,
      scanned: photosSnap.size,
      affected: legacy.length,
      processed,
      updated,
      skipped,
      failed,
      errors,
    };
    logger.info("backfillThumbnails: complete", summary);
    return summary;
  },
);
