/**
 * ensureClaims - HTTPS Callable
 *
 * Called by the client when custom claims are missing from the ID token.
 * Reads the user's Firestore doc and sets custom claims from it.
 * This handles users who were created before the onUserCreate Cloud Function
 * was deployed, or cases where claims were lost/never set.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { logger } from "firebase-functions/v2";

export const ensureClaims = onCall(
  { region: "asia-south1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be authenticated.");
    }

    const uid = request.auth.uid;
    const db = admin.firestore();

    // Read user doc
    const userDoc = await db.collection("users").doc(uid).get();
    if (!userDoc.exists) {
      logger.warn("ensureClaims: No user doc found.", { uid });
      throw new HttpsError("not-found", "User document not found.");
    }

    const userData = userDoc.data()!;

    // Build roles
    const roles: string[] = userData.roles
      ? [...userData.roles]
      : userData.role
        ? [userData.role]
        : ["employee"];
    const activeRole =
      userData.activeRole || userData.role || "employee";

    if (!userData.enterpriseId) {
      logger.warn("ensureClaims: No enterpriseId in user doc.", { uid });
      throw new HttpsError(
        "failed-precondition",
        "User document has no enterpriseId."
      );
    }

    // Build and set custom claims
    const customClaims: Record<string, unknown> = {
      roles,
      activeRole,
      role: activeRole,
      enterpriseId: userData.enterpriseId,
    };

    if (userData.groupId) {
      customClaims.groupId = userData.groupId;
    }

    // Check if claims already match desired values
    const existingUser = await admin.auth().getUser(uid);
    const existingClaims = existingUser.customClaims || {};
    const existingRoles = Array.isArray(existingClaims.roles)
      ? [...(existingClaims.roles as string[])].sort()
      : [];
    const desiredRoles = [...roles].sort();
    const rolesMatch =
      existingRoles.length === desiredRoles.length &&
      existingRoles.every((r, i) => r === desiredRoles[i]);
    const activeRoleMatch = existingClaims.activeRole === activeRole;
    const enterpriseMatch = existingClaims.enterpriseId === userData.enterpriseId;
    const groupMatch =
      (existingClaims.groupId || null) === (userData.groupId || null);

    if (rolesMatch && activeRoleMatch && enterpriseMatch && groupMatch) {
      logger.info("ensureClaims: Claims already in sync, skipping.", { uid });
      return { updated: false, claims: existingClaims };
    }

    await admin.auth().setCustomUserClaims(uid, customClaims);

    // Mark claims as set
    await db.collection("users").doc(uid).update({
      claimsSetAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    logger.info("ensureClaims: Custom claims set.", { uid, claims: customClaims });

    return { updated: true, claims: customClaims };
  }
);
