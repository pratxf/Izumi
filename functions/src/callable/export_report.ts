/**
 * exportReport - HTTPS Callable Function
 *
 * Generates data exports in CSV, Excel (.xlsx), or PDF format.
 *
 * Accepts:
 *   - enterpriseId: string
 *   - type: 'sessions' | 'tasks' | 'photos' | 'attendance' | 'summary'
 *   - period: { startDate: string (ISO), endDate: string (ISO) }
 *   - format: 'csv' | 'excel' | 'pdf'
 *
 * Queries Firestore data, generates the file, uploads to Cloud Storage,
 * and returns a download URL.
 *
 * Only accessible to authenticated admin users.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { logger } from "firebase-functions/v2";
import * as crypto from "crypto";

// ── Types ────────────────────────────────────────────────────────────────────

type ExportType = "sessions" | "tasks" | "photos" | "attendance" | "summary" | "customers";
type ExportFormat = "csv";

interface ExportRequest {
  enterpriseId: string;
  type: ExportType;
  period?: {
    startDate: string;
    endDate: string;
  };
  categories?: string[];
  format: ExportFormat;
}

interface ExportResponse {
  success: boolean;
  downloadUrl: string;
  fileName: string;
  recordCount: number;
}

interface TableData {
  headers: string[];
  rows: Record<string, unknown>[];
}

// ── Formatting Helpers ───────────────────────────────────────────────────────

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

function formatDuration(seconds: number): string {
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = seconds % 60;
  return `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
}

// ── CSV Generator ────────────────────────────────────────────────────────────

function csvEscape(value: unknown): string {
  if (value === null || value === undefined) return "";
  const str = String(value);
  if (str.includes(",") || str.includes('"') || str.includes("\n")) {
    return `"${str.replace(/"/g, '""')}"`;
  }
  return str;
}

function formatCsv(data: TableData): Buffer {
  const { headers, rows } = data;
  const headerLine = headers.map(csvEscape).join(",");
  const dataLines = rows.map((row) =>
    headers.map((h) => csvEscape(row[h])).join(",")
  );
  return Buffer.from([headerLine, ...dataLines].join("\n"), "utf-8");
}

// ── Data Fetchers ────────────────────────────────────────────────────────────

async function fetchSessions(
  db: admin.firestore.Firestore,
  enterpriseId: string,
  startTs: admin.firestore.Timestamp,
  endTs: admin.firestore.Timestamp,
  userNameMap: Map<string, string>
): Promise<TableData> {
  const snap = await db
    .collection("sessions")
    .where("enterpriseId", "==", enterpriseId)
    .where("startTime", ">=", startTs)
    .where("startTime", "<=", endTs)
    .orderBy("startTime", "asc")
    .get();

  const headers = [
    "sessionId", "employeeId", "employeeName", "startTime", "endTime",
    "status", "duration", "distance_km", "photosCount", "tasksCompleted", "notes",
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

  return { headers, rows };
}

async function fetchTasks(
  db: admin.firestore.Firestore,
  enterpriseId: string,
  startTs: admin.firestore.Timestamp,
  endTs: admin.firestore.Timestamp,
  userNameMap: Map<string, string>
): Promise<TableData> {
  const snap = await db
    .collection("tasks")
    .where("enterpriseId", "==", enterpriseId)
    .where("createdAt", ">=", startTs)
    .where("createdAt", "<=", endTs)
    .orderBy("createdAt", "asc")
    .get();

  const headers = [
    "taskId", "title", "description", "type", "priority", "status",
    "assignedTo", "assignedToName", "assignedBy", "assignedByName",
    "dueDate", "completedAt", "createdAt",
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

  return { headers, rows };
}

async function fetchPhotos(
  db: admin.firestore.Firestore,
  enterpriseId: string,
  startTs: admin.firestore.Timestamp,
  endTs: admin.firestore.Timestamp,
  userNameMap: Map<string, string>
): Promise<TableData> {
  const snap = await db
    .collection("photos")
    .where("enterpriseId", "==", enterpriseId)
    .where("timestamp", ">=", startTs)
    .where("timestamp", "<=", endTs)
    .orderBy("timestamp", "asc")
    .get();

  const headers = [
    "photoId", "employeeId", "employeeName", "sessionId", "timestamp",
    "location", "latitude", "longitude", "imageUrl", "thumbnailUrl",
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

  return { headers, rows };
}

async function fetchAttendance(
  db: admin.firestore.Firestore,
  enterpriseId: string,
  startTs: admin.firestore.Timestamp,
  endTs: admin.firestore.Timestamp,
  userNameMap: Map<string, string>
): Promise<TableData> {
  const snap = await db
    .collection("dailySummaries")
    .where("enterpriseId", "==", enterpriseId)
    .where("date", ">=", startTs)
    .where("date", "<=", endTs)
    .orderBy("date", "asc")
    .get();

  const headers = [
    "date", "employeeId", "employeeName", "totalDuration", "totalDistance_km",
    "photosCount", "tasksCompleted", "locationsVisited", "sessionCount", "isOffDuty",
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

  return { headers, rows };
}

async function fetchSummary(
  db: admin.firestore.Firestore,
  enterpriseId: string,
  startTs: admin.firestore.Timestamp,
  endTs: admin.firestore.Timestamp,
  userNameMap: Map<string, string>
): Promise<TableData> {
  const snap = await db
    .collection("dailySummaries")
    .where("enterpriseId", "==", enterpriseId)
    .where("date", ">=", startTs)
    .where("date", "<=", endTs)
    .get();

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
    "employeeId", "employeeName", "totalDuration", "avgDailyDuration",
    "totalDistance_km", "photosCount", "tasksCompleted", "daysWorked", "totalSessions",
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

  return { headers, rows };
}

async function fetchCustomers(
  db: admin.firestore.Firestore,
  enterpriseId: string,
  categories: string[],
  userNameMap: Map<string, string>
): Promise<TableData> {
  const snap = await db
    .collection("photos")
    .where("enterpriseId", "==", enterpriseId)
    .where("category", "in", categories)
    .orderBy("timestamp", "asc")
    .get();

  const headers = [
    "Employee Name", "Category", "Customer Type", "Customer Name",
    "Customer Phone", "Location", "Latitude", "Longitude",
    "Date/Time", "Notes", "Has Follow-up", "Image URL",
  ];

  const rows = snap.docs.map((doc) => {
    const d = doc.data();
    return {
      "Employee Name": userNameMap.get(d.employeeId) || d.employeeId || "",
      "Category": d.category || "",
      "Customer Type": d.customerType || "",
      "Customer Name": d.customerName || "",
      "Customer Phone": d.customerPhone || "",
      "Location": d.location || "",
      "Latitude": d.latitude ?? "",
      "Longitude": d.longitude ?? "",
      "Date/Time": formatTimestamp(d.timestamp),
      "Notes": d.notes || "",
      "Has Follow-up": d.hasFollowUp ? "Yes" : "No",
      "Image URL": d.imageUrl || "",
    };
  });

  return { headers, rows };
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
    if (
      !(claimRoles && claimRoles.includes("admin")) &&
      claimActiveRole !== "admin"
    ) {
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

    if (claims.enterpriseId !== data.enterpriseId) {
      throw new HttpsError(
        "permission-denied",
        "You can only export data for your own enterprise."
      );
    }

    const validTypes: ExportType[] = [
      "sessions", "tasks", "photos", "attendance", "summary", "customers",
    ];
    if (!data.type || !validTypes.includes(data.type)) {
      throw new HttpsError(
        "invalid-argument",
        `type must be one of: ${validTypes.join(", ")}`
      );
    }

    const format = data.format || "csv";
    if (format !== "csv") {
      throw new HttpsError(
        "invalid-argument",
        "Only CSV format is supported."
      );
    }

    // Customers type uses categories instead of date range
    if (data.type === "customers") {
      if (
        !data.categories ||
        !Array.isArray(data.categories) ||
        data.categories.length === 0
      ) {
        throw new HttpsError(
          "invalid-argument",
          "categories is required for customers export (e.g. ['distributor', 'farmer'])."
        );
      }
      const validCategories = ["distributor", "farmer"];
      for (const cat of data.categories) {
        if (!validCategories.includes(cat)) {
          throw new HttpsError(
            "invalid-argument",
            `Invalid category: ${cat}. Must be one of: ${validCategories.join(", ")}`
          );
        }
      }
    }

    let startTs: admin.firestore.Timestamp | undefined;
    let endTs: admin.firestore.Timestamp | undefined;

    if (data.type !== "customers") {
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

      const maxRangeMs = 90 * 24 * 60 * 60 * 1000;
      if (endDate.getTime() - startDate.getTime() > maxRangeMs) {
        throw new HttpsError(
          "invalid-argument",
          "Export range cannot exceed 90 days."
        );
      }

      startTs = admin.firestore.Timestamp.fromDate(startDate);
      endTs = admin.firestore.Timestamp.fromDate(endDate);
    }

    logger.info("exportReport: Starting export.", {
      enterpriseId: data.enterpriseId,
      type: data.type,
      format,
      ...(data.type === "customers"
        ? { categories: data.categories }
        : { startDate: data.period?.startDate, endDate: data.period?.endDate }),
    });

    const db = admin.firestore();

    try {
      // ── Pre-fetch user names for the enterprise ──────────────────────
      const usersSnap = await db
        .collection("users")
        .where("enterpriseId", "==", data.enterpriseId)
        .get();

      const userNameMap = new Map<string, string>();
      for (const userDoc of usersSnap.docs) {
        const userData = userDoc.data();
        userNameMap.set(userDoc.id, userData.name || userDoc.id);
      }

      // ── Fetch raw data based on type ─────────────────────────────────
      let tableData: TableData;

      switch (data.type) {
        case "sessions":
          tableData = await fetchSessions(
            db, data.enterpriseId, startTs!, endTs!, userNameMap
          );
          break;
        case "tasks":
          tableData = await fetchTasks(
            db, data.enterpriseId, startTs!, endTs!, userNameMap
          );
          break;
        case "photos":
          tableData = await fetchPhotos(
            db, data.enterpriseId, startTs!, endTs!, userNameMap
          );
          break;
        case "attendance":
          tableData = await fetchAttendance(
            db, data.enterpriseId, startTs!, endTs!, userNameMap
          );
          break;
        case "summary":
          tableData = await fetchSummary(
            db, data.enterpriseId, startTs!, endTs!, userNameMap
          );
          break;
        case "customers":
          tableData = await fetchCustomers(
            db, data.enterpriseId, data.categories!, userNameMap
          );
          break;
        default:
          throw new HttpsError(
            "invalid-argument",
            `Unknown export type: ${data.type}`
          );
      }

      const recordCount = tableData.rows.length;
      if (recordCount === 0) {
        throw new HttpsError(
          "not-found",
          "No data found for the specified period and type."
        );
      }

      // ── Generate CSV file ────────────────────────────────────────────
      const fileBuffer = formatCsv(tableData);
      const contentType = "text/csv";
      const fileExtension = "csv";

      // ── Upload to Cloud Storage ──────────────────────────────────────
      const timestamp = new Date()
        .toISOString()
        .replace(/[:.]/g, "-")
        .replace("T", "_")
        .substring(0, 19);
      const fileName = `${data.type}_${timestamp}.${fileExtension}`;
      const storagePath = `enterprises/${data.enterpriseId}/exports/${fileName}`;

      const bucket = admin.storage().bucket();
      const file = bucket.file(storagePath);
      const downloadToken = crypto.randomUUID();

      await file.save(fileBuffer, {
        contentType,
        metadata: {
          metadata: {
            firebaseStorageDownloadTokens: downloadToken,
            exportType: data.type,
            exportFormat: format,
            enterpriseId: data.enterpriseId,
            ...(data.period ? { startDate: data.period.startDate, endDate: data.period.endDate } : {}),
            ...(data.categories ? { categories: data.categories.join(",") } : {}),
            recordCount: String(recordCount),
            exportedBy: request.auth.uid,
            exportedAt: new Date().toISOString(),
          },
        },
      });

      // Build Firebase download URL (no IAM role needed, unlike getSignedUrl)
      const bucketName = bucket.name;
      const encodedPath = encodeURIComponent(storagePath);
      const downloadUrl =
        `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/${encodedPath}?alt=media&token=${downloadToken}`;

      logger.info("exportReport: Export completed.", {
        enterpriseId: data.enterpriseId,
        type: data.type,
        format,
        recordCount,
        storagePath,
      });

      return {
        success: true,
        downloadUrl,
        fileName,
        recordCount,
      };
    } catch (error) {
      // Re-throw HttpsError as-is (validation / not-found errors)
      if (error instanceof HttpsError) {
        throw error;
      }
      logger.error("exportReport: Unexpected error.", {
        enterpriseId: data.enterpriseId,
        type: data.type,
        error: String(error),
      });
      throw new HttpsError(
        "internal",
        `Export failed for type "${data.type}": ${error instanceof Error ? error.message : String(error)}`
      );
    }
  }
);
