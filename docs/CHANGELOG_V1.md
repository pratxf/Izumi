# Izumi v1.0 Changelog

Complete record of all changes made during the v1.0.40–v1.0.46 development cycle.

---

## v1.0.46 (Build 46)

### Feature 1: Team Lead Live Activity Dashboard

**Files changed:**
- `lib/screens/employee/team_screen.dart`
- `lib/screens/employee/team_lead_employee_detail_screen.dart`

**What changed:**

Team Monitor tab redesigned:
- Summary bar now shows **Active agent count** (scoped to team lead's group only) instead of "Total Tasks"
- Employee cards show **profile pictures** (from `profileImageUrl`, fallback to initials)
- Active employees show **distance (km)** and **photos count** below location
- Offline employees show **"Last seen X ago"** timestamp
- Status rings on avatars color-coded: green (active), orange (break), dark red (signal lost), grey (offline)

Team Lead Employee Detail screen fully rewritten:
- **Header**: Avatar with status ring, name, status badge, current location
- **Today's Summary**: 4-stat row — Duration, Distance, Photos, Tasks (from RTDB `activeStats`)
- **Tasks & Follow-ups**: Summary cards with progress bars + task lists with priority badges
- **Photos Section**: Grid of up to 6 recent photos from today
- **Live Activity Feed**: Last 24 hours of activity logs (sessions, locations, photos, tasks) with auto-refresh every 60 seconds

### Feature 2: Offline-First SQLite Queue Expansion

**Files changed:**
- `lib/offline_queue/offline_job.dart`
- `lib/offline_queue/offline_queue_manager.dart`

**What changed:**

New job types added:
- `locationSync` — queued location batch uploads
- `activityLog` — queued activity log writes
- `sessionEvent` — queued session start/end writes
- `taskEvent` — queued task status changes

New job statuses:
- `done` — successfully processed, kept for idempotency
- `failed` — exceeded max retries (10), permanently failed

Generic Firestore write handler (`_processGenericFirestoreJob`):
- Reads `collection`, `docId`, `data`, `merge` from job payload
- Writes to Firestore with merge support
- Works for any collection without custom handler code

Queue processing improvements:
- Max 10 retry attempts before marking `failed`
- Backoff capped at 1800 seconds (30 minutes): `min(2^attempts * 30, 1800)`
- Failed jobs kept in SQLite (idempotency key prevents re-insertion)

### Bug Fixes in v1.0.46

**Bug 3 & 7 — 16hr session duration cap:**
- `analytics_provider.dart`: `_resolveLiveDurationSecs()` clamps to 57,600 seconds (16 hours)
- `_recomputeTotals()` and `getEmployeeStats()` both cap per-session duration
- `sweep_signal_lost_sessions.ts`: Added `MAX_SESSION_DURATION_MS` (16 hours). Sweeper queries all `active` sessions with `startTime` older than 16 hours and force-ends them with `autoEndReason: exceeded_max_duration`

**Bug 4 — Activity feed empty unless analytics visited first:**
- `employee_detail_screen.dart`: Ensures `DashboardProvider.initDashboard()` completes before calling `_startRecentFeed()`, regardless of whether dashboard was previously visited

**Bug 5 — Activity timeline incomplete:**
- `admin_activity_feed_service.dart`: Increased all activity log query limits from 200–300 to 1000

**Bug 6 — Duplicate session events / rapid cycling:**
- `session_provider.dart`: Added 60-second debounce on `startSession()`. If a session was attempted within the last 60 seconds, returns error message instead of creating new session

**Bug 8 — Photo EXIF rotation:**
- `image_processing_service.dart`: Added `autoCorrectionAngle: true` and `keepExif: false` to `FlutterImageCompress.compressWithFile()`. This bakes EXIF orientation into pixel data so photos display correctly regardless of viewer EXIF support.
- `photo_provider.dart`: Direct upload path now uses `ImageProcessingService.preparePhotoForUpload()` with 20s timeout, falling back to raw bytes if compression fails

**Bug 10 — App logs out user when closed:**
- `auth_provider.dart`: Fixed single-device enforcement false positive. When app restarts after being killed, the RTDB device session token may be null/empty (cleared by onDisconnect). Previously this triggered a forced signout. Now, if the remote token is null or empty, the device reclaims the session instead of signing out.

---

## v1.0.45 (Build 45)

### User Management Fixes

**Files changed:**
- `lib/providers/user_provider.dart`
- `lib/screens/admin/user_management_screen.dart`
- `lib/screens/admin/add_user_screen.dart`
- `lib/providers/auth_provider.dart`
- `functions/src/callable/delete_user.ts`
- `functions/src/callable/admin_cleanup.ts`
- `functions/src/callable/resolve_user_on_login.ts`
- `functions/src/index.ts`

**Root cause:** When admin deleted a user, only the Firestore doc was deleted. The Firebase Auth account persisted with the old phone number. When the same phone was re-added and the user logged in, Firebase Auth reused the old UID with stale custom claims (often `role: admin`), routing them to the wrong screen.

**Fixes:**

Phone format normalization:
- `add_user_screen.dart`: Phone input now strips spaces, dashes, and parentheses before saving (`99174 94487` becomes `9917494487`)

Delete user — full cleanup:
- New Cloud Function `deleteUser`: Deletes Firebase Auth user by UID first, then falls back to phone number lookup via `admin.auth().getUserByPhoneNumber()`. Also removes user from groups, chat groups, and cleans up RTDB (presence, activeStats, heartbeat, liveLocations)
- `user_provider.dart`: Now calls Cloud Function instead of just deleting Firestore doc

Admin cleanup utility:
- New Cloud Function `adminCleanup`: One-time utility for fixing broken users. Deletes Auth by phone, clears stale Firestore docs, optionally recreates with correct role. Supports `deleteOnly` mode.

Login role resolution:
- `resolve_user_on_login.ts`: Added normalized phone fallback — if exact phone query fails, scans all user docs matching the normalized phone (stripped of formatting), fixes the stored phone, then continues migration
- `auth_provider.dart`: After `_waitForClaims()`, checks if claims returned a stale role that differs from the Firestore doc. If so, trusts the Firestore doc's role.

---

## v1.0.44 (Build 44)

### Stale Session Sweep & Upload Fixes

**Files changed:**
- `lib/offline_queue/offline_queue_manager.dart`
- `android/app/src/main/kotlin/com/izumi/izumi/SessionTaskRemovalService.kt`
- `functions/src/scheduled/sweep_signal_lost_sessions.ts`
- `functions/src/callable/delete_user.ts` (new)
- `functions/src/index.ts`

**Sweep improvements:**
- Sweep now catches stale `active` sessions (not just `signal_lost`). Checks `lastSeen` heartbeat age for `active`/`break` statuses — if > 1 hour, auto-ends the session
- Re-validates latest presence data before acting to avoid race conditions

**Duplicate timeline fix:**
- `SessionTaskRemovalService.kt`: Changed activity log document ID from auto-generated (`document()`) to deterministic (`session_auto_ended_$sessionId`). Now all three sources of session-end logs (Dart handler, Kotlin service, Cloud Function) write to the same document — overwrites instead of duplicates.

**Old queue photo uploads:**
- `offline_queue_manager.dart`: Removed `dailySummaries` write from `_processPhotoJob` batch. This was the root cause of ALL photo upload failures — `dailySummaries` has `allow write: if false` in Firestore rules, which failed the entire batch.

---

## v1.0.43 (Build 43)

### Photo Upload Fix

**Files changed:**
- `lib/providers/photo_provider.dart` (major rewrite)
- `lib/screens/employee/preview_screen.dart`
- `lib/screens/employee/gallery_screen.dart`
- `lib/screens/employee/home_screen.dart`
- `lib/offline_queue/offline_queue_manager.dart`
- `lib/services/image_processing_service.dart`
- `android/app/src/main/AndroidManifest.xml`
- `android/app/src/main/res/values/colors.xml` (new)
- `lib/tracking/tracking_task_handler.dart`

**Root cause:** The `dailySummaries` collection in Firestore has `allow write: if false` security rules. The photo upload batch included a `dailySummaries` increment, which caused the ENTIRE batch (photo doc + chat share + summary) to fail with `permission-denied`. This affected both the offline queue path and would have affected any direct upload.

**Fix — Direct upload rewrite:**
- `photo_provider.dart`: Completely rewrote `uploadPhoto()` to bypass the offline queue. Now uploads directly to Firebase Storage and writes Firestore doc in a batch — no `ImageProcessingService`, no `OfflineQueueManager`, no `PersistentMediaFileManager` in the upload path. Works exactly like the chat camera (which was always working).
- Removed `dailySummaries` from the batch (Cloud Functions handle this via `on_photo_document_created.ts` and `daily_summary_aggregator.ts`)

**Upload error visibility:**
- `preview_screen.dart`: Now checks `photo.uploadStatus == UploadStatus.success` before showing success message. Shows red error snackbar with actual error text on failure.
- `gallery_screen.dart`: Added queue event listener that shows red snackbar with error details when photo jobs fail. Gallery open triggers `retryAllNow()`.

**Queue reliability improvements:**
- `offline_queue_manager.dart`: Added 60-second timeout on each job. Force-breaks stuck `_isProcessing` lock after 2 minutes. `retryAllNow()` resets both `error` and stuck `processing` jobs. Compression wrapped in try/catch with raw bytes fallback.
- `image_processing_service.dart`: Added 15s/10s timeouts on compression calls

**Notification icon fix:**
- `AndroidManifest.xml`: Added `com.google.firebase.messaging.default_notification_icon` and `default_notification_color` metadata for FCM push notifications
- `tracking_task_handler.dart`: Local notification init uses `ic_stat_izumi` instead of `@mipmap/ic_launcher`. Added `icon: 'ic_stat_izumi'` to notification details.

**Session auto-end fixes:**
- `tracking_task_handler.dart`: `onDestroy` now checks if session context was cleared from shared storage (= normal end). If cleared, skips auto-end entirely. Prevents duplicate notifications on manual session end.
- `tracking_foreground_service.dart`: `startTracking()` no longer calls `restartService()` when service is already running. Instead sends `refresh_context` message. Prevents `onDestroy` race condition that was auto-ending sessions immediately after start.
- Added 30-second minimum session age check — skips auto-end for sessions younger than 30 seconds

**Upload retry on app resume:**
- `home_screen.dart`: Added `WidgetsBindingObserver`. On `AppLifecycleState.resumed`, calls `OfflineQueueManager.instance.retryAllNow()`.

---

## v1.0.42 (Build 42)

### Notification Icon & Upload Retry

**Files changed:**
- `android/app/src/main/AndroidManifest.xml`
- `android/app/src/main/res/values/colors.xml` (new)
- `lib/offline_queue/offline_queue_manager.dart`
- `lib/screens/employee/home_screen.dart`
- `lib/tracking/tracking_task_handler.dart`
- `pubspec.yaml`

---

## v1.0.41 (Build 41)

### Session Auto-End Race Condition

**Files changed:**
- `lib/tracking/tracking_foreground_service.dart`
- `lib/tracking/tracking_task_handler.dart`
- `functions/src/sessions/on_presence_offline.ts`

**Root cause:** `startTracking()` called `restartService()` when the foreground service was already running (from `autoRunOnBoot`). This triggered `onDestroy` on the handler that had already loaded the NEW session context, immediately auto-ending the session the user just created.

**Fixes:**
- `tracking_foreground_service.dart`: If service is running, send `refresh_context` instead of `restartService()`
- `tracking_task_handler.dart`: 30-second minimum session age guard in `onDestroy`
- `on_presence_offline.ts`: Reduced heartbeat stale threshold from 4 hours to 1 hour

---

## v1.0.40 (Build 40)

### Precise Location Addresses

**Files changed:**
- `lib/services/geocoding_cache.dart`
- `lib/tracking/sync_manager.dart`
- `lib/tracking/tracking_task_handler.dart`

**What changed:**
- Reverse geocoding now includes **street/thoroughfare** names for pin-point accuracy
- Address format: "street, subLocality, locality" (e.g., "MG Road, Ratanada, Jodhpur") instead of just "Jodhpur"
- Geocoding cache precision increased from ~100m (3 decimal places) to ~11m (4 decimal places)

**Also included (from previous session):**
- Enterprise-wide photo fallback for employee activity screen
- Client-side reverse geocoding via `GeocodingCache` for admin screens
- Write-time reverse geocoding for new location data
- Foreground service `autoRunOnBoot: true` for service restart after reboot
- Dashboard heartbeat staleness detection (35-minute grace)
- `RECEIVE_BOOT_COMPLETED` permission in AndroidManifest
- 30-second timeout on `Geolocator.getCurrentPosition()`

---

## Cloud Functions Deployed

| Function | Version | What Changed |
|----------|---------|-------------|
| `sweepSignalLostSessions` | v3 | Checks stale active sessions + 16hr force-end |
| `onPresenceOffline` | v2 | 1-hour heartbeat threshold (was 4 hours) |
| `deleteUser` | v2 | Phone number lookup for Auth deletion |
| `adminCleanup` | v1 | One-time user fix utility with deleteOnly mode |
| `resolveUserOnLogin` | v2 | Normalized phone fallback matching |

---

## Firebase Paths Affected

| Path | Change |
|------|--------|
| `sessions/{id}` | New fields: `autoEndReason`, `autoEndSource` |
| `activityLogs/session_auto_ended_{sessionId}` | Deterministic doc ID (was random) |
| `presence/{eid}/{uid}` | `signalLostAt` written on all signal_lost transitions |
| `dailySummaries` | Client no longer writes (Cloud Functions only) |
| `deviceSessions/{uid}` | Empty/null token no longer triggers forced signout |

---

## Key Architecture Decisions

1. **Direct photo upload over offline queue**: The offline queue's batch write to `dailySummaries` was the root cause of all upload failures. Moved to direct upload path matching the chat camera (which always worked). Cloud Functions handle `dailySummaries` server-side.

2. **Deterministic activity log IDs**: All three sources of session-end logs (Dart handler, Kotlin native service, Cloud Function trigger) now use the same document ID `session_auto_ended_{sessionId}`. This prevents duplicate timeline entries via Firestore's natural idempotency.

3. **Auth user deletion by phone**: Firestore user docs have random IDs (not Firebase Auth UIDs) for pre-created users. The `deleteUser` Cloud Function looks up the Auth user by phone number when UID-based deletion fails.

4. **16-hour session cap**: Both client-side (analytics display) and server-side (sweeper force-end). Sessions exceeding 16 hours are always data errors from killed services that weren't caught by earlier safety nets.

5. **Single-device enforcement tolerance**: When RTDB device session token is null/empty (cleared by `onDisconnect` after app kill), the restarting app reclaims the session instead of forcing signout. Only sign out when a genuinely different device's token is detected.
