/**
 * cleanupOldExports - Weekly Scheduled Function
 *
 * Runs every Sunday at 02:00 IST (Saturday 20:30 UTC).
 * Iterates through all enterprises and deletes export files from
 * Cloud Storage that are older than 30 days.
 *
 * Storage path convention:
 *   enterprises/{enterpriseId}/exports/{exportId}.csv
 *   enterprises/{enterpriseId}/reports/{reportId}.pdf
 */

import { onSchedule } from "firebase-functions/v2/scheduler";
import * as admin from "firebase-admin";
import { logger } from "firebase-functions/v2";

/** Number of days after which export files are deleted. */
const RETENTION_DAYS = 30;

/** Prefixes under each enterprise directory to clean up. */
const CLEANUP_PREFIXES = ["exports", "reports"];

export const cleanupOldExports = onSchedule(
  {
    // Every Sunday at 02:00 IST (Saturday 20:30 UTC)
    schedule: "30 20 * * 6",
    timeZone: "Asia/Kolkata",
    region: "asia-south1",
    retryCount: 1,
    timeoutSeconds: 540,
    memory: "256MiB",
  },
  async (_event) => {
    logger.info("cleanupOldExports: Starting weekly cleanup.", {
      retentionDays: RETENTION_DAYS,
    });

    const db = admin.firestore();
    const bucket = admin.storage().bucket();
    const cutoffDate = new Date();
    cutoffDate.setDate(cutoffDate.getDate() - RETENTION_DAYS);

    logger.info("cleanupOldExports: Cutoff date.", {
      cutoffDate: cutoffDate.toISOString(),
    });

    // ── 1. Get all enterprises ───────────────────────────────────────────
    const enterprisesSnap = await db.collection("enterprises").get();

    if (enterprisesSnap.empty) {
      logger.info("cleanupOldExports: No enterprises found.");
      return;
    }

    let totalFilesDeleted = 0;
    let totalFilesChecked = 0;
    let totalErrors = 0;

    for (const enterpriseDoc of enterprisesSnap.docs) {
      const enterpriseId = enterpriseDoc.id;

      for (const prefix of CLEANUP_PREFIXES) {
        const directoryPath = `enterprises/${enterpriseId}/${prefix}/`;

        logger.info("cleanupOldExports: Scanning directory.", {
          directoryPath,
        });

        try {
          // List all files under this prefix
          const [files] = await bucket.getFiles({
            prefix: directoryPath,
          });

          for (const file of files) {
            totalFilesChecked++;

            try {
              // Get file metadata to check creation time
              const [metadata] = await file.getMetadata();
              const fileCreatedAt = metadata.timeCreated
                ? new Date(metadata.timeCreated)
                : null;

              if (!fileCreatedAt) {
                logger.warn(
                  "cleanupOldExports: Could not determine creation time.",
                  { fileName: file.name }
                );
                continue;
              }

              // Delete if older than the retention period
              if (fileCreatedAt < cutoffDate) {
                await file.delete();
                totalFilesDeleted++;

                logger.info("cleanupOldExports: File deleted.", {
                  fileName: file.name,
                  createdAt: fileCreatedAt.toISOString(),
                });
              }
            } catch (fileError) {
              totalErrors++;
              logger.error("cleanupOldExports: Error processing file.", {
                fileName: file.name,
                error:
                  fileError instanceof Error
                    ? fileError.message
                    : String(fileError),
              });
            }
          }
        } catch (listError) {
          totalErrors++;
          logger.error("cleanupOldExports: Error listing files.", {
            directoryPath,
            error:
              listError instanceof Error
                ? listError.message
                : String(listError),
          });
        }
      }
    }

    logger.info("cleanupOldExports: Cleanup complete.", {
      enterpriseCount: enterprisesSnap.size,
      totalFilesChecked,
      totalFilesDeleted,
      totalErrors,
    });
  }
);
