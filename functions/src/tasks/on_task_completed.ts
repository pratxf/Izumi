/**
 * onTaskCompleted - Firestore Trigger
 *
 * Triggered when a task document is updated and status changes to "completed".
 * Notifies: admin + team lead + task creator (assignedBy) — excluding the
 * employee who completed the task.
 */

import { onDocumentUpdated } from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";
import { logger } from "firebase-functions/v2";
import { sendNotification } from "../utils/send_notification";
import { lookupRecipients } from "../utils/lookup_recipients";
import { upsertActivityLog } from "../utils/activity_log";

interface TaskDocument {
  enterpriseId: string;
  title: string;
  status: "pending" | "completed";
  assignedTo: string;
  assignedBy: string;
  updatedAt?: admin.firestore.Timestamp;
}

interface UserDocument {
  name: string;
}

export const onTaskCompleted = onDocumentUpdated(
  {
    document: "tasks/{taskId}",
    region: "asia-south1",
  },
  async (event) => {
    const before = event.data?.before.data() as TaskDocument | undefined;
    const after = event.data?.after.data() as TaskDocument | undefined;

    if (!before || !after) {
      logger.warn("onTaskCompleted: Missing before/after data, skipping.");
      return;
    }

    // Only fire when status changes to "completed"
    if (before.status === "completed" || after.status !== "completed") {
      return;
    }

    const taskId = event.params.taskId;
    const employeeId = after.assignedTo;

    logger.info("onTaskCompleted: Task completed.", {
      taskId,
      employeeId,
    });

    // Look up employee name
    let employeeName = "Employee";
    try {
      const userDoc = await admin
        .firestore()
        .collection("users")
        .doc(employeeId)
        .get();
      if (userDoc.exists) {
        employeeName = (userDoc.data() as UserDocument).name || "Employee";
      }
    } catch (err) {
      logger.warn("onTaskCompleted: Could not read employee name.", {
        employeeId,
      });
    }

    // Find recipients: admin + team lead + task assigner, excluding the employee
    const recipients = await lookupRecipients({
      employeeId,
      enterpriseId: after.enterpriseId,
      additionalIds: [after.assignedBy],
    });

    // Send notification to each recipient
    const promises = recipients.map((recipientId) =>
      sendNotification({
        userId: recipientId,
        title: "Task Completed",
        body: `${employeeName} completed "${after.title}"`,
        type: "task",
        data: {
          taskId,
          action: "TASK_COMPLETED",
          employeeId,
        },
      })
    );

    await Promise.all(promises);

    await upsertActivityLog(admin.firestore(), {
      id: `task_completed_${taskId}`,
      enterpriseId: after.enterpriseId,
      employeeId,
      orgId: after.enterpriseId,
      type: "task_completed",
      title: "Task Completed",
      detail: `${employeeName} completed "${after.title}"`,
      timestamp: after.updatedAt ?? admin.firestore.FieldValue.serverTimestamp(),
      payload: {
        taskId,
        title: after.title,
        completedAt: after.updatedAt ?? admin.firestore.FieldValue.serverTimestamp(),
      },
      metadata: {
        taskId,
        assignedBy: after.assignedBy,
      },
    });

    logger.info("onTaskCompleted: Notifications sent.", {
      taskId,
      recipientCount: recipients.length,
    });
  }
);
