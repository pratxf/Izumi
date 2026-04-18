/**
 * checkPhoneCollision - HTTPS Callable (admin only)
 *
 * Before the admin creates a new user doc, probe whether the phone is
 * already attached to a Firebase Auth record and/or an existing user doc.
 * Returns a structured verdict the client can use to render a clear
 * confirm/abort dialog — never silently nukes another account.
 *
 * Verdicts:
 *   none             — no Auth record, no doc in this enterprise. Safe to create.
 *   sameEnterpriseDoc — a Firestore user doc already exists in this enterprise.
 *                       (Client already catches this — returned for completeness.)
 *   orphanAuthSameEnterprise — Auth record has enterpriseId claim matching
 *                       ours but no Firestore doc anywhere. The AddUser dialog
 *                       should offer to clean it up.
 *   otherEnterpriseAuth — Auth record exists but belongs to a different
 *                       enterprise (claims or Firestore doc). Do NOT allow
 *                       cleanup — operator must resolve outside this screen.
 *   unknownAuth      — Auth record exists with no enterprise claim and no
 *                       Firestore doc in any enterprise. Treat as an orphan
 *                       owned by no one; client decides (same UX as
 *                       orphanAuthSameEnterprise).
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

type Verdict =
  | "none"
  | "sameEnterpriseDoc"
  | "orphanAuthSameEnterprise"
  | "otherEnterpriseAuth"
  | "unknownAuth";

export const checkPhoneCollision = onCall(
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

    const phone = request.data?.phone as string | undefined;
    if (!phone) throw new HttpsError("invalid-argument", "phone required");

    const db = admin.firestore();

    // 1. Firestore doc in THIS enterprise?
    const sameEnt = await db
      .collection("users")
      .where("phone", "==", phone)
      .where("enterpriseId", "==", callerEnterpriseId)
      .limit(1)
      .get();

    // 2. Auth record for this phone?
    let authUid: string | null = null;
    let authEnterpriseIdClaim: string | null = null;
    let authDisplayName: string | null = null;
    try {
      const au = await admin.auth().getUserByPhoneNumber(phone);
      authUid = au.uid;
      authDisplayName = au.displayName || null;
      const claims = au.customClaims || {};
      authEnterpriseIdClaim =
        typeof claims.enterpriseId === "string" ? claims.enterpriseId : null;
    } catch (e) {
      const code = (e as { code?: string })?.code;
      if (code !== "auth/user-not-found") throw e;
    }

    // 3. Does Auth uid have a Firestore doc? If so, which enterprise?
    let authDocEnterpriseId: string | null = null;
    if (authUid) {
      const doc = await db.collection("users").doc(authUid).get();
      if (doc.exists) {
        authDocEnterpriseId =
          (doc.data()?.enterpriseId as string | undefined) ?? null;
      }
    }

    let verdict: Verdict;
    let message: string;
    if (!sameEnt.empty) {
      verdict = "sameEnterpriseDoc";
      message = "A user with this phone already exists in your enterprise.";
    } else if (!authUid) {
      verdict = "none";
      message = "Phone is free.";
    } else if (
      authDocEnterpriseId &&
      authDocEnterpriseId !== callerEnterpriseId
    ) {
      verdict = "otherEnterpriseAuth";
      message =
        "This phone number is already in use by another account in a different enterprise.";
    } else if (
      authEnterpriseIdClaim &&
      authEnterpriseIdClaim !== callerEnterpriseId
    ) {
      verdict = "otherEnterpriseAuth";
      message =
        "This phone number is already in use by another account in a different enterprise.";
    } else if (authEnterpriseIdClaim === callerEnterpriseId) {
      verdict = "orphanAuthSameEnterprise";
      message =
        "An old account exists for this phone in your enterprise but its user record was removed. Clean up and create fresh?";
    } else {
      verdict = "unknownAuth";
      message =
        "A Firebase Auth record exists for this phone but is not linked to any enterprise. Clean up and create fresh?";
    }

    return {
      verdict,
      message,
      authUid,
      authEnterpriseIdClaim,
      authDocEnterpriseId,
      authDisplayName,
    };
  }
);
