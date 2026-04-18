/**
 * cleanupOrphanData - HTTPS Callable (admin only, scoped to caller enterprise)
 *
 * One-time cleanup for residue left by older delete flows:
 *   - Employee IDs referenced in sessions/photos/tasks/dailySummaries that no
 *     longer have a user doc → creates deletedUsers/{uid} tombstones so
 *     analytics can exclude them.
 *   - Firebase Auth users whose custom claims point at this enterprise but
 *     have no matching Firestore user doc → candidates to delete.
 *
 * Parameters:
 *   dryRun: boolean (default true)  — if true, only reports; no writes.
 *
 * Returns a structured report for admin review.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { logger } from "firebase-functions/v2";

interface OrphanRecord {
  employeeId: string;
  sessionCount: number;
  photoCount: number;
  taskCount: number;
  summaryCount: number;
  authExists: boolean;
  authPhone: string | null;
}

export const cleanupOrphanData = onCall(
  { region: "asia-south1", timeoutSeconds: 540 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be authenticated.");
    }
    const callerRoles = request.auth.token.roles as string[] | undefined;
    const callerRole = request.auth.token.activeRole || request.auth.token.role;
    const isAdmin =
      (callerRoles && callerRoles.includes("admin")) || callerRole === "admin";
    if (!isAdmin) {
      throw new HttpsError("permission-denied", "Admin only.");
    }

    const callerEnterpriseId = request.auth.token.enterpriseId as
      | string
      | undefined;
    if (!callerEnterpriseId) {
      throw new HttpsError(
        "failed-precondition",
        "No enterpriseId in caller claims."
      );
    }
    const enterpriseId = callerEnterpriseId;
    const dryRun = request.data?.dryRun !== false; // default true

    const db = admin.firestore();

    // 1. Collect current user doc IDs for the enterprise.
    const usersSnap = await db
      .collection("users")
      .where("enterpriseId", "==", enterpriseId)
      .get();
    const activeUserIds = new Set(usersSnap.docs.map((d) => d.id));

    // 2. Scan each data collection and tally references by employeeId.
    const tally = (
      docs: FirebaseFirestore.QueryDocumentSnapshot[],
      field: string,
      key: "sessionCount" | "photoCount" | "taskCount" | "summaryCount",
      acc: Map<string, OrphanRecord>
    ) => {
      for (const doc of docs) {
        const id = doc.get(field);
        if (typeof id !== "string" || !id) continue;
        if (activeUserIds.has(id)) continue;
        const existing = acc.get(id) ?? {
          employeeId: id,
          sessionCount: 0,
          photoCount: 0,
          taskCount: 0,
          summaryCount: 0,
          authExists: false,
          authPhone: null,
        };
        existing[key] += 1;
        acc.set(id, existing);
      }
    };

    const orphanMap = new Map<string, OrphanRecord>();
    const [sessions, photos, tasks, summaries] = await Promise.all([
      db
        .collection("sessions")
        .where("enterpriseId", "==", enterpriseId)
        .get(),
      db
        .collection("photos")
        .where("enterpriseId", "==", enterpriseId)
        .get(),
      db.collection("tasks").where("enterpriseId", "==", enterpriseId).get(),
      db
        .collection("dailySummaries")
        .where("enterpriseId", "==", enterpriseId)
        .get(),
    ]);

    tally(sessions.docs, "employeeId", "sessionCount", orphanMap);
    tally(photos.docs, "employeeId", "photoCount", orphanMap);
    tally(tasks.docs, "assignedTo", "taskCount", orphanMap);
    tally(summaries.docs, "employeeId", "summaryCount", orphanMap);

    // 3. Resolve Auth existence for each orphan employeeId.
    for (const record of orphanMap.values()) {
      try {
        const au = await admin.auth().getUser(record.employeeId);
        record.authExists = true;
        record.authPhone = au.phoneNumber || null;
      } catch {
        record.authExists = false;
      }
    }

    // 4. Find Auth zombies: Auth users with enterpriseId claim = ours but
    //    no matching user doc in our enterprise.
    const authZombies: Array<{
      uid: string;
      phone: string | null;
      name: string | null;
    }> = [];
    let pageToken: string | undefined;
    do {
      const page = await admin.auth().listUsers(1000, pageToken);
      for (const u of page.users) {
        const claims = u.customClaims || {};
        if (claims.enterpriseId !== enterpriseId) continue;
        if (activeUserIds.has(u.uid)) continue;
        authZombies.push({
          uid: u.uid,
          phone: u.phoneNumber || null,
          name: u.displayName || null,
        });
      }
      pageToken = page.pageToken;
    } while (pageToken);

    // 5. If not dryRun: write tombstones + delete Auth zombies.
    const actions = {
      tombstonesCreated: [] as string[],
      tombstonesSkipped: [] as string[],
      authZombiesDeleted: [] as string[],
      authZombiesFailed: [] as Array<{ uid: string; error: string }>,
    };

    if (!dryRun) {
      for (const record of orphanMap.values()) {
        try {
          const existing = await db
            .collection("deletedUsers")
            .doc(record.employeeId)
            .get();
          if (existing.exists) {
            actions.tombstonesSkipped.push(record.employeeId);
            continue;
          }
          await db
            .collection("deletedUsers")
            .doc(record.employeeId)
            .set({
              uid: record.employeeId,
              name: null,
              phone: record.authPhone,
              enterpriseId,
              deletedAt: admin.firestore.FieldValue.serverTimestamp(),
              deletedBy: request.auth.uid,
              source: "cleanup_orphan_data",
              sessionCount: record.sessionCount,
              photoCount: record.photoCount,
              taskCount: record.taskCount,
              summaryCount: record.summaryCount,
            });
          actions.tombstonesCreated.push(record.employeeId);
        } catch (e) {
          logger.error("cleanupOrphanData: Tombstone write failed.", {
            uid: record.employeeId,
            error: e instanceof Error ? e.message : String(e),
          });
        }
      }

      for (const zombie of authZombies) {
        try {
          await admin.auth().deleteUser(zombie.uid);
          actions.authZombiesDeleted.push(zombie.uid);
        } catch (e) {
          actions.authZombiesFailed.push({
            uid: zombie.uid,
            error: e instanceof Error ? e.message : String(e),
          });
        }
      }
    }

    const report = {
      dryRun,
      enterpriseId,
      activeUserCount: activeUserIds.size,
      orphanEmployeeIds: Array.from(orphanMap.values()).sort(
        (a, b) => b.sessionCount - a.sessionCount
      ),
      orphanTotals: {
        uniqueIds: orphanMap.size,
        sessions: Array.from(orphanMap.values()).reduce(
          (n, r) => n + r.sessionCount,
          0
        ),
        photos: Array.from(orphanMap.values()).reduce(
          (n, r) => n + r.photoCount,
          0
        ),
        tasks: Array.from(orphanMap.values()).reduce(
          (n, r) => n + r.taskCount,
          0
        ),
        summaries: Array.from(orphanMap.values()).reduce(
          (n, r) => n + r.summaryCount,
          0
        ),
      },
      authZombies,
      actions,
    };

    logger.info("cleanupOrphanData: completed", {
      dryRun,
      enterpriseId,
      orphans: orphanMap.size,
      zombies: authZombies.length,
    });

    return report;
  }
);
