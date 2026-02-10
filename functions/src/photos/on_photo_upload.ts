/**
 * onPhotoUpload - Cloud Storage Trigger
 *
 * Triggered when a file is uploaded (finalized) to Cloud Storage
 * under the path enterprises/{enterpriseId}/photos/.
 *
 * This function:
 *   1. Skips files that are already thumbnails (*_thumb.jpg)
 *   2. Downloads the original image from Storage
 *   3. Generates a 200x200 thumbnail using the sharp library
 *   4. Uploads the thumbnail alongside the original
 *   5. Updates the corresponding Firestore photo document with
 *      the public thumbnail URL
 */

import { onObjectFinalized } from "firebase-functions/v2/storage";
import * as admin from "firebase-admin";
import { logger } from "firebase-functions/v2";
import * as path from "path";
import * as os from "os";
import * as fs from "fs";
import sharp from "sharp";

/** Thumbnail dimensions. */
const THUMB_WIDTH = 200;
const THUMB_HEIGHT = 200;

/** Suffix appended to the original filename for the thumbnail. */
const THUMB_SUFFIX = "_thumb";

export const onPhotoUpload = onObjectFinalized(
  {
    region: "asia-south1",
    bucket: undefined, // Uses the default bucket
    // Only trigger for files under enterprises/*/photos/
    // We filter by path prefix in the handler since v2 does not support
    // path-pattern triggers natively on storage.
  },
  async (event) => {
    const object = event.data;
    const filePath = object.name;
    const contentType = object.contentType;

    if (!filePath) {
      logger.warn("onPhotoUpload: No file path in event, skipping.");
      return;
    }

    // ── Guard: Only process files under enterprises/*/photos/ ────────────
    const pathSegments = filePath.split("/");
    // Expected: enterprises/{enterpriseId}/photos/{userId}/{date}/{photoId}.jpg
    if (
      pathSegments.length < 3 ||
      pathSegments[0] !== "enterprises" ||
      pathSegments[2] !== "photos"
    ) {
      logger.info("onPhotoUpload: File is not in a photos path, skipping.", {
        filePath,
      });
      return;
    }

    // ── Guard: Skip if this is already a thumbnail ───────────────────────
    const fileName = path.basename(filePath);
    if (fileName.includes(THUMB_SUFFIX)) {
      logger.info("onPhotoUpload: File is already a thumbnail, skipping.", {
        filePath,
      });
      return;
    }

    // ── Guard: Only process images ───────────────────────────────────────
    if (!contentType || !contentType.startsWith("image/")) {
      logger.info("onPhotoUpload: File is not an image, skipping.", {
        filePath,
        contentType,
      });
      return;
    }

    const enterpriseId = pathSegments[1];

    logger.info("onPhotoUpload: Processing photo upload.", {
      filePath,
      enterpriseId,
      contentType,
    });

    const bucket = admin.storage().bucket(object.bucket);

    // Build paths
    const fileExtension = path.extname(fileName);
    const fileBaseName = path.basename(fileName, fileExtension);
    const fileDir = path.dirname(filePath);
    const thumbFileName = `${fileBaseName}${THUMB_SUFFIX}${fileExtension}`;
    const thumbFilePath = path.join(fileDir, thumbFileName);

    // Temp files on the Cloud Function instance
    const tempOriginalPath = path.join(os.tmpdir(), fileName);
    const tempThumbPath = path.join(os.tmpdir(), thumbFileName);

    try {
      // ── 1. Download the original image ─────────────────────────────────
      await bucket.file(filePath).download({ destination: tempOriginalPath });
      logger.info("onPhotoUpload: Original downloaded.", { tempOriginalPath });

      // ── 2. Generate the thumbnail with sharp ──────────────────────────
      await sharp(tempOriginalPath)
        .resize(THUMB_WIDTH, THUMB_HEIGHT, {
          fit: "cover",
          position: "centre",
        })
        .jpeg({ quality: 80 })
        .toFile(tempThumbPath);
      logger.info("onPhotoUpload: Thumbnail generated.", { tempThumbPath });

      // ── 3. Upload the thumbnail to Storage ─────────────────────────────
      const [thumbFile] = await bucket.upload(tempThumbPath, {
        destination: thumbFilePath,
        metadata: {
          contentType: "image/jpeg",
          metadata: {
            isThumb: "true",
            originalPath: filePath,
          },
        },
      });

      // Make the thumbnail publicly readable and get its URL
      await thumbFile.makePublic();
      const thumbnailUrl = `https://storage.googleapis.com/${object.bucket}/${thumbFilePath}`;

      logger.info("onPhotoUpload: Thumbnail uploaded.", {
        thumbFilePath,
        thumbnailUrl,
      });

      // ── 4. Find and update the Firestore photo document ────────────────
      // The photo document is identified by matching the imageUrl or the
      // storage path. We query by the storage URL of the original image.
      const originalUrl = `https://storage.googleapis.com/${object.bucket}/${filePath}`;

      const db = admin.firestore();
      const photosQuery = await db
        .collection("photos")
        .where("enterpriseId", "==", enterpriseId)
        .where("imageUrl", "==", originalUrl)
        .limit(1)
        .get();

      if (photosQuery.empty) {
        // Fallback: Try to extract photoId from the filename
        // Filename convention: {photoId}.jpg
        const photoId = fileBaseName;
        const photoRef = db.collection("photos").doc(photoId);
        const photoDoc = await photoRef.get();

        if (photoDoc.exists) {
          await photoRef.update({
            thumbnailUrl,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          logger.info(
            "onPhotoUpload: Photo document updated via ID fallback.",
            { photoId, thumbnailUrl }
          );
        } else {
          logger.warn(
            "onPhotoUpload: No matching Firestore photo document found.",
            { filePath, originalUrl, photoId }
          );
        }
      } else {
        const photoDoc = photosQuery.docs[0];
        await photoDoc.ref.update({
          thumbnailUrl,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        logger.info("onPhotoUpload: Photo document updated.", {
          photoDocId: photoDoc.id,
          thumbnailUrl,
        });
      }
    } catch (error) {
      logger.error("onPhotoUpload: Failed to process photo.", {
        filePath,
        error: error instanceof Error ? error.message : String(error),
      });
      throw error;
    } finally {
      // ── Cleanup temp files ─────────────────────────────────────────────
      try {
        if (fs.existsSync(tempOriginalPath)) fs.unlinkSync(tempOriginalPath);
        if (fs.existsSync(tempThumbPath)) fs.unlinkSync(tempThumbPath);
      } catch (cleanupErr) {
        logger.warn("onPhotoUpload: Failed to clean up temp files.", {
          error:
            cleanupErr instanceof Error
              ? cleanupErr.message
              : String(cleanupErr),
        });
      }
    }
  }
);
