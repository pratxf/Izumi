/**
 * resolveUserOnLogin - HTTPS Callable
 *
 * Called by the Flutter client after phone auth to reliably resolve
 * a user by phone number using admin SDK privileges (bypasses
 * Firestore security rules race condition for new auth users).
 *
 * Logic:
 * 1. Require authentication with a phone number.
 * 2. Check if /users/{uid} already exists → return user data.
 * 3. Query /users where phone == callerPhone:
 *    - Found: migrate doc to /users/{uid}, merge roles, delete old doc,
 *      set custom claims, return user data.
 *    - Not found: return null (caller is a new user).
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { logger } from "firebase-functions/v2";

export const resolveUserOnLogin = onCall(
  { region: "asia-south1" },
  async (request) => {
    // Require authentication
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be authenticated.");
    }

    const uid = request.auth.uid;
    const phoneNumber = request.auth.token.phone_number as string | undefined;

    if (!phoneNumber) {
      throw new HttpsError(
        "failed-precondition",
        "No phone number associated with this account."
      );
    }

    const db = admin.firestore();

    // 1. Check if /users/{uid} already exists
    const uidDoc = await db.collection("users").doc(uid).get();
    if (uidDoc.exists) {
      let userData = uidDoc.data()!;
      logger.info("resolveUserOnLogin: User doc already exists at UID path.", {
        uid,
        enterpriseId: userData.enterpriseId,
      });

      // If UID doc has placeholder enterprise, check for admin-created doc by phone
      if (!userData.enterpriseId || userData.enterpriseId === "default_enterprise") {
        const phoneLookup = await db
          .collection("users")
          .where("phone", "==", phoneNumber)
          .get();

        // Find a doc that is NOT the UID doc and has a real enterpriseId
        const adminDoc = phoneLookup.docs.find(
          (d) =>
            d.id !== uid &&
            d.data().enterpriseId &&
            d.data().enterpriseId !== "default_enterprise"
        );

        if (adminDoc) {
          const adminData = adminDoc.data();
          const oldDocId = adminDoc.id;
          logger.info(
            "resolveUserOnLogin: Found admin-created doc, merging into UID doc.",
            { uid, oldDocId, enterpriseId: adminData.enterpriseId }
          );

          // Build roles from admin doc
          const roles: string[] = adminData.roles
            ? [...adminData.roles]
            : adminData.role
              ? [adminData.role]
              : ["employee"];
          const activeRole =
            adminData.activeRole || adminData.role || "employee";

          // Merge admin-created data into UID doc
          const mergedData = {
            ...userData,
            ...adminData,
            roles,
            activeRole,
            role: activeRole,
            migratedFrom: oldDocId,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          };
          await db.collection("users").doc(uid).set(mergedData);
          userData = mergedData;

          // Delete old admin-created doc
          try {
            await db.collection("users").doc(oldDocId).delete();
            logger.info("resolveUserOnLogin: Deleted old admin-created doc.", {
              oldDocId,
            });
          } catch (deleteErr) {
            logger.warn("resolveUserOnLogin: Could not delete old doc.", {
              oldDocId,
              error:
                deleteErr instanceof Error
                  ? deleteErr.message
                  : String(deleteErr),
            });
          }

          // Set custom claims with correct enterprise
          const customClaims: Record<string, unknown> = {
            roles,
            activeRole,
            role: activeRole,
            enterpriseId: adminData.enterpriseId || "",
          };
          if (adminData.groupId) {
            customClaims.groupId = adminData.groupId;
          }
          try {
            await admin.auth().setCustomUserClaims(uid, customClaims);
            logger.info("resolveUserOnLogin: Custom claims updated.", {
              uid,
              claims: customClaims,
            });
          } catch (claimsErr) {
            logger.error("resolveUserOnLogin: Failed to set claims.", {
              uid,
              error:
                claimsErr instanceof Error
                  ? claimsErr.message
                  : String(claimsErr),
            });
          }

          // Migrate tasks from old doc ID to UID
          const tasksSnapshot = await db
            .collection("tasks")
            .where("assignedTo", "==", oldDocId)
            .get();
          if (!tasksSnapshot.empty) {
            const batch = db.batch();
            for (const taskDoc of tasksSnapshot.docs) {
              batch.update(taskDoc.ref, {
                assignedTo: uid,
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              });
            }
            await batch.commit();
            logger.info(
              `resolveUserOnLogin: Migrated ${tasksSnapshot.size} tasks from admin doc.`,
              { uid, oldDocId }
            );
          }

          const finalDoc = await db.collection("users").doc(uid).get();
          return { found: true, user: { id: uid, ...finalDoc.data() } };
        }
      }

      // Ensure roles/activeRole fields exist (backward compat migration)
      if (!userData.roles && userData.role) {
        await db.collection("users").doc(uid).update({
          roles: [userData.role],
          activeRole: userData.role,
        });
        userData.roles = [userData.role];
        userData.activeRole = userData.role;
      }

      // Check for orphaned tasks from pre-migration ID
      const migratedFrom = userData.migratedFrom as string | undefined;
      if (migratedFrom) {
        const orphanedTasks = await db
          .collection("tasks")
          .where("assignedTo", "==", migratedFrom)
          .get();
        if (!orphanedTasks.empty) {
          const batch = db.batch();
          for (const taskDoc of orphanedTasks.docs) {
            batch.update(taskDoc.ref, {
              assignedTo: uid,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
          }
          await batch.commit();
          logger.info(
            `resolveUserOnLogin: Migrated ${orphanedTasks.size} orphaned tasks.`,
            { uid, migratedFrom }
          );
        }
      }

      return { found: true, user: { id: uid, ...userData } };
    }

    // 2. Query by phone number (admin SDK bypasses security rules)
    const phoneLookup = await db
      .collection("users")
      .where("phone", "==", phoneNumber)
      .limit(1)
      .get();

    if (phoneLookup.empty) {
      logger.info(
        "resolveUserOnLogin: No user doc found for phone. New user.",
        { uid, phoneNumber }
      );
      return { found: false, user: null };
    }

    // 3. Found a pre-created doc — migrate to /users/{uid}
    const existingDoc = phoneLookup.docs[0];
    const existingData = existingDoc.data();
    const oldDocId = existingDoc.id;

    // Build roles array from existing data
    const roles: string[] = existingData.roles
      ? [...existingData.roles]
      : existingData.role
        ? [existingData.role]
        : ["employee"];
    const activeRole =
      existingData.activeRole || existingData.role || "employee";

    // Create new doc at UID path
    const migratedData = {
      ...existingData,
      roles,
      activeRole,
      role: activeRole, // backward compat
      migratedFrom: oldDocId,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    await db.collection("users").doc(uid).set(migratedData);

    // Delete the old doc
    try {
      await db.collection("users").doc(oldDocId).delete();
      logger.info("resolveUserOnLogin: Deleted old pre-created doc.", {
        oldDocId,
      });
    } catch (deleteErr) {
      logger.warn("resolveUserOnLogin: Could not delete old doc.", {
        oldDocId,
        error:
          deleteErr instanceof Error ? deleteErr.message : String(deleteErr),
      });
    }

    // Set custom claims
    const customClaims: Record<string, unknown> = {
      roles,
      activeRole,
      role: activeRole, // backward compat
      enterpriseId: existingData.enterpriseId || "",
    };
    if (existingData.groupId) {
      customClaims.groupId = existingData.groupId;
    }

    try {
      await admin.auth().setCustomUserClaims(uid, customClaims);
      logger.info("resolveUserOnLogin: Custom claims set.", {
        uid,
        claims: customClaims,
      });
    } catch (claimsErr) {
      logger.error("resolveUserOnLogin: Failed to set claims.", {
        uid,
        error:
          claimsErr instanceof Error ? claimsErr.message : String(claimsErr),
      });
    }

    // Migrate tasks from old doc ID to new UID
    const tasksSnapshot = await db
      .collection("tasks")
      .where("assignedTo", "==", oldDocId)
      .get();

    if (!tasksSnapshot.empty) {
      const batch = db.batch();
      for (const taskDoc of tasksSnapshot.docs) {
        batch.update(taskDoc.ref, {
          assignedTo: uid,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
      logger.info(
        `resolveUserOnLogin: Migrated ${tasksSnapshot.size} tasks.`,
        { uid, oldDocId }
      );
    }

    // Read the final migrated doc
    const finalDoc = await db.collection("users").doc(uid).get();

    return { found: true, user: { id: uid, ...finalDoc.data() } };
  }
);
