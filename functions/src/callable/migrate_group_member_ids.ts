/**
 * migrateGroupMemberIds - HTTPS Callable
 *
 * Repairs stale group `memberIds`/`leadIds` that still reference old
 * pre-created user doc IDs instead of Firebase Auth UID-based IDs.
 *
 * Only admins can execute this callable.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { logger } from "firebase-functions/v2";

type RepairResult = {
  totalGroups: number;
  groupsUpdated: number;
  rewrittenMemberIds: number;
  rewrittenLeadIds: number;
  removedOrphanMemberIds: number;
  removedOrphanLeadIds: number;
  unresolvedIdCount: number;
  unresolvedIdSamples: string[];
  dryRun: boolean;
  removeOrphans: boolean;
};

export const migrateGroupMemberIds = onCall(
  { region: "asia-south1" },
  async (request): Promise<RepairResult> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be authenticated.");
    }

    const callerRoles = request.auth.token.roles as string[] | undefined;
    const callerRole = request.auth.token.activeRole || request.auth.token.role;
    if (!(callerRoles && callerRoles.includes("admin")) && callerRole !== "admin") {
      throw new HttpsError("permission-denied", "Only admins can run this.");
    }

    const enterpriseId = request.auth.token.enterpriseId as string;
    if (!enterpriseId) {
      throw new HttpsError("failed-precondition", "No enterpriseId in claims.");
    }

    const data = (request.data || {}) as {
      dryRun?: boolean;
      removeOrphans?: boolean;
    };
    const dryRun = data.dryRun ?? true;
    const removeOrphans = data.removeOrphans ?? false;

    const db = admin.firestore();

    const usersSnapshot = await db
      .collection("users")
      .where("enterpriseId", "==", enterpriseId)
      .get();

    const validUserIds = new Set<string>();
    const migratedIdMap = new Map<string, string>(); // oldId -> uid

    for (const userDoc of usersSnapshot.docs) {
      const userId = userDoc.id;
      validUserIds.add(userId);

      const migratedFrom = userDoc.data().migratedFrom as string | undefined;
      if (migratedFrom && migratedFrom !== userId) {
        migratedIdMap.set(migratedFrom, userId);
      }
    }

    const groupsSnapshot = await db
      .collection("groups")
      .where("enterpriseId", "==", enterpriseId)
      .get();

    const unresolvedIds = new Set<string>();
    let groupsUpdated = 0;
    let rewrittenMemberIds = 0;
    let rewrittenLeadIds = 0;
    let removedOrphanMemberIds = 0;
    let removedOrphanLeadIds = 0;

    const updates: Array<{
      ref: FirebaseFirestore.DocumentReference;
      data: Record<string, unknown>;
    }> = [];

    for (const groupDoc of groupsSnapshot.docs) {
      const group = groupDoc.data();
      const currentMemberIds = Array.isArray(group.memberIds)
        ? (group.memberIds as unknown[]).filter((id) => typeof id === "string") as string[]
        : [];
      const currentLeadIds = Array.isArray(group.leadIds)
        ? (group.leadIds as unknown[]).filter((id) => typeof id === "string") as string[]
        : [];

      let localRewrittenMemberIds = 0;
      let localRewrittenLeadIds = 0;
      let localRemovedMemberIds = 0;
      let localRemovedLeadIds = 0;

      const normalizeId = (id: string): { id?: string; rewritten: boolean; orphan: boolean } => {
        if (validUserIds.has(id)) {
          return { id, rewritten: false, orphan: false };
        }
        const mapped = migratedIdMap.get(id);
        if (mapped) {
          return { id: mapped, rewritten: true, orphan: false };
        }
        return { rewritten: false, orphan: true };
      };

      const nextMemberIds: string[] = [];
      for (const memberId of currentMemberIds) {
        const normalized = normalizeId(memberId);
        if (normalized.orphan) {
          unresolvedIds.add(memberId);
          if (removeOrphans) {
            localRemovedMemberIds++;
            continue;
          }
          nextMemberIds.push(memberId);
          continue;
        }
        if (normalized.rewritten) localRewrittenMemberIds++;
        nextMemberIds.push(normalized.id as string);
      }

      const nextLeadIds: string[] = [];
      for (const leadId of currentLeadIds) {
        const normalized = normalizeId(leadId);
        if (normalized.orphan) {
          unresolvedIds.add(leadId);
          if (removeOrphans) {
            localRemovedLeadIds++;
            continue;
          }
          nextLeadIds.push(leadId);
          continue;
        }
        if (normalized.rewritten) localRewrittenLeadIds++;
        nextLeadIds.push(normalized.id as string);
      }

      const dedupMembers = Array.from(new Set(nextMemberIds));
      const dedupLeads = Array.from(new Set(nextLeadIds));

      const nextLeadId = dedupLeads.length > 0
        ? dedupLeads[0]
        : (removeOrphans ? "" : (typeof group.leadId === "string" ? group.leadId : ""));

      const membersChanged = dedupMembers.length !== currentMemberIds.length ||
        dedupMembers.some((id, i) => id !== currentMemberIds[i]);
      const leadsChanged = dedupLeads.length !== currentLeadIds.length ||
        dedupLeads.some((id, i) => id !== currentLeadIds[i]);
      const leadIdChanged = typeof group.leadId === "string"
        ? group.leadId !== nextLeadId
        : nextLeadId.length > 0;

      if (membersChanged || leadsChanged || leadIdChanged) {
        groupsUpdated++;
        rewrittenMemberIds += localRewrittenMemberIds;
        rewrittenLeadIds += localRewrittenLeadIds;
        removedOrphanMemberIds += localRemovedMemberIds;
        removedOrphanLeadIds += localRemovedLeadIds;

        if (!dryRun) {
          updates.push({
            ref: groupDoc.ref,
            data: {
              memberIds: dedupMembers,
              leadIds: dedupLeads,
              leadId: nextLeadId,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
          });
        }
      }
    }

    if (!dryRun && updates.length > 0) {
      for (let i = 0; i < updates.length; i += 400) {
        const chunk = updates.slice(i, i + 400);
        const batch = db.batch();
        for (const update of chunk) {
          batch.update(update.ref, update.data);
        }
        await batch.commit();
      }
    }

    const result: RepairResult = {
      totalGroups: groupsSnapshot.size,
      groupsUpdated,
      rewrittenMemberIds,
      rewrittenLeadIds,
      removedOrphanMemberIds,
      removedOrphanLeadIds,
      unresolvedIdCount: unresolvedIds.size,
      unresolvedIdSamples: Array.from(unresolvedIds).slice(0, 20),
      dryRun,
      removeOrphans,
    };

    logger.info("migrateGroupMemberIds completed.", {
      enterpriseId,
      ...result,
    });

    return result;
  }
);
