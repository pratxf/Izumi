import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import * as admin from "firebase-admin";

/**
 * broadcastDiagnosticCommand
 *
 * Admin-only. Fans out a data-only FCM `diagnostic_control` message to
 * every employee in the caller's enterprise (or a single targetUserId).
 *
 * Request:
 *   {
 *     enterpriseId: string,
 *     action: "enable" | "disable" | "upload_now",
 *     targetUserId?: string,
 *   }
 *
 * Response:
 *   { success, successCount, failureCount, invalidTokens: string[] }
 *
 * Tokens that FCM reports as not-registered or invalid are stripped from
 * the matching user doc so the next broadcast skips them.
 */
export const broadcastDiagnosticCommand = onCall(
  { region: "asia-south1", timeoutSeconds: 60, memory: "256MiB" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be authenticated.");
    }
    const claims = request.auth.token;
    const roles = claims.roles as string[] | undefined;
    const activeRole = (claims.activeRole ?? claims.role) as string | undefined;
    const isAdmin =
      (roles && roles.includes("admin")) || activeRole === "admin";
    if (!isAdmin) {
      throw new HttpsError("permission-denied", "Admin access required.");
    }

    const data = (request.data ?? {}) as {
      enterpriseId?: string;
      action?: string;
      targetUserId?: string;
    };
    const { enterpriseId, action, targetUserId } = data;

    if (!enterpriseId || !action) {
      throw new HttpsError(
        "invalid-argument",
        "enterpriseId and action are required.",
      );
    }
    if (!["enable", "disable", "upload_now"].includes(action)) {
      throw new HttpsError("invalid-argument", `Unknown action: ${action}`);
    }
    if (claims.enterpriseId !== enterpriseId) {
      throw new HttpsError(
        "permission-denied",
        "Admin can only broadcast within their own enterprise.",
      );
    }

    const db = admin.firestore();
    const snap = await db
      .collection("users")
      .where("enterpriseId", "==", enterpriseId)
      .get();

    const tokenToUserId = new Map<string, string>();
    for (const d of snap.docs) {
      if (targetUserId && d.id !== targetUserId) continue;
      const token = d.data().fcmToken as string | undefined;
      if (token && token.length > 0) tokenToUserId.set(token, d.id);
    }

    if (tokenToUserId.size === 0) {
      logger.info("broadcastDiagnosticCommand: no eligible tokens", {
        enterpriseId,
        action,
        targetUserId,
      });
      return {
        success: true,
        successCount: 0,
        failureCount: 0,
        invalidTokens: [],
      };
    }

    const tokens = Array.from(tokenToUserId.keys());
    const message: admin.messaging.MulticastMessage = {
      tokens,
      data: {
        type: "diagnostic_control",
        action,
      },
      android: { priority: "high" },
      apns: {
        headers: { "apns-priority": "5" },
        payload: { aps: { contentAvailable: true } },
      },
    };

    const resp = await admin.messaging().sendEachForMulticast(message);

    const invalidUserIds: string[] = [];
    resp.responses.forEach((r, idx) => {
      if (r.success || !r.error) return;
      const code = r.error.code;
      if (
        code === "messaging/registration-token-not-registered" ||
        code === "messaging/invalid-registration-token" ||
        code === "messaging/invalid-argument"
      ) {
        const uid = tokenToUserId.get(tokens[idx]);
        if (uid) invalidUserIds.push(uid);
      }
    });

    if (invalidUserIds.length > 0) {
      await Promise.all(
        invalidUserIds.map((uid) =>
          db
            .collection("users")
            .doc(uid)
            .update({ fcmToken: admin.firestore.FieldValue.delete() })
            .catch((e) =>
              logger.warn("broadcastDiagnosticCommand: token cleanup failed", {
                uid,
                error: e instanceof Error ? e.message : String(e),
              }),
            ),
        ),
      );
    }

    logger.info("broadcastDiagnosticCommand: sent", {
      enterpriseId,
      action,
      targetUserId,
      successCount: resp.successCount,
      failureCount: resp.failureCount,
      invalidTokens: invalidUserIds.length,
    });

    return {
      success: true,
      successCount: resp.successCount,
      failureCount: resp.failureCount,
      invalidTokens: invalidUserIds,
    };
  },
);
