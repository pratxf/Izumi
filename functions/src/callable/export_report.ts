/**
 * exportReport - HTTPS Callable Function
 *
 * Accepts a request with:
 *   - enterpriseId: string
 *   - type: 'sessions' | 'tasks' | 'photos' | 'attendance' | 'summary'
 *   - period: { startDate: string (ISO), endDate: string (ISO) }
 *   - format: 'csv' (extensible to 'pdf' in the future)
 *
 * Queries the relevant Firestore data for the enterprise and period,
 * generates a CSV file, uploads it to Cloud Storage under
 * enterprises/{enterpriseId}/exports/, and returns the signed download URL.
 *
 * Only accessible to authenticated users with the 'admin' role within
 * the requested enterprise.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { logger } from "firebase-functions/v2";

// ── Types ────────────────────────────────────────────────────────────────────

interface ExportRequest {
  enterpriseId: string;
  type: "sessions" | "tasks" | "photos" | "attendance" | "summary";
  period: {
    startDate: string; // ISO 8601 date string
    endDate: string;   // ISO 8601 date string
  };
  format: "csv";
}

interface ExportResponse {
  success: boolean;
  downloadUrl: string;
  fileName: string;
  recordCount: number;
}

// ── Helpers ──────────────────────────────────────────────────────────────────

/**
 * Escape a value for CSV output. Wraps in quotes if the value contains
 * commas, quotes, or newlines.
 */
function csvEscape(value: unknown): string {
  if (value === null || value === undefined) return "";
  const str = String(value);
  if (str.includes(",") || str.includes('"') || str.includes("\n")) {
    return `"${str.replace(/"/g, '""')}"`;
  }
  return str;
}

/**
 * Convert an array of objects into a CSV string.
 */
function toCsv(headers: string[], rows: Record<string, unknown>[]): string {
  const headerLine = headers.map(csvEscape).join(",");
  const dataLines = rows.map((row) =>
    headers.map((h) => csvEscape(row[h])).join(",")
  );
  return [headerLine, ...dataLines].join("\n");
}

/**
 * Format a Firestore Timestamp to a human-readable IST string.
 */
function formatTimestamp(
  ts: admin.firestore.Timestamp | undefined
): string {
  if (!ts) return "";
  const date = ts.toDate();
  const istOffsetMs = 330 * 60_000;
  const utcMs = date.getTime() + date.getTimezoneOffset() * 60_000;
  const istDate = new Date(utcMs + istOffsetMs);
  return istDate.toLocaleString("en-IN", {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: true,
  });
}

/**
 * Format seconds into HH:MM:SS.
 */
