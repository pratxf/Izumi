/**
 * Shared helpers for user admin callables. Keeps updateUserRole and
 * updateUser aligned on how role changes propagate into group/leadIds
 * and the linked chat group membership.
 */

import * as admin from "firebase-admin";
import { logger } from "firebase-functions/v2";

type GroupSnapshot =
  | FirebaseFirestore.QueryDocumentSnapshot<FirebaseFirestore.DocumentData>
  | FirebaseFirestore.DocumentSnapshot<FirebaseFirestore.DocumentData>;

function stringList(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.filter((item): item is string => typeof item === "string");
}

export interface RoleGroupSyncResult {
  groupSyncApplied: boolean;
  chatSyncApplied: boolean;
  affectedGroupIds: string[];
}

/**
 * Propagate a role change to groups (leadIds) and any linked chatGroups.
 * Promotion to team_lead → add to leadIds. Demotion away from team_lead
 * → remove from leadIds. The primary scalar leadId is kept in sync.
 */
export async function syncRoleAndGroups(
  db: FirebaseFirestore.Firestore,
  targetUserId: string,
  targetEnterpriseId: string,
  targetData: FirebaseFirestore.DocumentData,
  newRole: string
): Promise<RoleGroupSyncResult> {
  let groupSyncApplied = false;
  let chatSyncApplied = false;
  const affectedGroupIds = new Set<string>();

  const candidateGroupDocs = new Map<string, GroupSnapshot>();
  const targetGroupId =
    typeof targetData.groupId === "string" ? targetData.groupId : "";
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
      logger.warn("syncRoleAndGroups: Skipping group outside target enterprise.", {
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
      nextLeadIds.some((id, i) => id !== currentLeadIds[i]);

    const currentLeadId =
      typeof groupData.leadId === "string" ? groupData.leadId : "";
    const nextLeadId =
      newRole !== "team_lead" && currentLeadId === targetUserId
        ? nextLeadIds.length > 0
          ? nextLeadIds[0]
          : ""
        : currentLeadId;

    if (leadIdsChanged || nextLeadId !== currentLeadId) {
      await groupDoc.ref.update({
        leadIds: nextLeadIds,
        leadId: nextLeadId,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    groupSyncApplied = true;
    affectedGroupIds.add(groupDoc.id);

    // Mirror the change into any linked chatGroup so chat membership tracks
    // the lead/member roster.
    let linkedChatSnapshot = await db
      .collection("chatGroups")
      .where("linkedGroupId", "==", groupDoc.id)
      .limit(1)
      .get();

    if (
      linkedChatSnapshot.empty &&
      typeof groupData.name === "string" &&
      groupData.name.trim().length > 0
    ) {
      linkedChatSnapshot = await db
        .collection("chatGroups")
        .where("enterpriseId", "==", targetEnterpriseId)
        .where("name", "==", groupData.name.trim())
        .limit(1)
        .get();
    }

    if (linkedChatSnapshot.empty) continue;

    const chatDoc = linkedChatSnapshot.docs[0];
    const chatData = chatDoc.data();
    const memberIds = stringList(groupData.memberIds);
    const normalizedMembers = Array.from(
      new Set<string>([
        ...memberIds,
        ...nextLeadIds,
        ...(typeof chatData.createdBy === "string" &&
        chatData.createdBy.length > 0
          ? [chatData.createdBy]
          : []),
      ])
    );
    const currentChatMembers = stringList(chatData.memberIds);
    const chatMembersChanged =
      normalizedMembers.length !== currentChatMembers.length ||
      normalizedMembers.some((id, i) => id !== currentChatMembers[i]);
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

  return {
    groupSyncApplied,
    chatSyncApplied,
    affectedGroupIds: Array.from(affectedGroupIds),
  };
}
