/**
 * onTaskAssigned - Firestore Trigger
 *
 * Triggered when a new document is created in /tasks/{taskId}.
 * This function:
 *   1. Sends a push notification AND writes an in-app notification via sendNotification()
 *   2. Creates an activity log entry
 */

import { onDocumentCreated } from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";
import { logger } from "firebase-functions/v2";
import { sendNotification } from "../utils/send_notification";
import { upsertActivityLog } from "../utils/activity_log";

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

    // ── 1. Read the assigner's name for the notification ─────────────────
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

    // ── 2. Send notification (Firestore + FCM push) via helper ───────────
    if (taskData.sendNotification !== false) {
      const taskTypeLabel =
        taskData.type === "followup" ? "Follow-up" : "Task";
      const priorityTag = priorityLabel(taskData.priority);
      const titleText = `New ${taskTypeLabel} Assigned`;
      const bodyText = priorityTag
        ? `[${priorityTag}] ${taskData.title} - assigned by ${assignerName}`
        : `${taskData.title} - assigned by ${assignerName}`;

      await sendNotification({
        userId: taskData.assignedTo,
        title: titleText,
        body: bodyText,
        type: "task",
        data: {
          taskId: taskId,
          action: "TASK_ASSIGNED",
          priority: taskData.priority,
        },
      });
    }

    // ── 3. Create an activity log entry ──────────────────────────────────
    try {
      await upsertActivityLog(db, {
        id: `task_started_${taskId}`,
        enterpriseId: taskData.enterpriseId,
        employeeId: taskData.assignedTo,
        orgId: taskData.enterpriseId,
        type: "task_started",
        title: "New Task Assigned",
        detail: `"${taskData.title}" assigned by ${assignerName}`,
        timestamp:
          taskData.createdAt ?? admin.firestore.FieldValue.serverTimestamp(),
        payload: {
          taskId,
          title: taskData.title,
        },
        metadata: {
          taskId,
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
