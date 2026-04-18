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

// ── Force Logout (single-device enforcement via FCM) ──────────────────────
export { onForceLogoutCreated } from "./force_logout/on_force_logout_created";

// ── Session Triggers ───────────────────────────────────────────────────────
export { onSessionComplete } from "./sessions/on_session_complete";
export { onSessionStarted, onSessionEnded } from "./sessions/on_session_event";
export { onPresenceOffline } from "./sessions/on_presence_offline";
export { onSessionLocationCreated } from "./sessions/on_session_location_created";

// ── Photo Triggers ─────────────────────────────────────────────────────────
export { onPhotoUpload } from "./photos/on_photo_upload";
export { onPhotoDocumentCreated } from "./photos/on_photo_document_created";

// ── Task Triggers ──────────────────────────────────────────────────────────
export { onTaskAssigned } from "./tasks/on_task_assigned";
export { onTaskCompleted } from "./tasks/on_task_completed";

// ── Chat Triggers ─────────────────────────────────────────────────────────
export { onChatMessage } from "./chat/on_chat_message";
export { onGroupUpdated } from "./chat/on_group_updated";
export { enrichLocationUpdate } from "./logs/enrich_location_update";

// ── Scheduled Functions ────────────────────────────────────────────────────
export { dailySummaryAggregator } from "./scheduled/daily_summary_aggregator";
export { checkAnalyticsIntegrity } from "./scheduled/check_analytics_integrity";
export { cleanupOldExports } from "./scheduled/cleanup_old_exports";
export { sanitizeActiveStats } from "./scheduled/sanitize_active_stats";
export { sweepSignalLostSessions } from "./scheduled/sweep_signal_lost_sessions";

// ── HTTPS Callable Functions ───────────────────────────────────────────────
export { exportReport } from "./callable/export_report";
export { migrateOrphanedTasks } from "./callable/migrate_orphaned_tasks";
export { migrateGroupMemberIds } from "./callable/migrate_group_member_ids";
export { migrateHistoricalAnalytics } from "./callable/migrate_historical_analytics";
export { migrateHistoricalPhotos } from "./callable/migrate_historical_photos";
export { resolveUserOnLogin } from "./callable/resolve_user_on_login";
export { ensureClaims } from "./callable/ensure_claims";
export { updateUserRole } from "./callable/update_user_role";
export { syncLinkedChatGroups } from "./callable/sync_linked_chat_groups";
export { deleteUser } from "./callable/delete_user";
export { adminCleanup } from "./callable/admin_cleanup";
export { cleanupOrphanData } from "./callable/cleanup_orphan_data";
export { forceEndAllSessions } from "./callable/force_end_all_sessions";
export { backfillActivityLogs } from "./callable/backfill_activity_logs";
export { backfillSessionDistances } from "./callable/backfill_session_distances";
export { backfillThumbnails } from "./callable/backfill_thumbnails";
export { broadcastDiagnosticCommand } from "./callable/broadcast_diagnostic";
