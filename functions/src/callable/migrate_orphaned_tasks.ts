/**
 * migrateOrphanedTasks - HTTPS Callable
 *
 * One-time migration function to fix tasks where assignedTo
 * references an old auto-generated user doc ID instead of
 * the employee's Firebase Auth UID.
 *
 * Matches orphaned tasks to the correct user by assignedToName
 * within the same enterprise, then updates assignedTo.
 *
 * Can only be called by an admin.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { logger } from "firebase-functions/v2";

export const migrateOrphanedTasks = onCall(
  { region: "asia-south1" },
  async (request) => {
    // Verify caller is authenticated
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be authenticated.");
    }

    // Verify caller is an admin (check roles array with fallback to role)
    const callerRoles = request.auth.token.roles as string[] | undefined;
    const callerRole = request.auth.token.activeRole || request.auth.token.role;
    if (!(callerRoles && callerRoles.includes("admin")) && callerRole !== "admin") {
      throw new HttpsError("permission-denied", "Only admins can run this.");
    }

    const enterpriseId = request.auth.token.enterpriseId as string;
    if (!enterpriseId) {
      throw new HttpsError("failed-precondition", "No enterpriseId in claims.");
    }

    const db = admin.firestore();

    // 1. Load all current users in this enterprise (keyed by doc ID)
    const usersSnapshot = await db
      .collection("users")
      .where("enterpriseId", "==", enterpriseId)
      .get();

    const validUserIds = new Set<string>();
    const usersByName = new Map<string, string>(); // name -> userId

    for (const userDoc of usersSnapshot.docs) {
      validUserIds.add(userDoc.id);
      const name = userDoc.data().name as string;
      if (name) {
        usersByName.set(name.toLowerCase(), userDoc.id);
      }
    }

    // 2. Load all tasks for this enterprise
    const tasksSnapshot = await db
      .collection("tasks")
      .where("enterpriseId", "==", enterpriseId)
      .get();

    let migratedCount = 0;
    let skippedCount = 0;
    const batch = db.batch();

    for (const taskDoc of tasksSnapshot.docs) {
      const taskData = taskDoc.data();
      const assignedTo = taskData.assignedTo as string;

      // Skip if assignedTo already points to a valid user
      if (validUserIds.has(assignedTo)) {
        continue;
      }

      // Try to match by assignedToName
      const assignedToName = (taskData.assignedToName as string) || "";
      const matchedUserId = usersByName.get(assignedToName.toLowerCase());

      if (matchedUserId) {
        batch.update(taskDoc.ref, {
          assignedTo: matchedUserId,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        migratedCount++;
        logger.info("Migrating orphaned task", {
          taskId: taskDoc.id,
          oldAssignedTo: assignedTo,
          newAssignedTo: matchedUserId,
          assignedToName,
        });
      } else {
        skippedCount++;
        logger.warn("Could not match orphaned task to any user", {
          taskId: taskDoc.id,
          assignedTo,
          assignedToName,
        });
      }
    }

    if (migratedCount > 0) {
      await batch.commit();
    }

    const result = {
      totalTasks: tasksSnapshot.size,
      migrated: migratedCount,
      skipped: skippedCount,
    };

    logger.info("migrateOrphanedTasks completed.", result);
    return result;
  }
);
