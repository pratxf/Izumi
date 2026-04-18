/**
 * adminCleanup - One-time callable to fix stuck users.
 * Delete after use.
 */
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { logger } from "firebase-functions/v2";

export const adminCleanup = onCall(
  { region: "asia-south1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be authenticated.");
    }
    const callerRole = request.auth.token.activeRole || request.auth.token.role;
    if (callerRole !== "admin") {
      throw new HttpsError("permission-denied", "Admin only.");
    }

    const phone = request.data?.phone as string | undefined;
    const name = request.data?.name as string | undefined;
    const role = request.data?.role as string || "employee";
    const deleteOnly = request.data?.deleteOnly === true;
    const enterpriseId = request.auth.token.enterpriseId as string;

    if (!phone) throw new HttpsError("invalid-argument", "phone required");
    if (!enterpriseId) {
      throw new HttpsError(
        "failed-precondition",
        "No enterpriseId in caller claims."
      );
    }

    const db = admin.firestore();
    const results: string[] = [];

    // 1. Delete Auth user by phone — but only if they belong to THIS
    //    enterprise. The Auth record itself has no enterprise metadata, so
    //    we gate on the presence of a user doc in our enterprise OR on the
    //    Auth user's custom claim. This prevents one enterprise's admin from
    //    nuking another enterprise's Auth user that happens to share a phone.
    try {
      const authUser = await admin.auth().getUserByPhoneNumber(phone);
      const authClaims = authUser.customClaims || {};
      const claimsEnterpriseMatch =
        authClaims.enterpriseId === enterpriseId;
      const uidDoc = await db.collection("users").doc(authUser.uid).get();
      const uidDocEnterpriseMatch =
        uidDoc.exists && uidDoc.data()?.enterpriseId === enterpriseId;

      if (claimsEnterpriseMatch || uidDocEnterpriseMatch || !uidDoc.exists) {
        // Safe to delete: either the Auth user is explicitly in this
        // enterprise, or it's an orphan Auth record with no Firestore doc
        // anywhere (pure zombie — allowed to clean up).
        await admin.auth().deleteUser(authUser.uid);
        results.push(`Deleted Auth user: ${authUser.uid}`);

        if (uidDoc.exists) {
          await db.collection("users").doc(authUser.uid).delete();
          results.push(`Deleted UID doc: ${authUser.uid}`);
        }
      } else {
        results.push(
          `Skipped Auth user ${authUser.uid} — belongs to a different enterprise`
        );
      }
    } catch (e) {
      results.push(`No Auth user for ${phone}`);
    }

    // 2. Delete stale docs with this phone — scoped to THIS enterprise only.
    const stale = await db
      .collection("users")
      .where("phone", "==", phone)
      .where("enterpriseId", "==", enterpriseId)
      .get();
    for (const doc of stale.docs) {
      await doc.ref.delete();
      results.push(`Deleted stale doc: ${doc.id}`);
    }

    // 3. Create fresh doc (skip if deleteOnly)
    if (deleteOnly) {
      logger.info("adminCleanup completed (deleteOnly)", { phone, results });
      return { success: true, results };
    }
    const ref = db.collection("users").doc();
    await ref.set({
      name: name || "Employee",
      phone,
      roles: [role],
      activeRole: role,
      role,
      enterpriseId,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    results.push(`Created ${role} doc: ${ref.id}`);

    logger.info("adminCleanup completed", { phone, results });
    return { success: true, results };
  }
);
