/**
 * sendNotification — Shared helper
 *
 * 1. Writes a notification document to /users/{userId}/notifications (in-app)
 * 2. Sends an FCM push via admin.messaging().send() (device notification)
 * 3. Cleans up invalid FCM tokens automatically
 */

import * as admin from "firebase-admin";
import { logger } from "firebase-functions/v2";

export interface NotificationPayload {
  /** Firestore UID of the recipient */
  userId: string;
  /** Notification title (e.g. "New Task Assigned") */
  title: string;
  /** Notification body (e.g. "Ravi completed 'Fix valve'") */
  body: string;
  /** Notification type for UI grouping: task | alert | system | location | report */
  type: string;
  /** Extra key-value data for deep linking (action, taskId, sessionId, etc.) */
  data?: Record<string, string>;
}

/**
 * Writes an in-app notification doc AND sends an FCM push to the user.
 * Silently skips if the user has no FCM token (still writes the Firestore doc).
 */
export async function sendNotification(payload: NotificationPayload): Promise<void> {
  const { userId, title, body, type, data } = payload;
  const db = admin.firestore();

  // ── 1. Write to Firestore /users/{userId}/notifications ──────────────
  try {
    await db
      .collection("users")
      .doc(userId)
      .collection("notifications")
      .add({
        title,
        body,
        type,
        isRead: false,
        data: data ?? {},
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    logger.info("sendNotification: Firestore notification written.", {
      userId,
      title,
    });
  } catch (err) {
    logger.error("sendNotification: Failed to write Firestore notification.", {
      userId,
      error: err instanceof Error ? err.message : String(err),
    });
    // Continue to attempt FCM even if Firestore write fails
  }

  // ── 2. Send FCM push ─────────────────────────────────────────────────
  let fcmToken: string | undefined;
  try {
    const userDoc = await db.collection("users").doc(userId).get();
    fcmToken = userDoc.data()?.fcmToken as string | undefined;
  } catch (err) {
    logger.warn("sendNotification: Could not read user doc for FCM token.", {
      userId,
    });
    return;
  }

  if (!fcmToken) {
    logger.info("sendNotification: No FCM token for user, skipping push.", {
      userId,
    });
    return;
  }

  const message: admin.messaging.Message = {
    token: fcmToken,
    notification: { title, body },
    data: {
      ...data,
      type,
    },
    android: {
      priority: "high",
      notification: {
        channelId: type === "task" ? "tasks" : "general",
        defaultSound: true,
      },
    },
    apns: {
      payload: {
        aps: {
          badge: 1,
          sound: "default",
        },
      },
    },
  };

  try {
    const messageId = await admin.messaging().send(message);
    logger.info("sendNotification: FCM push sent.", { userId, messageId });
  } catch (error) {
    // Clean up invalid/expired tokens
    if (
      error instanceof Error &&
      (error.message.includes("not-registered") ||
        error.message.includes("invalid-registration-token"))
    ) {
      logger.warn("sendNotification: Invalid FCM token, removing.", { userId });
      await db.collection("users").doc(userId).update({
        fcmToken: admin.firestore.FieldValue.delete(),
      });
    } else {
      logger.error("sendNotification: FCM send failed.", {
        userId,
        error: error instanceof Error ? error.message : String(error),
      });
    }
  }
}
