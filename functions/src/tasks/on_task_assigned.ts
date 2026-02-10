/**
 * onTaskAssigned - Firestore Trigger
 *
 * Triggered when a new document is created in /tasks/{taskId}.
 * This function:
 *   1. Reads the assigned employee's FCM token from /users/{assignedTo}
 *   2. Sends a push notification via admin.messaging()
 *   3. Creates an activity log entry
 */

import { onDocumentCreated } from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";
import { logger } from "firebase-functions/v2";

/** Shape of a task document. */
interface TaskDocument {
  enterpriseId: string;
  title: string;
  description?: string;
  type: "task" | "followup";
  priority: "high" | "medium" | "low";
  status: "pending" | "completed";
  assignedTo: string;
  assignedBy: string;
  groupId?: string;
  dueDate: admin.firestore.Timestamp;
  sendNotification: boolean;
  createdAt: admin.firestore.Timestamp;
  updatedAt: admin.firestore.Timestamp;
}

/** Shape of a user document (partial - only fields we need). */
interface UserDocument {
  name: string;
  fcmToken?: string;
  enterpriseId: string;
}

/**
 * Map priority to a human-readable label for the notification.
 */
function priorityLabel(priority: string): string {
  switch (priority) {
    case "high":
      return "HIGH PRIORITY";
    case "medium":
      return "Medium Priority";
    case "low":
      return "Low Priority";
    default:
      return "";
  }
}

export const onTaskAssigned = onDocumentCreated(
  {
    document: "tasks/{taskId}",
    region: "asia-south1",
  },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) {
      logger.warn("onTaskAssigned: No data in event, skipping.");
      return;
    }

    const taskId = event.params.taskId;
    const taskData = snapshot.data() as TaskDocument;

    // Validate required fields
    if (!taskData.assignedTo) {
      logger.warn("onTaskAssigned: No assignedTo field, skipping.", { taskId });
      return;
    }

    logger.info("onTaskAssigned: Processing new task.", {
      taskId,
      assignedTo: taskData.assignedTo,
      type: taskData.type,
      sendNotification: taskData.sendNotification,
    });

    const db = admin.firestore();

    // ── 1. Read the assigned employee's user document ────────────────────
    const userDoc = await db
      .collection("users")
      .doc(taskData.assignedTo)
      .get();

    if (!userDoc.exists) {
      logger.error("onTaskAssigned: Assigned user not found.", {
        taskId,
        assignedTo: taskData.assignedTo,
      });
      return;
    }

    const userData = userDoc.data() as UserDocument;

    // ── 2. Read the assigner's name for the notification ─────────────────
    let assignerName = "Admin";
    try {
      const assignerDoc = await db
        .collection("users")
        .doc(taskData.assignedBy)
        .get();
      if (assignerDoc.exists) {
        assignerName = (assignerDoc.data() as UserDocument).name || "Admin";
      }
    } catch (err) {
      logger.warn("onTaskAssigned: Could not read assigner name.", {
        assignedBy: taskData.assignedBy,
      });
    }

    // ── 3. Send push notification if enabled and token exists ────────────
    if (taskData.sendNotification !== false) {
      if (!userData.fcmToken) {
        logger.warn(
          "onTaskAssigned: No FCM token for assigned user, cannot send push.",
          { taskId, assignedTo: taskData.assignedTo }
        );
      } else {
        const taskTypeLabel =
          taskData.type === "followup" ? "Follow-up" : "Task";
        const priorityTag = priorityLabel(taskData.priority);
        const titleText = `New ${taskTypeLabel} Assigned`;
        const bodyText = priorityTag
          ? `[${priorityTag}] ${taskData.title} - assigned by ${assignerName}`
          : `${taskData.title} - assigned by ${assignerName}`;

        const message: admin.messaging.Message = {
          token: userData.fcmToken,
          notification: {
            title: titleText,
            body: bodyText,
          },
          data: {
            taskId: taskId,
            type: taskData.type,
            priority: taskData.priority,
            click_action: "OPEN_TASK",
          },
          android: {
            priority: "high",
            notification: {
              channelId: "tasks",
              priority:
                taskData.priority === "high" ? "max" : "default",
              defaultSound: true,
            },
          },
          apns: {
            payload: {
              aps: {
                badge: 1,
                sound: "default",
                category: "TASK_ASSIGNED",
              },
            },
          },
        };

        try {
          const messageId = await admin.messaging().send(message);
          logger.info("onTaskAssigned: Push notification sent.", {
            taskId,
            messageId,
            assignedTo: taskData.assignedTo,
          });
        } catch (error) {
          // If the token is invalid/expired, remove it from the user document
          if (
            error instanceof Error &&
            (error.message.includes("not-registered") ||
              error.message.includes("invalid-registration-token"))
          ) {
            logger.warn(
              "onTaskAssigned: FCM token is invalid, removing from user.",
              { assignedTo: taskData.assignedTo }
            );
            await db
              .collection("users")
              .doc(taskData.assignedTo)
              .update({
                fcmToken: admin.firestore.FieldValue.delete(),
              });
          } else {
            logger.error("onTaskAssigned: Failed to send push notification.", {
              taskId,
              error:
                error instanceof Error ? error.message : String(error),
            });
          }
        }
      }
    }

    // ── 4. Create an activity log entry ──────────────────────────────────
    try {
      await db.collection("activityLogs").add({
        enterpriseId: taskData.enterpriseId,
        employeeId: taskData.assignedTo,
        type: "task_started",
        title: "New Task Assigned",
        detail: `"${taskData.title}" assigned by ${assignerName}`,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        metadata: {
          taskId: taskId,
          taskType: taskData.type,
          priority: taskData.priority,
          assignedBy: taskData.assignedBy,
        },
      });

      logger.info("onTaskAssigned: Activity log created.", {
        taskId,
        employeeId: taskData.assignedTo,
      });
    } catch (error) {
      logger.error("onTaskAssigned: Failed to create activity log.", {
        taskId,
        error: error instanceof Error ? error.message : String(error),
      });
      // Non-critical - do not rethrow
    }
  }
);
