/**
 * Session Event Notifications
 *
 * onSessionStarted — Triggered when a new session document is created.
 * onSessionEnded   — Triggered when a session document status becomes ended.
 *
 * Notifies admin + team lead (and employee for auto-ended sessions).
 */

import { onDocumentCreated, onDocumentUpdated } from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";
import { logger } from "firebase-functions/v2";
import { sendNotification } from "../utils/send_notification";
import { lookupRecipients } from "../utils/lookup_recipients";
import { upsertActivityLog } from "../utils/activity_log";

interface SessionDocument {
  employeeId: string;
  enterpriseId: string;
  status: string;
  startTime?: admin.firestore.Timestamp;
  endTime?: admin.firestore.Timestamp;
  totalDuration?: number;
  totalDistance?: number;
  autoEndReason?: string;
}

interface UserDocument {
  name: string;
}

/**
 * Look up an employee's display name from Firestore.
 */
async function getEmployeeName(employeeId: string): Promise<string> {
  try {
    const doc = await admin
      .firestore()
      .collection("users")
      .doc(employeeId)
      .get();
    if (doc.exists) {
      return (doc.data() as UserDocument).name || "Employee";
    }
  } catch (err) {
    logger.warn("getEmployeeName: Could not read user doc.", { employeeId });
  }
  return "Employee";
}

// ── onSessionStarted ──────────────────────────────────────────────────────

export const onSessionStarted = onDocumentCreated(
  {
    document: "sessions/{sessionId}",
    region: "asia-south1",
  },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) {
      logger.warn("onSessionStarted: No data in event, skipping.");
      return;
    }

    const sessionId = event.params.sessionId;
    const sessionData = snapshot.data() as SessionDocument;
    const employeeId = sessionData.employeeId;

    if (!employeeId || !sessionData.enterpriseId) {
      logger.warn("onSessionStarted: Missing employeeId or enterpriseId.", {
        sessionId,
      });
      return;
    }

    logger.info("onSessionStarted: Processing new session.", {
      sessionId,
      employeeId,
    });

    // Check if session_start log already exists (written by client with location)
    const existing = await admin.firestore().collection('activityLogs')
      .where('sessionId', '==', sessionId)
      .where('type', '==', 'session_start')
      .limit(1)
      .get();

    if (!existing.empty) {
      logger.info("onSessionStarted: session_start log already written by client, skipping.", {
        sessionId,
        employeeId,
      });
    } else {
      const employeeName = await getEmployeeName(employeeId);
      await upsertActivityLog(admin.firestore(), {
        id: `session_started_${sessionId}`,
        enterpriseId: sessionData.enterpriseId,
        employeeId,
        sessionId,
        orgId: sessionData.enterpriseId,
        type: "session_start",
        title: "Session Started",
        detail: `${employeeName} started a field session`,
        timestamp:
          sessionData.startTime ?? admin.firestore.FieldValue.serverTimestamp(),
        payload: {
          startTime:
            sessionData.startTime ?? admin.firestore.FieldValue.serverTimestamp(),
        },
        metadata: {
          source: "session_trigger",
        },
      });
    }

    const employeeName = await getEmployeeName(employeeId);
    const recipients = await lookupRecipients({
      employeeId,
      enterpriseId: sessionData.enterpriseId,
    });

    const promises = recipients.map((recipientId) =>
      sendNotification({
        userId: recipientId,
        title: "Session Started",
        body: `${employeeName} has started a field session`,
        type: "alert",
        data: {
          sessionId,
          action: "SESSION_STARTED",
          employeeId,
        },
      })
    );

    await Promise.all(promises);

    logger.info("onSessionStarted: Notifications sent.", {
      sessionId,
      recipientCount: recipients.length,
    });
  }
);

// ── onSessionEnded ────────────────────────────────────────────────────────

export const onSessionEnded = onDocumentUpdated(
  {
    document: "sessions/{sessionId}",
    region: "asia-south1",
  },
  async (event) => {
    const before = event.data?.before.data() as SessionDocument | undefined;
    const after = event.data?.after.data() as SessionDocument | undefined;

    if (!before || !after) {
      logger.warn("onSessionEnded: Missing before/after data, skipping.");
      return;
    }

    const endedStatuses = new Set(["completed", "auto_ended"]);
    const statusChanged = before.status !== after.status;
    const isEndedTransition = statusChanged && endedStatuses.has(after.status);
    if (!isEndedTransition) {
      return;
    }

    const sessionId = event.params.sessionId;
    const employeeId = after.employeeId;

    if (!employeeId || !after.enterpriseId) {
      logger.warn("onSessionEnded: Missing employeeId or enterpriseId.", {
        sessionId,
      });
      return;
    }

    logger.info("onSessionEnded: Session ended.", {
      sessionId,
      employeeId,
      status: after.status,
    });

    const employeeName = await getEmployeeName(employeeId);
    const endTime = after.endTime ?? admin.firestore.FieldValue.serverTimestamp();
    const durationSeconds = after.totalDuration ?? 0;
    const distanceKm = after.totalDistance ?? 0;
    const endReason = after.status === "auto_ended"
      ? (after.autoEndReason || "auto_ended")
      : "manual";

    await upsertActivityLog(admin.firestore(), {
      id: `${after.status === "auto_ended" ? "session_auto_ended" : "session_ended"}_${sessionId}`,
      enterpriseId: after.enterpriseId,
      employeeId,
      sessionId,
      orgId: after.enterpriseId,
      type: "session_end",
      title: after.status === "auto_ended" ? "Session Auto-Ended" : "Session Ended",
      detail: after.status === "auto_ended"
        ? `${employeeName}'s session was auto-ended`
        : `${employeeName} ended the field session`,
      timestamp: endTime,
      payload: {
        endTime,
        durationSeconds,
        distanceKm,
        endReason,
      },
      metadata: {
        status: after.status,
        source: "session_trigger",
      },
    });

    const recipients = await lookupRecipients({
      employeeId,
      enterpriseId: after.enterpriseId,
    });
    const notifyEmployee = after.status === "auto_ended";
    const recipientSet = new Set<string>(recipients);
    if (notifyEmployee) recipientSet.add(employeeId);

    const title = after.status === "auto_ended" ? "Session Auto-Ended" : "Session Ended";
    const body = after.status === "auto_ended"
      ? `${employeeName}'s session was auto-ended due to app disconnect`
      : `${employeeName} has ended their field session`;
    const action = after.status === "auto_ended" ? "SESSION_AUTO_ENDED" : "SESSION_ENDED";

    const promises = Array.from(recipientSet).map((recipientId) =>
      sendNotification({
        userId: recipientId,
        title,
        body,
        type: "alert",
        data: {
          sessionId,
          action,
          status: after.status,
          employeeId,
        },
      })
    );

    await Promise.all(promises);

    logger.info("onSessionEnded: Notifications sent.", {
      sessionId,
      status: after.status,
      recipientCount: recipientSet.size,
    });
  }
);
