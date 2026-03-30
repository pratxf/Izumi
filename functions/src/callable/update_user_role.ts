/**
 * updateUserRole - HTTPS Callable
 *
 * Admin-only role update for an existing user. Keeps Firestore user role fields
 * and Firebase Auth custom claims in sync so security rules and routing reflect
 * the latest role immediately after token refresh.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { logger } from "firebase-functions/v2";

const VALID_ROLES = ["employee", "team_lead", "admin"];

function stringList(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.filter((item): item is string => typeof item === "string");
}

type GroupSnapshot = FirebaseFirestore.QueryDocumentSnapshot<FirebaseFirestore.DocumentData> |
FirebaseFirestore.DocumentSnapshot<FirebaseFirestore.DocumentData>;

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

    const updatedFields: Record<string, unknown> = {
      roles: [newRole],
      activeRole: newRole,
      role: newRole,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    await targetRef.update(updatedFields);

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

    let groupSyncApplied = false;
    let chatSyncApplied = false;
    const affectedGroupIds = new Set<string>();

    const candidateGroupDocs = new Map<string, GroupSnapshot>();
    const targetGroupId = typeof targetData.groupId === "string" ? targetData.groupId : "";
    if (targetGroupId) {
      const groupDoc = await db.collection("groups").doc(targetGroupId).get();
      if (groupDoc.exists) {
        candidateGroupDocs.set(groupDoc.id, groupDoc);
      }
    }

    const memberGroups = await db
      .collection("groups")
      .where("enterpriseId", "==", targetEnterpriseId)
      .where("memberIds", "array-contains", targetUserId)
      .get();
    for (const doc of memberGroups.docs) {
      candidateGroupDocs.set(doc.id, doc);
    }

    if (newRole !== "team_lead") {
      const leadGroups = await db
        .collection("groups")
        .where("enterpriseId", "==", targetEnterpriseId)
        .where("leadIds", "array-contains", targetUserId)
        .get();
      for (const doc of leadGroups.docs) {
        candidateGroupDocs.set(doc.id, doc);
      }
    }

    for (const groupDoc of candidateGroupDocs.values()) {
      if (!groupDoc.exists) continue;
      const groupData = groupDoc.data()!;
      const groupEnterpriseId = groupData.enterpriseId as string | undefined;
      if (groupEnterpriseId !== targetEnterpriseId) {
        logger.warn("updateUserRole: Skipping group sync outside target enterprise.", {
          targetUserId,
          targetGroupId: groupDoc.id,
          targetEnterpriseId,
          groupEnterpriseId,
        });
        continue;
      }

      const currentLeadIds = stringList(groupData.leadIds);
      const nextLeadIds =
        newRole === "team_lead"
          ? Array.from(new Set([...currentLeadIds, targetUserId]))
          : currentLeadIds.filter((id) => id !== targetUserId);

      const leadIdsChanged =
        nextLeadIds.length !== currentLeadIds.length ||
        nextLeadIds.some((id, index) => id !== currentLeadIds[index]);

      if (leadIdsChanged) {
        await groupDoc.ref.update({
          leadIds: nextLeadIds,
          leadId: nextLeadIds.length > 0 ? nextLeadIds[0] : "",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      groupSyncApplied = true;
      affectedGroupIds.add(groupDoc.id);

      let linkedChatSnapshot = await db
        .collection("chatGroups")
        .where("linkedGroupId", "==", groupDoc.id)
        .limit(1)
        .get();

      if (linkedChatSnapshot.empty &&
          typeof groupData.name === "string" &&
          groupData.name.trim().length > 0) {
        linkedChatSnapshot = await db
          .collection("chatGroups")
          .where("enterpriseId", "==", targetEnterpriseId)
          .where("name", "==", groupData.name.trim())
          .limit(1)
          .get();
      }

      if (linkedChatSnapshot.empty) {
        continue;
      }

      const chatDoc = linkedChatSnapshot.docs[0];
      const chatData = chatDoc.data();
      const memberIds = stringList(groupData.memberIds);
      const normalizedMembers = Array.from(new Set<string>([
        ...memberIds,
        ...nextLeadIds,
        ...(typeof chatData.createdBy === "string" && chatData.createdBy.length > 0
          ? [chatData.createdBy]
          : []),
      ]));
      const currentChatMembers = stringList(chatData.memberIds);
      const chatMembersChanged =
        normalizedMembers.length !== currentChatMembers.length ||
        normalizedMembers.some((id, index) => id !== currentChatMembers[index]);
      const linkedGroupChanged = chatData.linkedGroupId !== groupDoc.id;

      if (chatMembersChanged || linkedGroupChanged) {
        await chatDoc.ref.update({
          linkedGroupId: groupDoc.id,
          memberIds: normalizedMembers,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      chatSyncApplied = true;
    }

    logger.info("updateUserRole: Role updated.", {
      targetUserId,
      newRole,
      enterpriseId: targetEnterpriseId,
      claimsUpdated,
      groupSyncApplied,
      chatSyncApplied,
      affectedGroupIds: Array.from(affectedGroupIds),
    });

    return {
      success: true,
      targetUserId,
      roles: [newRole],
      activeRole: newRole,
      claimsUpdated,
      groupSyncApplied,
      chatSyncApplied,
      affectedGroupIds: Array.from(affectedGroupIds),
    };
  }
);
