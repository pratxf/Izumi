/**
 * onUserCreate - Firestore Trigger
 *
 * Triggered when a new document is created in /users/{userId}.
 * Sets Firebase Auth custom claims (roles, activeRole, enterpriseId, groupId)
 * on the corresponding Firebase Auth user so that security rules
 * and client-side routing can rely on token claims.
 */

import { onDocumentCreated } from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";
import { logger } from "firebase-functions/v2";

/** Shape of the user document as stored in Firestore. */
interface UserDocument {
  name: string;
  phone: string;
  email?: string;
  role?: "employee" | "team_lead" | "admin";
  roles?: string[];
  activeRole?: string;
  enterpriseId: string;
  groupId?: string;
  fcmToken?: string;
  profileImageUrl?: string;
  migratedFrom?: string;
  createdAt: admin.firestore.Timestamp;
  updatedAt: admin.firestore.Timestamp;
}

export const onUserCreate = onDocumentCreated(
  {
    document: "users/{userId}",
    region: "asia-south1",
  },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) {
      logger.warn("onUserCreate: No data in event, skipping.");
      return;
    }

    const userId = event.params.userId;
    const userData = snapshot.data() as UserDocument;

    // Build roles array with backward compatibility
    const roles: string[] = userData.roles
      ? [...userData.roles]
      : userData.role
        ? [userData.role]
        : ["employee"];
    const activeRole =
      userData.activeRole || userData.role || "employee";

    // Validate required fields before setting claims
    if (roles.length === 0 || !userData.enterpriseId) {
      logger.error(
        "onUserCreate: Missing required fields (roles or enterpriseId).",
        { userId, roles, enterpriseId: userData.enterpriseId }
      );
      return;
    }

    // Validate role values
    const validRoles = ["employee", "team_lead", "admin"];
    for (const r of roles) {
      if (!validRoles.includes(r)) {
        logger.error("onUserCreate: Invalid role value.", {
          userId,
          role: r,
        });
        return;
      }
    }

    // Build custom claims object
    const customClaims: Record<string, unknown> = {
      roles,
      activeRole,
      role: activeRole, // backward compat
      enterpriseId: userData.enterpriseId,
    };

    if (userData.groupId) {
      customClaims.groupId = userData.groupId;
    }

    try {
      // Verify the Firebase Auth user exists before setting claims
      await admin.auth().getUser(userId);

      // Set custom claims on the Firebase Auth user
      await admin.auth().setCustomUserClaims(userId, customClaims);

      logger.info("onUserCreate: Custom claims set successfully.", {
        userId,
        claims: customClaims,
      });

      // Ensure roles/activeRole fields are written to Firestore doc
      const updateFields: Record<string, unknown> = {
        claimsSetAt: admin.firestore.FieldValue.serverTimestamp(),
      };
      if (!userData.roles) {
        updateFields.roles = roles;
        updateFields.activeRole = activeRole;
      }
      await admin.firestore().collection("users").doc(userId).update(updateFields);

      // Migrate tasks if this user was migrated from a pre-created doc
      if (userData.migratedFrom) {
        const oldDocId = userData.migratedFrom;
        const tasksSnapshot = await admin
          .firestore()
          .collection("tasks")
          .where("assignedTo", "==", oldDocId)
          .get();

        if (!tasksSnapshot.empty) {
          const batch = admin.firestore().batch();
          for (const taskDoc of tasksSnapshot.docs) {
            batch.update(taskDoc.ref, {
              assignedTo: userId,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
          }
          await batch.commit();
          logger.info(
            `onUserCreate: Migrated ${tasksSnapshot.size} tasks from old ID to new UID.`,
            { userId, oldDocId }
          );
        }

        // Clean up the migratedFrom field
        await admin.firestore().collection("users").doc(userId).update({
          migratedFrom: admin.firestore.FieldValue.delete(),
        });
      }
    } catch (error) {
      if (
        error instanceof Error &&
        "code" in error &&
        (error as unknown as admin.FirebaseError).code === "auth/user-not-found"
      ) {
        logger.error(
          "onUserCreate: Firebase Auth user not found. " +
            "The Firestore document was created but the Auth user does not exist.",
          { userId }
        );
      } else {
        logger.error("onUserCreate: Failed to set custom claims.", {
          userId,
          error: error instanceof Error ? error.message : String(error),
        });
      }
      throw error;
    }
  }
);
