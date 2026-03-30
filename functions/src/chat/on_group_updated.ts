import {onDocumentUpdated} from "firebase-functions/v2/firestore";
import {logger} from "firebase-functions/v2";
import * as admin from "firebase-admin";

interface GroupDocument {
  enterpriseId?: string;
  name?: string;
  memberIds?: unknown[];
  leadIds?: unknown[];
  leadId?: string;
}

interface ChatGroupDocument {
  linkedGroupId?: string;
  memberIds?: unknown[];
  createdBy?: string;
}

function stringList(values: unknown[] | undefined): string[] {
  if (!Array.isArray(values)) return [];
  return values.filter((value): value is string => typeof value === "string");
}

export const onGroupUpdated = onDocumentUpdated(
  {
    document: "groups/{groupId}",
    region: "asia-south1",
  },
  async (event) => {
    const after = event.data?.after;
    if (!after?.exists) {
      logger.warn("onGroupUpdated: Missing updated group snapshot, skipping.");
      return;
    }

    const groupId = event.params.groupId;
    const groupData = after.data() as GroupDocument;
    const enterpriseId = groupData.enterpriseId ?? "";

    if (!enterpriseId) {
      logger.warn("onGroupUpdated: Group missing enterpriseId.", {groupId});
      return;
    }

    let linkedChatGroups = await admin
      .firestore()
      .collection("chatGroups")
      .where("linkedGroupId", "==", groupId)
      .limit(1)
      .get();

    if (linkedChatGroups.empty &&
        typeof groupData.name === "string" &&
        groupData.name.trim().length > 0) {
      linkedChatGroups = await admin
        .firestore()
        .collection("chatGroups")
        .where("enterpriseId", "==", enterpriseId)
        .where("name", "==", groupData.name.trim())
        .limit(1)
        .get();
    }

    if (linkedChatGroups.empty) {
      logger.info("onGroupUpdated: No linked chat group found.", {
        groupId,
        enterpriseId,
        groupName: groupData.name,
      });
      return;
    }

    const chatGroupDoc = linkedChatGroups.docs[0];
    const chatGroup = chatGroupDoc.data() as ChatGroupDocument;

    const memberIds = stringList(groupData.memberIds);
    const leadIds = stringList(groupData.leadIds);
    if (leadIds.length === 0 &&
        typeof groupData.leadId === "string" &&
        groupData.leadId.length > 0) {
      leadIds.push(groupData.leadId);
    }

    const normalizedMemberSet = new Set<string>([
      ...memberIds,
      ...leadIds,
    ]);
    if (typeof chatGroup.createdBy === "string" &&
        chatGroup.createdBy.length > 0) {
      normalizedMemberSet.add(chatGroup.createdBy);
    }
    const normalizedMembers = Array.from(normalizedMemberSet);

    const currentMembers = stringList(chatGroup.memberIds);
    const membersUnchanged =
      normalizedMembers.length === currentMembers.length &&
      normalizedMembers.every((id, index) => id === currentMembers[index]);

    if (membersUnchanged &&
        chatGroup.linkedGroupId === groupId) {
      return;
    }

    await chatGroupDoc.ref.update({
      "linkedGroupId": groupId,
      "memberIds": normalizedMembers,
      "updatedAt": admin.firestore.FieldValue.serverTimestamp(),
    });

    logger.info("onGroupUpdated: Synced linked chat group members.", {
      groupId,
      enterpriseId,
      chatGroupId: chatGroupDoc.id,
      memberCount: normalizedMembers.length,
    });
  },
);
