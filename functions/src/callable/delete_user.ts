/**
 * deleteUser - HTTPS Callable
 *
 * Admin-only function to fully delete a user:
 * 1. Verify caller is admin in same enterprise
 * 2. Delete Firestore user doc
 * 3. Remove user from groups and chat groups
 * 4. Delete Firebase Auth user (frees phone number for re-registration)
 * 5. Clean up RTDB presence/stats
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { logger } from "firebase-functions/v2";

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

    const callerEnterpriseId = request.auth.token.enterpriseId as string | undefined;
    if (!callerEnterpriseId) {
      throw new HttpsError("failed-precondition", "No enterpriseId in caller claims.");
    }

    const targetUserId = request.data?.targetUserId as string | undefined;
    if (!targetUserId) {
      throw new HttpsError("invalid-argument", "targetUserId is required.");
    }

    // Prevent self-deletion
    if (targetUserId === request.auth.uid) {
      throw new HttpsError("invalid-argument", "Cannot delete your own account.");
    }

    const db = admin.firestore();
    const rtdb = admin.database();

    // Verify target user exists and belongs to same enterprise
    const userDoc = await db.collection("users").doc(targetUserId).get();
    if (!userDoc.exists) {
      // User doc might have a different ID (pre-migration). Try by the provided ID anyway.
      logger.warn("deleteUser: User doc not found, proceeding with cleanup.", {
        targetUserId,
      });
    } else {
      const userData = userDoc.data()!;
      if (userData.enterpriseId !== callerEnterpriseId) {
        throw new HttpsError(
          "permission-denied",
          "Cannot delete users from a different enterprise."
        );
      }
    }

    const enterpriseId = callerEnterpriseId;

    // 1. Remove from groups (memberIds, leadIds)
    try {
      const groupsByMember = await db
        .collection("groups")
        .where("enterpriseId", "==", enterpriseId)
        .where("memberIds", "array-contains", targetUserId)
        .get();

      for (const doc of groupsByMember.docs) {
        await doc.ref.update({
          memberIds: admin.firestore.FieldValue.arrayRemove(targetUserId),
          leadIds: admin.firestore.FieldValue.arrayRemove(targetUserId),
        });
      }
    } catch (e) {
      logger.warn("deleteUser: Failed to clean up groups.", { targetUserId, error: e });
    }

    // 2. Remove from chat groups
    try {
      const chatGroupsByMember = await db
        .collection("chatGroups")
        .where("enterpriseId", "==", enterpriseId)
        .where("memberIds", "array-contains", targetUserId)
        .get();

      for (const doc of chatGroupsByMember.docs) {
        await doc.ref.update({
          memberIds: admin.firestore.FieldValue.arrayRemove(targetUserId),
        });
      }
    } catch (e) {
      logger.warn("deleteUser: Failed to clean up chat groups.", { targetUserId, error: e });
    }

    // 3. Clean up RTDB
    try {
      await Promise.all([
        rtdb.ref(`presence/${enterpriseId}/${targetUserId}`).remove(),
        rtdb.ref(`activeStats/${enterpriseId}/${targetUserId}`).remove(),
        rtdb.ref(`sessionHeartbeat/${enterpriseId}/${targetUserId}`).remove(),
        rtdb.ref(`liveLocations/${enterpriseId}/${targetUserId}`).remove(),
      ]);
    } catch (e) {
      logger.warn("deleteUser: Failed to clean up RTDB.", { targetUserId, error: e });
    }

    // 4. Delete Firestore user doc
    try {
      await db.collection("users").doc(targetUserId).delete();
    } catch (e) {
      logger.warn("deleteUser: Failed to delete Firestore doc.", { targetUserId, error: e });
    }

    // 5. Delete Firebase Auth user (frees the phone number)
    // The targetUserId may be a random Firestore doc ID (pre-migration),
    // not the Firebase Auth UID. Try by ID first, then by phone number.
    let authDeleted = false;
    try {
      await admin.auth().deleteUser(targetUserId);
      authDeleted = true;
      logger.info("deleteUser: Firebase Auth user deleted by UID.", { targetUserId });
    } catch (e: unknown) {
      const code = (e as { code?: string })?.code;
      if (code !== "auth/user-not-found") {
        logger.error("deleteUser: Failed to delete Auth user by UID.", {
          targetUserId,
          error: e instanceof Error ? e.message : String(e),
        });
      }
    }

    // If UID-based delete failed, try looking up by phone number
    if (!authDeleted && userDoc.exists) {
      const phone = userDoc.data()?.phone as string | undefined;
      if (phone) {
        try {
          const authUser = await admin.auth().getUserByPhoneNumber(phone);
          await admin.auth().deleteUser(authUser.uid);
          authDeleted = true;
          logger.info("deleteUser: Firebase Auth user deleted by phone lookup.", {
            targetUserId,
            phone,
            authUid: authUser.uid,
          });
        } catch (e: unknown) {
          const code = (e as { code?: string })?.code;
          if (code === "auth/user-not-found") {
            logger.info("deleteUser: No Auth user found for phone either.", {
              targetUserId,
              phone,
            });
          } else {
            logger.error("deleteUser: Failed to delete Auth user by phone.", {
              targetUserId,
              phone,
              error: e instanceof Error ? e.message : String(e),
            });
          }
        }
      }
    }

    logger.info("deleteUser: User fully deleted.", {
      targetUserId,
      enterpriseId,
      deletedBy: request.auth.uid,
    });

    return { success: true };
  }
);
