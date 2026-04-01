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

    const db = admin.firestore();
    const results: string[] = [];

    // 1. Delete Auth user by phone
    try {
      const authUser = await admin.auth().getUserByPhoneNumber(phone);
      await admin.auth().deleteUser(authUser.uid);
      results.push(`Deleted Auth user: ${authUser.uid}`);

      // Delete UID doc
      const uidDoc = await db.collection("users").doc(authUser.uid).get();
      if (uidDoc.exists) {
        await db.collection("users").doc(authUser.uid).delete();
        results.push(`Deleted UID doc: ${authUser.uid}`);
      }
    } catch (e) {
      results.push(`No Auth user for ${phone}`);
    }

    // 2. Delete all stale docs with this phone
    const stale = await db.collection("users").where("phone", "==", phone).get();
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