function formatDuration(seconds: number): string {
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = seconds % 60;
  return `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
}

// ── Data Fetchers ────────────────────────────────────────────────────────────

async function fetchSessionsCsv(
  db: admin.firestore.Firestore,
  enterpriseId: string,
  startTs: admin.firestore.Timestamp,
  endTs: admin.firestore.Timestamp,
  userNameMap: Map<string, string>
): Promise<{ csv: string; count: number }> {
  const snap = await db
    .collection("sessions")
    .where("enterpriseId", "==", enterpriseId)
    .where("startTime", ">=", startTs)
    .where("startTime", "<=", endTs)
    .orderBy("startTime", "asc")
    .get();

  const headers = [
    "sessionId",
    "employeeId",
    "employeeName",
    "startTime",
    "endTime",
    "status",
    "duration",
    "distance_km",
    "photosCount",
    "tasksCompleted",
    "notes",
  ];

  const rows = snap.docs.map((doc) => {
    const d = doc.data();
    return {
      sessionId: doc.id,
      employeeId: d.employeeId || "",
      employeeName: userNameMap.get(d.employeeId) || d.employeeId || "",
      startTime: formatTimestamp(d.startTime),
      endTime: formatTimestamp(d.endTime),
      status: d.status || "",
      duration: formatDuration(d.totalDuration || 0),
      distance_km: d.totalDistance || 0,
      photosCount: d.photosCount || 0,
      tasksCompleted: d.tasksCompleted || 0,
      notes: d.notes || "",
    };
  });

  return { csv: toCsv(headers, rows), count: rows.length };
}

async function fetchTasksCsv(
  db: admin.firestore.Firestore,
  enterpriseId: string,
  startTs: admin.firestore.Timestamp,
  endTs: admin.firestore.Timestamp,
  userNameMap: Map<string, string>
): Promise<{ csv: string; count: number }> {
  const snap = await db
    .collection("tasks")
    .where("enterpriseId", "==", enterpriseId)
    .where("createdAt", ">=", startTs)
    .where("createdAt", "<=", endTs)
    .orderBy("createdAt", "asc")
    .get();

  const headers = [
    "taskId",
    "title",
    "description",
    "type",
    "priority",
    "status",
    "assignedTo",
    "assignedToName",
    "assignedBy",
    "assignedByName",
    "dueDate",
    "completedAt",
    "createdAt",
  ];

  const rows = snap.docs.map((doc) => {
    const d = doc.data();
    return {
      taskId: doc.id,
      title: d.title || "",
      description: d.description || "",
      type: d.type || "",
      priority: d.priority || "",
      status: d.status || "",
      assignedTo: d.assignedTo || "",
      assignedToName: userNameMap.get(d.assignedTo) || d.assignedTo || "",
      assignedBy: d.assignedBy || "",
      assignedByName: userNameMap.get(d.assignedBy) || d.assignedBy || "",
      dueDate: formatTimestamp(d.dueDate),
      completedAt: formatTimestamp(d.completedAt),
      createdAt: formatTimestamp(d.createdAt),
    };
  });

  return { csv: toCsv(headers, rows), count: rows.length };
}

async function fetchPhotosCsv(
  db: admin.firestore.Firestore,
  enterpriseId: string,
  startTs: admin.firestore.Timestamp,
  endTs: admin.firestore.Timestamp,
  userNameMap: Map<string, string>
): Promise<{ csv: string; count: number }> {
  const snap = await db
    .collection("photos")
    .where("enterpriseId", "==", enterpriseId)
    .where("timestamp", ">=", startTs)
    .where("timestamp", "<=", endTs)
    .orderBy("timestamp", "asc")
    .get();

  const headers = [
    "photoId",
    "employeeId",
    "employeeName",
    "sessionId",
    "timestamp",
    "location",
    "latitude",
    "longitude",
    "imageUrl",
    "thumbnailUrl",
  ];

  const rows = snap.docs.map((doc) => {
    const d = doc.data();
    return {
      photoId: doc.id,
      employeeId: d.employeeId || "",
      employeeName: userNameMap.get(d.employeeId) || d.employeeId || "",
      sessionId: d.sessionId || "",
      timestamp: formatTimestamp(d.timestamp),
      location: d.location || "",
      latitude: d.latitude || "",
      longitude: d.longitude || "",
      imageUrl: d.imageUrl || "",
      thumbnailUrl: d.thumbnailUrl || "",
    };
  });

  return { csv: toCsv(headers, rows), count: rows.length };
}

async function fetchAttendanceCsv(
  db: admin.firestore.Firestore,
  enterpriseId: string,
  startTs: admin.firestore.Timestamp,
  endTs: admin.firestore.Timestamp,
  userNameMap: Map<string, string>
): Promise<{ csv: string; count: number }> {
  const snap = await db
    .collection("dailySummaries")
    .where("enterpriseId", "==", enterpriseId)
    .where("date", ">=", startTs)
    .where("date", "<=", endTs)
    .orderBy("date", "asc")
    .get();

  const headers = [
    "date",
    "employeeId",
    "employeeName",
    "totalDuration",
    "totalDistance_km",
    "photosCount",
    "tasksCompleted",
    "locationsVisited",
    "sessionCount",
    "isOffDuty",
  ];

  const rows = snap.docs.map((doc) => {
    const d = doc.data();
    const dateTs = d.date as admin.firestore.Timestamp | undefined;
    const dateStr = dateTs
      ? dateTs.toDate().toISOString().split("T")[0]
      : "";

    return {
      date: dateStr,
      employeeId: d.employeeId || "",
      employeeName: userNameMap.get(d.employeeId) || d.employeeId || "",
      totalDuration: formatDuration(d.totalDuration || 0),
      totalDistance_km: d.totalDistance || 0,
      photosCount: d.photosCount || 0,
      tasksCompleted: d.tasksCompleted || 0,
      locationsVisited: (d.locationsVisited || []).join("; "),
      sessionCount: (d.sessionIds || []).length,
      isOffDuty: d.isOffDuty ? "Yes" : "No",
    };
  });

  return { csv: toCsv(headers, rows), count: rows.length };
}

async function fetchSummaryCsv(
  db: admin.firestore.Firestore,
  enterpriseId: string,
  startTs: admin.firestore.Timestamp,
  endTs: admin.firestore.Timestamp,
  userNameMap: Map<string, string>
): Promise<{ csv: string; count: number }> {
  // Aggregate daily summaries per employee across the entire period
  const snap = await db
    .collection("dailySummaries")
    .where("enterpriseId", "==", enterpriseId)
    .where("date", ">=", startTs)
    .where("date", "<=", endTs)
    .get();

  // Aggregate per employee
  const aggMap = new Map<
    string,
    {
      totalDuration: number;
      totalDistance: number;
      photosCount: number;
      tasksCompleted: number;
      daysWorked: number;
      totalSessions: number;
    }
  >();

  for (const doc of snap.docs) {
    const d = doc.data();
    const employeeId = d.employeeId as string;
    const existing = aggMap.get(employeeId) || {
      totalDuration: 0,
      totalDistance: 0,
      photosCount: 0,
      tasksCompleted: 0,
      daysWorked: 0,
      totalSessions: 0,
    };

    existing.totalDuration += d.totalDuration || 0;
    existing.totalDistance += d.totalDistance || 0;
    existing.photosCount += d.photosCount || 0;
    existing.tasksCompleted += d.tasksCompleted || 0;
    existing.daysWorked += d.isOffDuty ? 0 : 1;
    existing.totalSessions += (d.sessionIds || []).length;

    aggMap.set(employeeId, existing);
  }

  const headers = [
    "employeeId",
    "employeeName",
    "totalDuration",
    "avgDailyDuration",
    "totalDistance_km",
    "photosCount",
    "tasksCompleted",
    "daysWorked",
    "totalSessions",
  ];

  const rows: Record<string, unknown>[] = [];
  for (const [employeeId, stats] of aggMap.entries()) {
    const avgDuration =
      stats.daysWorked > 0
        ? Math.round(stats.totalDuration / stats.daysWorked)
        : 0;

    rows.push({
      employeeId,
      employeeName: userNameMap.get(employeeId) || employeeId,
      totalDuration: formatDuration(stats.totalDuration),
      avgDailyDuration: formatDuration(avgDuration),
      totalDistance_km: Math.round(stats.totalDistance * 100) / 100,
      photosCount: stats.photosCount,
      tasksCompleted: stats.tasksCompleted,
      daysWorked: stats.daysWorked,
      totalSessions: stats.totalSessions,
    });
  }

  return { csv: toCsv(headers, rows), count: rows.length };
}

// ── Main Function ────────────────────────────────────────────────────────────

export const exportReport = onCall<ExportRequest>(
  {
    region: "asia-south1",
    timeoutSeconds: 120,
    memory: "512MiB",
  },
  async (request): Promise<ExportResponse> => {
    // ── Authentication & Authorization ─────────────────────────────────
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const claims = request.auth.token;
    const claimRoles = claims.roles as string[] | undefined;
    const claimActiveRole = claims.activeRole || claims.role;
    if (!(claimRoles && claimRoles.includes("admin")) && claimActiveRole !== "admin") {
      throw new HttpsError(
        "permission-denied",
        "Only administrators can export reports."
      );
    }

    const data = request.data;

    // ── Input Validation ───────────────────────────────────────────────
    if (!data.enterpriseId || typeof data.enterpriseId !== "string") {
      throw new HttpsError(
        "invalid-argument",
        "enterpriseId is required and must be a string."
      );
    }

    // Verify the admin belongs to the requested enterprise
    if (claims.enterpriseId !== data.enterpriseId) {
      throw new HttpsError(
        "permission-denied",
        "You can only export data for your own enterprise."
      );
    }

    const validTypes = ["sessions", "tasks", "photos", "attendance", "summary"];
    if (!data.type || !validTypes.includes(data.type)) {
      throw new HttpsError(
        "invalid-argument",
        `type must be one of: ${validTypes.join(", ")}`
      );
    }

    if (
      !data.period ||
      !data.period.startDate ||
      !data.period.endDate
    ) {
      throw new HttpsError(
        "invalid-argument",
        "period.startDate and period.endDate are required (ISO 8601)."
      );
    }

    const startDate = new Date(data.period.startDate);
    const endDate = new Date(data.period.endDate);

    if (isNaN(startDate.getTime()) || isNaN(endDate.getTime())) {
      throw new HttpsError(
        "invalid-argument",
        "Invalid date format. Use ISO 8601 (e.g. 2026-02-01)."
      );
    }

    if (startDate > endDate) {
      throw new HttpsError(
        "invalid-argument",
        "startDate must be before or equal to endDate."
      );
    }

    // Limit export range to 90 days to prevent excessive data
    const maxRangeMs = 90 * 24 * 60 * 60 * 1000;
    if (endDate.getTime() - startDate.getTime() > maxRangeMs) {
      throw new HttpsError(
        "invalid-argument",
        "Export range cannot exceed 90 days."
      );
    }

    if (data.format && data.format !== "csv") {
      throw new HttpsError(
        "invalid-argument",
        "Only CSV format is currently supported."
      );
    }

    logger.info("exportReport: Starting export.", {
      enterpriseId: data.enterpriseId,
      type: data.type,
      startDate: data.period.startDate,
      endDate: data.period.endDate,
    });

    const db = admin.firestore();
    const startTs = admin.firestore.Timestamp.fromDate(startDate);
    const endTs = admin.firestore.Timestamp.fromDate(endDate);

    // ── Pre-fetch user names for the enterprise ────────────────────────
    const usersSnap = await db
      .collection("users")
      .where("enterpriseId", "==", data.enterpriseId)
      .get();

    const userNameMap = new Map<string, string>();
    for (const userDoc of usersSnap.docs) {
      const userData = userDoc.data();
      userNameMap.set(userDoc.id, userData.name || userDoc.id);
    }

    // ── Generate CSV based on type ─────────────────────────────────────
    let csvContent: string;
    let recordCount: number;

    switch (data.type) {
      case "sessions": {
        const result = await fetchSessionsCsv(
          db, data.enterpriseId, startTs, endTs, userNameMap
        );
        csvContent = result.csv;
        recordCount = result.count;
        break;
      }
      case "tasks": {
        const result = await fetchTasksCsv(
          db, data.enterpriseId, startTs, endTs, userNameMap
        );
        csvContent = result.csv;
        recordCount = result.count;
        break;
      }
      case "photos": {
        const result = await fetchPhotosCsv(
          db, data.enterpriseId, startTs, endTs, userNameMap
        );
        csvContent = result.csv;
        recordCount = result.count;
        break;
      }
      case "attendance": {
        const result = await fetchAttendanceCsv(
          db, data.enterpriseId, startTs, endTs, userNameMap
        );
        csvContent = result.csv;
        recordCount = result.count;
        break;
      }
      case "summary": {
        const result = await fetchSummaryCsv(
          db, data.enterpriseId, startTs, endTs, userNameMap
        );
        csvContent = result.csv;
        recordCount = result.count;
        break;
      }
      default:
        throw new HttpsError("invalid-argument", `Unknown export type: ${data.type}`);
    }

    if (recordCount === 0) {
      throw new HttpsError(
        "not-found",
        "No data found for the specified period and type."
      );
    }

    // ── Upload CSV to Cloud Storage ────────────────────────────────────
    const timestamp = new Date()
      .toISOString()
      .replace(/[:.]/g, "-")
      .replace("T", "_")
      .substring(0, 19);
    const fileName = `${data.type}_${timestamp}.csv`;
    const storagePath = `enterprises/${data.enterpriseId}/exports/${fileName}`;

    const bucket = admin.storage().bucket();
    const file = bucket.file(storagePath);

    await file.save(csvContent, {
      contentType: "text/csv",
      metadata: {
        metadata: {
          exportType: data.type,
          enterpriseId: data.enterpriseId,
          startDate: data.period.startDate,
          endDate: data.period.endDate,
          recordCount: String(recordCount),
          exportedBy: request.auth.uid,
          exportedAt: new Date().toISOString(),
        },
      },
    });

    // Generate a signed URL valid for 7 days
    const [signedUrl] = await file.getSignedUrl({
      action: "read",
      expires: Date.now() + 7 * 24 * 60 * 60 * 1000, // 7 days
    });

    logger.info("exportReport: Export completed.", {
      enterpriseId: data.enterpriseId,
      type: data.type,
      recordCount,
      storagePath,
    });

    return {
      success: true,
      downloadUrl: signedUrl,
      fileName,
      recordCount,
    };
  }
);
