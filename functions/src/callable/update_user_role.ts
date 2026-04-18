/**
 * updateUserRole - HTTPS Callable
 *
 * Admin-only role update for an existing user. Keeps Firestore user role
 * fields and Firebase Auth custom claims in sync, and propagates the role
 * change into groups/chatGroups via syncRoleAndGroups.
 *
 * Kept single-purpose for the AddUser "role conflict" replace path.
 * Full-edit flows use the updateUser callable instead.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { logger } from "firebase-functions/v2";
import { syncRoleAndGroups } from "./_user_sync_helpers";

const VALID_ROLES = ["employee", "team_lead", "admin"];

export const updateUserRole = onCall(
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
      throw new HttpsError("permission-denied", "Only admins can update roles.");
    }

    const callerEnterpriseId = request.auth.token.enterpriseId as string | undefined;
    if (!callerEnterpriseId) {
      throw new HttpsError("failed-precondition", "No enterpriseId in caller claims.");
    }

    const targetUserId = request.data?.targetUserId as string | undefined;
    const newRole = request.data?.newRole as string | undefined;
    if (!targetUserId || !newRole) {
      throw new HttpsError("invalid-argument", "targetUserId and newRole are required.");
    }
    if (!VALID_ROLES.includes(newRole)) {
      throw new HttpsError("invalid-argument", "Invalid role value.");
    }

    const db = admin.firestore();
    const targetRef = db.collection("users").doc(targetUserId);
    const targetDoc = await targetRef.get();
    if (!targetDoc.exists) {
      throw new HttpsError("not-found", "Target user not found.");
    }

    const targetData = targetDoc.data()!;
    const targetEnterpriseId = targetData.enterpriseId as string | undefined;
    if (!targetEnterpriseId || targetEnterpriseId !== callerEnterpriseId) {
      throw new HttpsError("permission-denied", "Cannot modify users outside your enterprise.");
    }

    await targetRef.update({
      roles: [newRole],
      activeRole: newRole,
      role: newRole,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    const customClaims: Record<string, unknown> = {
      roles: [newRole],
      activeRole: newRole,
      role: newRole,
      enterpriseId: targetEnterpriseId,
    };
    if (targetData.groupId) {
      customClaims.groupId = targetData.groupId;
    }

    let claimsUpdated = false;
    try {
      await admin.auth().setCustomUserClaims(targetUserId, customClaims);
      claimsUpdated = true;
    } catch (error) {
      const authError = error as { code?: string; message?: string };
      if (authError.code !== "auth/user-not-found") {
        throw error;
      }
      logger.warn("updateUserRole: Firebase Auth user not found; claims not set.", {
        targetUserId,
      });
    }

    const syncResult = await syncRoleAndGroups(
      db,
      targetUserId,
      targetEnterpriseId,
      targetData,
      newRole
    );

    logger.info("updateUserRole: Role updated.", {
      targetUserId,
      newRole,
      enterpriseId: targetEnterpriseId,
      claimsUpdated,
      ...syncResult,
    });

    return {
      success: true,
      targetUserId,
      roles: [newRole],
      activeRole: newRole,
      claimsUpdated,
      ...syncResult,
    };
  }
);
