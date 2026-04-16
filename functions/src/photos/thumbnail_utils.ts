/**
 * Shared helpers for thumbnail generation and Firebase download URLs.
 *
 * Used by:
 *   - photos/on_photo_upload.ts (generates thumbnails on new uploads)
 *   - callable/backfill_thumbnails.ts (regenerates URLs / thumbnails for
 *     historical photos that still hold the legacy public URL)
 */

import * as admin from "firebase-admin";
import * as path from "path";
import * as os from "os";
import * as fs from "fs";
import { randomUUID } from "crypto";
import { logger } from "firebase-functions/v2";
import sharp from "sharp";

export const THUMB_WIDTH = 200;
export const THUMB_HEIGHT = 200;
export const THUMB_SUFFIX = "_thumb";

type Bucket = ReturnType<ReturnType<typeof admin.storage>["bucket"]>;

/** Builds a Firebase tokenized download URL — the same shape the client SDK
 *  produces. Works regardless of bucket public-access / UBLA settings. */
export function tokenizedDownloadUrl(
  bucketName: string,
  objectPath: string,
  token: string,
): string {
  const encoded = encodeURIComponent(objectPath);
  return (
    `https://firebasestorage.googleapis.com/v0/b/${bucketName}` +
    `/o/${encoded}?alt=media&token=${token}`
  );
}

/** Inserts THUMB_SUFFIX before the file extension. */
export function deriveThumbPath(originalPath: string): string {
  const ext = path.extname(originalPath);
  const base = originalPath.slice(0, originalPath.length - ext.length);
  return `${base}${THUMB_SUFFIX}${ext || ".jpg"}`;
}

/** Sets a fresh download token on an already-uploaded thumbnail file
 *  (preserving its existing custom metadata) and returns the new URL. */
export async function refreshThumbnailToken(
  bucket: Bucket,
  thumbPath: string,
  originalPath: string,
): Promise<string> {
  const token = randomUUID();
  await bucket.file(thumbPath).setMetadata({
    metadata: {
      isThumb: "true",
      originalPath,
      firebaseStorageDownloadTokens: token,
    },
  });
  return tokenizedDownloadUrl(bucket.name, thumbPath, token);
}

/** Downloads the original, generates a 200x200 thumbnail with sharp, uploads
 *  it with a Firebase download token in metadata, and returns the URL. */
export async function generateAndUploadThumbnail(
  bucket: Bucket,
  originalPath: string,
  thumbPath: string,
): Promise<string> {
  const fileName = path.basename(originalPath);
  const thumbName = path.basename(thumbPath);
  const tempOriginalPath = path.join(os.tmpdir(), `orig_${randomUUID()}_${fileName}`);
  const tempThumbPath = path.join(os.tmpdir(), `thumb_${randomUUID()}_${thumbName}`);

  try {
    await bucket.file(originalPath).download({ destination: tempOriginalPath });

    await sharp(tempOriginalPath)
      .resize(THUMB_WIDTH, THUMB_HEIGHT, { fit: "cover", position: "centre" })
      .jpeg({ quality: 80 })
      .toFile(tempThumbPath);

    const token = randomUUID();
    await bucket.upload(tempThumbPath, {
      destination: thumbPath,
      metadata: {
        contentType: "image/jpeg",
        metadata: {
          isThumb: "true",
          originalPath,
          firebaseStorageDownloadTokens: token,
        },
      },
    });

    return tokenizedDownloadUrl(bucket.name, thumbPath, token);
  } finally {
    try {
      if (fs.existsSync(tempOriginalPath)) fs.unlinkSync(tempOriginalPath);
      if (fs.existsSync(tempThumbPath)) fs.unlinkSync(tempThumbPath);
    } catch (cleanupErr) {
      logger.warn("generateAndUploadThumbnail: temp cleanup failed", {
        error: cleanupErr instanceof Error ? cleanupErr.message : String(cleanupErr),
      });
    }
  }
}

/** Pulls the storage object path out of either a Firebase tokenized URL
 *  (`/v0/b/{bucket}/o/{encodedPath}`) or a legacy public URL
 *  (`storage.googleapis.com/{bucket}/{path}`). Returns null if neither. */
export function extractStoragePath(url: string): string | null {
  if (!url) return null;
  const tokenMatch = url.match(/\/o\/([^?]+)/);
  if (tokenMatch) {
    try {
      return decodeURIComponent(tokenMatch[1]);
    } catch {
      return null;
    }
  }
  const legacyMatch = url.match(/^https:\/\/storage\.googleapis\.com\/[^/]+\/(.+)$/);
  if (legacyMatch) {
    try {
      return decodeURIComponent(legacyMatch[1].split("?")[0]);
    } catch {
      return null;
    }
  }
  return null;
}
