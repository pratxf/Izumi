/**
 * updateUser - HTTPS Callable
 *
 * Admin-only atomic edit: name, phone, and/or role in one server round-trip.
 * Enforces phone uniqueness within the enterprise, pre-checks Firebase Auth
 * for phone collisions with a clear error (never a raw Firebase error), and
 * keeps Firestore + Auth custom claims + Auth phone number + group/chat
 * membership aligned.
 *
 * Request shape:
 *   { targetUserId: string, name?: string, phone?: string, role?: string }
 *
 * Only fields present in the request are touched. If the admin just renames
 * a user, no role/claim/group work happens.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { logger } from "firebase-functions/v2";
import { syncRoleAndGroups } from "./_user_sync_helpers";

const VALID_ROLES = ["employee", "team_lead", "admin"];

export const updateUser = onCall(
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

    const targetUserId = request.data?.targetUserId as string | undefined;
    if (!targetUserId) {
      throw new HttpsError("invalid-argument", "targetUserId is required.");
    }

    const nameRaw = request.data?.name;
    const phoneRaw = request.data?.phone;
    const roleRaw = request.data?.role;

    const nextName =
      typeof nameRaw === "string" ? nameRaw.trim() : undefined;
    const nextPhone =
      typeof phoneRaw === "string" ? phoneRaw.trim() : undefined;
    const nextRole = typeof roleRaw === "string" ? roleRaw : undefined;

    if (nextName === undefined && nextPhone === undefined && nextRole === undefined) {
      throw new HttpsError(
        "invalid-argument",
        "At least one of name, phone, or role must be provided."
      );
    }
    if (nextName !== undefined && nextName.length === 0) {
      throw new HttpsError("invalid-argument", "Name cannot be empty.");
    }
    if (nextPhone !== undefined && nextPhone.length === 0) {
      throw new HttpsError("invalid-argument", "Phone cannot be empty.");
    }
    if (nextRole !== undefined && !VALID_ROLES.includes(nextRole)) {
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
      throw new HttpsError(
        "permission-denied",
        "Cannot modify users outside your enterprise."
      );
    }

    const currentPhone = (targetData.phone as string | undefined) ?? "";
    const phoneChanged = nextPhone !== undefined && nextPhone !== currentPhone;

    // Phone uniqueness within this enterprise (excluding self).
    if (phoneChanged) {
      const conflict = await db
        .collection("users")
        .where("phone", "==", nextPhone)
        .where("enterpriseId", "==", targetEnterpriseId)
        .get();
      const others = conflict.docs.filter((d) => d.id !== targetUserId);
      if (others.length > 0) {
        throw new HttpsError(
          "already-exists",
          "Another user in your enterprise already uses this phone number."
        );
      }

      // Pre-check Firebase Auth for a phone collision before trying the
      // update, so we return a human-readable message rather than bubbling
      // auth/phone-number-already-exists.
      try {
        const owner = await admin.auth().getUserByPhoneNumber(nextPhone);
        if (owner.uid !== targetUserId) {
          throw new HttpsError(
            "already-exists",
            "This phone number is already in use by another account."
          );
        }
      } catch (e) {
        const code = (e as { code?: string })?.code;
        if (
          code &&
          code !== "auth/user-not-found" &&
          !(e instanceof HttpsError)
        ) {
          throw e;
        }
        if (e instanceof HttpsError) throw e;
      }
    }

    const updates: Record<string, unknown> = {
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (nextName !== undefined) updates.name = nextName;
    if (nextPhone !== undefined) updates.phone = nextPhone;

    const roleChanged =
      nextRole !== undefined && nextRole !== (targetData.activeRole as string | undefined);
    if (roleChanged) {
      updates.roles = [nextRole];
      updates.activeRole = nextRole;
      updates.role = nextRole;
    }

    await targetRef.update(updates);

    // Keep Firebase Auth phone in sync. Pre-check above already ruled out
    // collisions; treat auth/user-not-found as a non-fatal (placeholder
    // doc that has not logged in yet) — Auth phone lands on first login.
    let authPhoneUpdated = false;
    if (phoneChanged) {
      try {
        await admin.auth().updateUser(targetUserId, { phoneNumber: nextPhone });
        authPhoneUpdated = true;
      } catch (e) {
        const code = (e as { code?: string })?.code;
        if (code === "auth/user-not-found") {
          logger.info(
            "updateUser: Auth user not found; phone will land on first login.",
            { targetUserId }
          );
        } else if (code === "auth/phone-number-already-exists") {
          // Extremely narrow race: pre-check passed but another write won.
          throw new HttpsError(
            "already-exists",
            "This phone number is already in use by another account."
          );
        } else {
          throw e;
        }
      }
    }

    // Keep custom claims in sync whenever role changes. We also refresh
    // claims when phone changes — the phone isn't a claim, but the token
    // must be re-issued for the Auth update to propagate; setCustomUserClaims
    // is the cheapest way to invalidate existing tokens deterministically.
    let claimsUpdated = false;
    if (roleChanged || phoneChanged) {
      const afterRoleDoc = await targetRef.get();
      const afterData = afterRoleDoc.data() ?? targetData;
      const claims: Record<string, unknown> = {
        roles: afterData.roles ?? [afterData.activeRole ?? "employee"],
        activeRole: afterData.activeRole ?? "employee",
        role: afterData.activeRole ?? afterData.role ?? "employee",
        enterpriseId: targetEnterpriseId,
      };
      if (afterData.groupId) claims.groupId = afterData.groupId;
      try {
        await admin.auth().setCustomUserClaims(targetUserId, claims);
        claimsUpdated = true;
      } catch (e) {
        const code = (e as { code?: string })?.code;
        if (code !== "auth/user-not-found") throw e;
        logger.warn("updateUser: Auth user not found; claims not set.", {
          targetUserId,
        });
      }
    }

    let syncResult = {
      groupSyncApplied: false,
      chatSyncApplied: false,
      affectedGroupIds: [] as string[],
    };
    if (roleChanged) {
      const refreshed = await targetRef.get();
      syncResult = await syncRoleAndGroups(
        db,
        targetUserId,
        targetEnterpriseId,
        refreshed.data() ?? targetData,
        nextRole!
      );
    }

    logger.info("updateUser: applied.", {
      targetUserId,
      enterpriseId: targetEnterpriseId,
      nameChanged: nextName !== undefined && nextName !== targetData.name,
      phoneChanged,
      roleChanged,
      authPhoneUpdated,
      claimsUpdated,
      ...syncResult,
    });

    return {
      success: true,
      targetUserId,
      authPhoneUpdated,
      claimsUpdated,
      ...syncResult,
    };
  }
);
