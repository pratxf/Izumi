/**
 * Izumi Cloud Functions - Main Entry Point
 *
 * Exports all Cloud Functions for the Izumi Field Workforce
 * Management & Intelligence Platform.
 *
 * All functions are deployed to the asia-south1 region.
 */

import * as admin from "firebase-admin";

// Initialize Firebase Admin SDK (must be done before importing functions)
admin.initializeApp();

// ── Auth Triggers ──────────────────────────────────────────────────────────
export { onUserCreate } from "./auth/on_user_create";

// ── Session Triggers ───────────────────────────────────────────────────────
export { onSessionComplete } from "./sessions/on_session_complete";

// ── Photo Triggers ─────────────────────────────────────────────────────────
export { onPhotoUpload } from "./photos/on_photo_upload";

// ── Task Triggers ──────────────────────────────────────────────────────────
export { onTaskAssigned } from "./tasks/on_task_assigned";

// ── Scheduled Functions ────────────────────────────────────────────────────
export { dailySummaryAggregator } from "./scheduled/daily_summary_aggregator";
export { cleanupOldExports } from "./scheduled/cleanup_old_exports";

// ── HTTPS Callable Functions ───────────────────────────────────────────────
export { exportReport } from "./callable/export_report";
export { migrateOrphanedTasks } from "./callable/migrate_orphaned_tasks";
export { resolveUserOnLogin } from "./callable/resolve_user_on_login";
