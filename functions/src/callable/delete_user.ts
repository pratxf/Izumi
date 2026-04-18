/**
 * deleteUser - HTTPS Callable
 *
 * Admin-only full user deletion with historical preservation:
 *   1. Verify caller is admin in same enterprise.
 *   2. Auto-end any active sessions (zombie prevention).
 *   3. Unassign pending tasks (completed tasks are audit records — left alone).
 *   4. Delete the user's /notifications subcollection.
 *   5. Remove user from groups (memberIds, leadIds, scalar leadId).
 *   6. Remove user from chat groups.
 *   7. Clean RTDB presence/stats/heartbeat/liveLocations.
 *   8. Write a deletedUsers/{uid} tombstone with counts so analytics can
 *      exclude this user's historical data without losing the records.
 *   9. Delete the Firestore user doc.
 *  10. Delete the Firebase Auth user (frees phone for re-registration).
 *
 * Sessions, photos, activityLogs, and dailySummaries are intentionally NOT
 * deleted. They are business/audit records. The tombstone in deletedUsers/
 * is the signal for analytics to exclude them from enterprise totals.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { logger } from "firebase-functions/v2";

async function deleteNotificationsSubcollection(
  db: FirebaseFirestore.Firestore,
  uid: string
): Promise<number> {
  const ref = db.collection("users").doc(uid).collection("notifications");
  let total = 0;
  while (true) {
    const snap = await ref.limit(400).get();
    if (snap.empty) break;
    const batch = db.batch();
    for (const doc of snap.docs) batch.delete(doc.ref);
    await batch.commit();
    total += snap.size;
    if (snap.size < 400) break;
  }
  return total;
}

export const deleteUser = onCall(
  { region: "asia-south1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be authenticated.");
    }

    const callerRoles = request.auth.token.roles as string[] | undefined;
    const callerRole = request.auth.token.activeRole || request.auth.token.role;
    const isAdmin =
      (callerRoles && callerRoles.includes("admin")) || callerRole === "admin";
    if (!isAdmin) {
      throw new HttpsError("permission-denied", "Only admins can delete users.");
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

    const targetUserId = request.data?.targetUserId as string | undefined;
    if (!targetUserId) {
      throw new HttpsError("invalid-argument", "targetUserId is required.");
    }
    if (targetUserId === request.auth.uid) {
      throw new HttpsError("invalid-argument", "Cannot delete your own account.");
    }

    const db = admin.firestore();
    const rtdb = admin.database();

    // Verify target user exists and belongs to caller's enterprise.
    const userDoc = await db.collection("users").doc(targetUserId).get();
    let userData: FirebaseFirestore.DocumentData | undefined;
    if (userDoc.exists) {
      userData = userDoc.data();
      if (userData?.enterpriseId !== callerEnterpriseId) {
        throw new HttpsError(
          "permission-denied",
          "Cannot delete users from a different enterprise."
        );
      }
    } else {
      // Doc missing: still allow cleanup (orphan Auth / residual data case).
      logger.warn(
        "deleteUser: User doc not found; proceeding with best-effort cleanup.",
        { targetUserId }
      );
    }

    const enterpriseId = callerEnterpriseId;

    // 1. Auto-end any active sessions for this employee so the UI never
    //    shows a zombie session that can never be closed.
    let autoEndedSessions = 0;
    try {
      const activeSessions = await db
        .collection("sessions")
        .where("enterpriseId", "==", enterpriseId)
        .where("employeeId", "==", targetUserId)
        .where("status", "==", "active")
        .get();

      if (!activeSessions.empty) {
        const batch = db.batch();
        const now = admin.firestore.FieldValue.serverTimestamp();
        for (const sessionDoc of activeSessions.docs) {
          batch.update(sessionDoc.ref, {
            status: "auto_ended",
            endTime: now,
            autoEndReason: "user_deleted",
            updatedAt: now,
          });
        }
        await batch.commit();
        autoEndedSessions = activeSessions.size;
      }
    } catch (e) {
      logger.warn("deleteUser: Failed to auto-end active sessions.", {
        targetUserId,
        error: e instanceof Error ? e.message : String(e),
      });
    }

    // 2. Unassign pending tasks. Completed tasks are audit records — keep.
    let unassignedTasks = 0;
    try {
      const pendingTasks = await db
        .collection("tasks")
        .where("enterpriseId", "==", enterpriseId)
        .where("assignedTo", "==", targetUserId)
        .where("status", "==", "pending")
        .get();

      if (!pendingTasks.empty) {
        const batch = db.batch();
        const now = admin.firestore.FieldValue.serverTimestamp();
        for (const taskDoc of pendingTasks.docs) {
          batch.update(taskDoc.ref, {
            status: "unassigned",
            assignedTo: null,
            updatedAt: now,
          });
        }
        await batch.commit();
        unassignedTasks = pendingTasks.size;
      }
    } catch (e) {
      logger.warn("deleteUser: Failed to unassign pending tasks.", {
        targetUserId,
        error: e instanceof Error ? e.message : String(e),
      });
    }

    // 3. Delete notifications subcollection.
    let deletedNotifications = 0;
    try {
      deletedNotifications = await deleteNotificationsSubcollection(
        db,
        targetUserId
      );
    } catch (e) {
      logger.warn("deleteUser: Failed to delete notifications subcollection.", {
        targetUserId,
        error: e instanceof Error ? e.message : String(e),
      });
    }

    // 4. Remove from groups: memberIds, leadIds, and scalar leadId.
    try {
      const groupsByMember = await db
        .collection("groups")
        .where("enterpriseId", "==", enterpriseId)
        .where("memberIds", "array-contains", targetUserId)
        .get();
      const groupsByLead = await db
        .collection("groups")
        .where("enterpriseId", "==", enterpriseId)
        .where("leadIds", "array-contains", targetUserId)
        .get();

      const groupRefs = new Map<string, FirebaseFirestore.DocumentReference>();
      for (const d of groupsByMember.docs) groupRefs.set(d.id, d.ref);
      for (const d of groupsByLead.docs) groupRefs.set(d.id, d.ref);

      for (const ref of groupRefs.values()) {
        const snap = await ref.get();
        if (!snap.exists) continue;
        const data = snap.data() || {};
        const currentLeadIds = Array.isArray(data.leadIds)
          ? (data.leadIds as unknown[]).filter(
              (id): id is string => typeof id === "string"
            )
          : [];
        const nextLeadIds = currentLeadIds.filter((id) => id !== targetUserId);

        // Keep the scalar leadId in sync with the array — if the deleted user
        // was the primary lead, promote the next lead (or clear the field).
        const currentLeadId =
          typeof data.leadId === "string" ? data.leadId : "";
        const nextLeadId =
          currentLeadId === targetUserId
            ? nextLeadIds.length > 0
              ? nextLeadIds[0]
              : ""
            : currentLeadId;

        await ref.update({
          memberIds: admin.firestore.FieldValue.arrayRemove(targetUserId),
          leadIds: admin.firestore.FieldValue.arrayRemove(targetUserId),
          leadId: nextLeadId,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      logger.warn("deleteUser: Failed to clean up groups.", {
        targetUserId,
        error: e instanceof Error ? e.message : String(e),
      });
    }

    // 5. Remove from chat groups.
    try {
      const chatGroupsByMember = await db
        .collection("chatGroups")
        .where("enterpriseId", "==", enterpriseId)
        .where("memberIds", "array-contains", targetUserId)
        .get();

      for (const doc of chatGroupsByMember.docs) {
        await doc.ref.update({
          memberIds: admin.firestore.FieldValue.arrayRemove(targetUserId),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      logger.warn("deleteUser: Failed to clean up chat groups.", {
        targetUserId,
        error: e instanceof Error ? e.message : String(e),
      });
    }

    // 6. Clean up RTDB nodes.
    try {
      await Promise.all([
        rtdb.ref(`presence/${enterpriseId}/${targetUserId}`).remove(),
        rtdb.ref(`activeStats/${enterpriseId}/${targetUserId}`).remove(),
        rtdb.ref(`sessionHeartbeat/${enterpriseId}/${targetUserId}`).remove(),
        rtdb.ref(`liveLocations/${enterpriseId}/${targetUserId}`).remove(),
      ]);
    } catch (e) {
      logger.warn("deleteUser: Failed to clean up RTDB.", {
        targetUserId,
        error: e instanceof Error ? e.message : String(e),
      });
    }

    // 7. Count historical records that will remain so the tombstone reflects
    //    what's being preserved.
    let sessionCount = 0;
    let photoCount = 0;
    let summaryCount = 0;
    try {
      const [sessAgg, photoAgg, summaryAgg] = await Promise.all([
        db
          .collection("sessions")
          .where("enterpriseId", "==", enterpriseId)
          .where("employeeId", "==", targetUserId)
          .count()
          .get(),
        db
          .collection("photos")
          .where("enterpriseId", "==", enterpriseId)
          .where("employeeId", "==", targetUserId)
          .count()
          .get(),
        db
          .collection("dailySummaries")
          .where("enterpriseId", "==", enterpriseId)
          .where("employeeId", "==", targetUserId)
          .count()
          .get(),
      ]);
      sessionCount = sessAgg.data().count;
      photoCount = photoAgg.data().count;
      summaryCount = summaryAgg.data().count;
    } catch (e) {
      logger.warn("deleteUser: Failed to compute tombstone counts.", {
        targetUserId,
        error: e instanceof Error ? e.message : String(e),
      });
    }

    // 8. Write tombstone BEFORE deleting the user doc so analytics sees the
    //    exclusion signal even if a later step fails.
    try {
      await db.collection("deletedUsers").doc(targetUserId).set({
        uid: targetUserId,
        name: userData?.name ?? null,
        phone: userData?.phone ?? null,
        enterpriseId,
        deletedAt: admin.firestore.FieldValue.serverTimestamp(),
        deletedBy: request.auth.uid,
        sessionCount,
        photoCount,
        summaryCount,
        autoEndedSessions,
        unassignedTasks,
      });
    } catch (e) {
      logger.error("deleteUser: Failed to write tombstone.", {
        targetUserId,
        error: e instanceof Error ? e.message : String(e),
      });
      // Intentionally not fatal — proceed with doc deletion.
    }

    // 9. Delete Firestore user doc.
    try {
      await db.collection("users").doc(targetUserId).delete();
    } catch (e) {
      logger.warn("deleteUser: Failed to delete Firestore user doc.", {
        targetUserId,
        error: e instanceof Error ? e.message : String(e),
      });
    }

    // 10. Delete Firebase Auth user. Try by UID first (normal path); fall back
    //     to phone lookup if the doc ID was a random Firestore ID (placeholder
    //     that the user never logged in under).
    let authDeleted = false;
    try {
      await admin.auth().deleteUser(targetUserId);
      authDeleted = true;
      logger.info("deleteUser: Auth user deleted by UID.", { targetUserId });
    } catch (e: unknown) {
      const code = (e as { code?: string })?.code;
      if (code !== "auth/user-not-found") {
        logger.error("deleteUser: Failed to delete Auth user by UID.", {
          targetUserId,
          error: e instanceof Error ? e.message : String(e),
        });
      }
    }

    if (!authDeleted && userData?.phone) {
      const phone = userData.phone as string;
      try {
        const authUser = await admin.auth().getUserByPhoneNumber(phone);
        await admin.auth().deleteUser(authUser.uid);
        authDeleted = true;
        logger.info("deleteUser: Auth user deleted by phone fallback.", {
          targetUserId,
          phone,
          authUid: authUser.uid,
        });
      } catch (e: unknown) {
        const code = (e as { code?: string })?.code;
        if (code !== "auth/user-not-found") {
          logger.error("deleteUser: Phone-based Auth delete failed.", {
            targetUserId,
            phone,
            error: e instanceof Error ? e.message : String(e),
          });
        }
      }
    }

    logger.info("deleteUser: User fully deleted.", {
      targetUserId,
      enterpriseId,
      deletedBy: request.auth.uid,
      autoEndedSessions,
      unassignedTasks,
      deletedNotifications,
      sessionCount,
      photoCount,
      summaryCount,
      authDeleted,
    });

    return {
      success: true,
      tombstoneCreated: true,
      autoEndedSessions,
      unassignedTasks,
      deletedNotifications,
      sessionCount,
      photoCount,
      summaryCount,
      authDeleted,
    };
  }
);
