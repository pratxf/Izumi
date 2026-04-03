/**
 * onForceLogoutCreated - Firestore Trigger
 *
 * Triggered when a document is created/updated at /forceLogout/{userId}.
 * Sends a data-only FCM push with type "force_logout" to the old device's
 * FCM token, then deletes the trigger document.
 */

import { onDocumentWritten } from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";
import { logger } from "firebase-functions/v2";

export const onForceLogoutCreated = onDocumentWritten(
  {
    document: "forceLogout/{userId}",
    region: "asia-south1",
  },
  async (event) => {
    const data = event.data?.after?.data();
    if (!data) return; // Document was deleted — nothing to do

    const userId = event.params.userId;
    const oldToken = data.token as string | undefined;

    if (!oldToken) {
      logger.warn("onForceLogoutCreated: No token in document.", { userId });
      await event.data?.after?.ref.delete();
      return;
    }

    // Send a data-only message (no notification) so it arrives silently
    // and the app handles sign-out without showing a notification banner.
    try {
      await admin.messaging().send({
        token: oldToken,
        data: { type: "force_logout" },
        android: { priority: "high" },
        apns: {
          payload: { aps: { contentAvailable: true } },
        },
      });
      logger.info("onForceLogoutCreated: force_logout push sent.", { userId });
    } catch (error) {
      // Token may already be invalid (device uninstalled, etc.) — that's fine,
      // the old device simply won't receive the push and will stay signed in
      // locally until it next contacts the server.
      logger.warn("onForceLogoutCreated: FCM send failed (token likely stale).", {
        userId,
        error: error instanceof Error ? error.message : String(error),
      });
    }

    // Clean up the trigger document
    await event.data?.after?.ref.delete();
  }
);
