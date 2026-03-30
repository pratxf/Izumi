/**
 * onChatMessage - Firestore Trigger
 *
 * Triggered when a new message is created in /chatGroups/{groupId}/messages/{messageId}.
 * This function updates the parent chatGroup doc with lastMessage + lastMessageAt.
 */

import { onDocumentCreated } from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";
import { logger } from "firebase-functions/v2";
interface ChatMessage {
  senderId: string;
  senderName: string;
  type: "text" | "image" | "location";
  text?: string;
  imageUrl?: string;
  latitude?: number;
  longitude?: number;
  address?: string;
  createdAt: admin.firestore.Timestamp;
}

export const onChatMessage = onDocumentCreated(
  {
    document: "chatGroups/{groupId}/messages/{messageId}",
    region: "asia-south1",
  },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) {
      logger.warn("onChatMessage: No data in event, skipping.");
      return;
    }

    const { groupId } = event.params;
    const messageData = snapshot.data() as ChatMessage;
    const db = admin.firestore();

    // ── 1. Build preview text ──────────────────────────────────────────
    let previewText: string;
    switch (messageData.type) {
      case "image":
        previewText = "Sent a photo";
        break;
      case "location":
        previewText = "Shared a location";
        break;
      default:
        previewText = messageData.text || "";
        break;
    }

    // ── 2. Update parent chatGroup with lastMessage ──────────────────────
    try {
      await db.collection("chatGroups").doc(groupId).update({
        lastMessage: {
          text: previewText,
          senderId: messageData.senderId,
          senderName: messageData.senderName,
          type: messageData.type,
          timestamp: messageData.createdAt,
        },
        lastMessageAt: messageData.createdAt,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      logger.info("onChatMessage: Updated lastMessage on chatGroup.", {
        groupId,
      });
    } catch (err) {
      logger.error("onChatMessage: Failed to update chatGroup.", {
        groupId,
        error: err instanceof Error ? err.message : String(err),
      });
    }

    logger.info("onChatMessage: Done.", { groupId });
  }
);
