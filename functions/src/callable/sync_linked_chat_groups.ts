import {onCall, HttpsError} from "firebase-functions/v2/https";
import {logger} from "firebase-functions/v2";
import * as admin from "firebase-admin";

type SyncResult = {
  totalGroups: number;
  linkedChatsFound: number;
  chatsUpdated: number;
  chatsLinkedByName: number;
  dryRun: boolean;
};

function stringList(values: unknown[] | undefined): string[] {
  if (!Array.isArray(values)) return [];
  return values.filter((value): value is string => typeof value === "string");
}

export const syncLinkedChatGroups = onCall(
  {region: "asia-south1"},
  async (request): Promise<SyncResult> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be authenticated.");
    }

    const callerRoles = request.auth.token.roles as string[] | undefined;
    const callerRole = request.auth.token.activeRole || request.auth.token.role;
    if (!(callerRoles && callerRoles.includes("admin")) && callerRole !== "admin") {
      throw new HttpsError("permission-denied", "Only admins can run this.");
    }

    const enterpriseId = request.auth.token.enterpriseId as string | undefined;
    if (!enterpriseId) {
      throw new HttpsError("failed-precondition", "No enterpriseId in claims.");
    }

    const dryRun = (request.data?.dryRun as boolean | undefined) ?? true;
    const db = admin.firestore();

    const groupsSnapshot = await db
      .collection("groups")
      .where("enterpriseId", "==", enterpriseId)
      .get();

    let linkedChatsFound = 0;
    let chatsUpdated = 0;
    let chatsLinkedByName = 0;

    for (const groupDoc of groupsSnapshot.docs) {
      const group = groupDoc.data();
      const memberIds = stringList(group.memberIds);
      const leadIds = stringList(group.leadIds);
      if (leadIds.length === 0 &&
          typeof group.leadId === "string" &&
          group.leadId.length > 0) {
        leadIds.push(group.leadId);
      }

      let chatQuery = await db
        .collection("chatGroups")
        .where("linkedGroupId", "==", groupDoc.id)
        .limit(1)
        .get();

      let linkedByName = false;
      if (chatQuery.empty && typeof group.name === "string" && group.name.trim().length > 0) {
        chatQuery = await db
          .collection("chatGroups")
          .where("enterpriseId", "==", enterpriseId)
          .where("name", "==", group.name.trim())
          .limit(1)
          .get();
        linkedByName = !chatQuery.empty;
      }

      if (chatQuery.empty) {
        continue;
      }

      linkedChatsFound++;
      if (linkedByName) chatsLinkedByName++;

      const chatDoc = chatQuery.docs[0];
      const chat = chatDoc.data();
      const normalizedMembers = Array.from(new Set<string>([
        ...memberIds,
        ...leadIds,
        ...(typeof chat.createdBy === "string" && chat.createdBy.length > 0
          ? [chat.createdBy]
          : []),
      ]));

      const currentMembers = stringList(chat.memberIds);
      const membersChanged =
        normalizedMembers.length !== currentMembers.length ||
        normalizedMembers.some((id, index) => id !== currentMembers[index]);
      const linkedGroupChanged = chat.linkedGroupId !== groupDoc.id;

      if (!membersChanged && !linkedGroupChanged) {
        continue;
      }

      chatsUpdated++;
      if (!dryRun) {
        await chatDoc.ref.update({
          linkedGroupId: groupDoc.id,
          memberIds: normalizedMembers,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    }

    const result: SyncResult = {
      totalGroups: groupsSnapshot.size,
      linkedChatsFound,
      chatsUpdated,
      chatsLinkedByName,
      dryRun,
    };

    logger.info("syncLinkedChatGroups completed.", {
      enterpriseId,
      ...result,
    });

    return result;
  },
);
