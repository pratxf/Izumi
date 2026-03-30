/**
 * lookupRecipients — Recipient lookup helper
 *
 * Finds the admin and team lead for a given employee within their enterprise.
 * - Admin UID === enterpriseId (by convention)
 * - Team lead: query `groups` where `memberIds` array-contains employeeId → `leadId`
 *
 * Returns a deduplicated set of recipient IDs, excluding the specified employee.
 */

import * as admin from "firebase-admin";
import { logger } from "firebase-functions/v2";

export interface RecipientLookupOptions {
  /** The employee's UID */
  employeeId: string;
  /** The enterprise ID (also the admin's UID) */
  enterpriseId: string;
  /** Additional UIDs to include (e.g. task assigner) */
  additionalIds?: string[];
}

/**
 * Returns deduplicated recipient UIDs (admin + team lead + additionalIds),
 * excluding the employee who triggered the event.
 */
export async function lookupRecipients(
  options: RecipientLookupOptions
): Promise<string[]> {
  const { employeeId, enterpriseId, additionalIds } = options;
  const recipients = new Set<string>();

  // ── 1. Admin = enterpriseId ───────────────────────────────────────────
  if (enterpriseId) {
    recipients.add(enterpriseId);
  }

  // ── 2. Team lead — find group where employee is a member ─────────────
  try {
    const groupSnap = await admin
      .firestore()
      .collection("groups")
      .where("enterpriseId", "==", enterpriseId)
      .where("memberIds", "array-contains", employeeId)
      .limit(1)
      .get();

    if (!groupSnap.empty) {
      const data = groupSnap.docs[0].data();
      // Support new leadIds array and legacy leadId string
      const leadIds = data.leadIds as string[] | undefined;
      if (leadIds && Array.isArray(leadIds)) {
        for (const id of leadIds) {
          if (id) recipients.add(id);
        }
      } else {
        const leadId = data.leadId as string | undefined;
        if (leadId) recipients.add(leadId);
      }
    }
  } catch (err) {
    logger.warn("lookupRecipients: Failed to query groups for team lead.", {
      employeeId,
      error: err instanceof Error ? err.message : String(err),
    });
  }

  // ── 3. Additional IDs (e.g. task assigner) ────────────────────────────
  if (additionalIds) {
    for (const id of additionalIds) {
      if (id) recipients.add(id);
    }
  }

  // ── 4. Exclude the triggering employee ────────────────────────────────
  recipients.delete(employeeId);

  return Array.from(recipients);
}
