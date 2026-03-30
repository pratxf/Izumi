import * as admin from "firebase-admin";

export type ActivityLogPayload = {
  id: string;
  enterpriseId: string;
  employeeId: string;
  sessionId?: string | null;
  orgId?: string;
  type: string;
  title: string;
  detail: string;
  date?: string;
  timestamp?: admin.firestore.Timestamp | admin.firestore.FieldValue;
  metadata?: Record<string, unknown>;
  payload?: Record<string, unknown>;
};

/**
 * Derives a YYYY-MM-DD date string from a Timestamp or FieldValue.
 * Falls back to today's date in Asia/Kolkata timezone.
 */
function deriveDate(
  ts?: admin.firestore.Timestamp | admin.firestore.FieldValue
): string {
  if (ts instanceof admin.firestore.Timestamp) {
    const d = ts.toDate();
    // Use IST (UTC+5:30) as the org timezone
    const ist = new Date(d.getTime() + 5.5 * 60 * 60 * 1000);
    return ist.toISOString().slice(0, 10);
  }
  const now = new Date();
  const ist = new Date(now.getTime() + 5.5 * 60 * 60 * 1000);
  return ist.toISOString().slice(0, 10);
}

export async function upsertActivityLog(
  db: admin.firestore.Firestore,
  payload: ActivityLogPayload
): Promise<void> {
  const effectiveTimestamp =
    payload.timestamp ?? admin.firestore.FieldValue.serverTimestamp();
  const dateStr = payload.date || deriveDate(payload.timestamp);

  await db.collection("activityLogs").doc(payload.id).set(
    {
      enterpriseId: payload.enterpriseId,
      employeeId: payload.employeeId,
      sessionId: payload.sessionId ?? null,
      orgId: payload.orgId || payload.enterpriseId,
      type: payload.type,
      title: payload.title,
      detail: payload.detail,
      timestamp: effectiveTimestamp,
      date: dateStr,
      payload: payload.payload ?? {},
      metadata: payload.metadata ?? {},
    },
    { merge: true }
  );
}
