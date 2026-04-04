# Izumi Backend - How It Works

**Last Updated:** April 2026
**Stack:** Firebase (Cloud Functions v2, Firestore, Realtime DB, Cloud Storage, FCM)
**Runtime:** Node.js 22, TypeScript
**Region:** asia-south1 (India)
**Project ID:** izumi-6e087

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Cloud Functions](#2-cloud-functions)
   - [Auth Triggers](#21-auth-triggers)
   - [Session Triggers](#22-session-triggers)
   - [Photo Triggers](#23-photo-triggers)
   - [Task Triggers](#24-task-triggers)
   - [Chat Triggers](#25-chat-triggers)
   - [Force Logout](#26-force-logout)
   - [Scheduled Jobs (Cron)](#27-scheduled-jobs-cron)
   - [Callable Functions (HTTPS)](#28-callable-functions-https)
3. [Database Schema](#3-database-schema)
   - [Firestore Collections](#31-firestore-collections)
   - [Realtime Database Nodes](#32-realtime-database-nodes)
4. [Cloud Storage Structure](#4-cloud-storage-structure)
5. [Security Rules](#5-security-rules)
6. [Firestore Indexes](#6-firestore-indexes)
7. [Authentication & Custom Claims](#7-authentication--custom-claims)
8. [Notification System](#8-notification-system)
9. [Utility Modules](#9-utility-modules)
10. [Data Flow Examples](#10-data-flow-examples)
11. [Frontend Service Layer](#11-frontend-service-layer)
12. [Deployment](#12-deployment)

---

## 1. Architecture Overview

```
                    +------------------+
                    |   Flutter App    |
                    +--------+---------+
                             |
           +-----------------+-----------------+
           |                 |                 |
     +-----v-----+   +------v------+   +------v------+
     | Firestore  |   | Realtime DB |   |   Storage   |
     +-----+------+   +------+------+   +------+------+
           |                 |                 |
           +--------+--------+---------+-------+
                    |                  |
              +-----v------+   +------v-------+
              |   Cloud     |   |  Scheduled   |
              |  Functions  |   |    Jobs      |
              |  (Triggers) |   |   (Cron)     |
              +-----+-------+   +------+-------+
                    |                  |
              +-----v------------------v-------+
              |           FCM Push             |
              |        Notifications           |
              +--------------------------------+
```

**How it works:** The Flutter app reads/writes directly to Firestore, RTDB, and Storage. Cloud Functions react to those writes (triggers) to run server-side logic -- notifications, calculations, cleanup. Scheduled jobs handle periodic maintenance. All access is gated by security rules using Firebase Auth custom claims.

---

## 2. Cloud Functions

Entry point: `functions/src/index.ts` -- all functions exported from here.

### 2.1 Auth Triggers

#### `onUserCreate`
**File:** `functions/src/auth/on_user_create.ts`
**Trigger:** Firestore document created at `/users/{userId}`

What it does:
1. Reads `roles`, `activeRole`, `enterpriseId`, `groupId` from the new user doc
2. Sets Firebase Auth **custom claims** on the user (used by security rules)
3. Validates role values (`employee`, `team_lead`, `admin`)
4. If `migratedFrom` field exists, migrates tasks from old doc ID to new UID

---

### 2.2 Session Triggers

#### `onSessionStarted`
**File:** `functions/src/sessions/on_session_event.ts`
**Trigger:** Firestore document created at `/sessions/{sessionId}`

What it does:
1. Creates an activity log entry (`type: session_start`)
2. Looks up recipients (admin + team lead for employee's group)
3. Sends FCM push + in-app notification to recipients

#### `onSessionEnded`
**File:** `functions/src/sessions/on_session_event.ts`
**Trigger:** Firestore document updated -- `status` changed to `completed` or `auto_ended`

What it does:
1. Creates activity log (`type: session_end`)
2. Sends notifications to admin, team lead, and (for auto_end) the employee
3. Includes duration and distance in notification payload

#### `onSessionComplete`
**File:** `functions/src/sessions/on_session_complete.ts`
**Trigger:** Firestore document updated -- `status` changed to `completed`

What it does:
1. Reads all location docs from `/sessions/{sessionId}/locations`
2. Calculates **trusted distance** using Haversine formula with outlier filtering:
   - Rejects segments > 100 km
   - Rejects speeds > 120 km/h
3. Calculates total session duration
4. Gathers unique location names visited
5. Creates/updates `/dailySummaries/{employeeId}_{YYYY-MM-DD}`
6. All dates computed in IST (UTC+5:30)

#### `onPresenceOffline`
**File:** `functions/src/sessions/on_presence_offline.ts`
**Trigger:** RTDB node updated at `presence/{enterpriseId}/{userId}`

What it does: When user goes offline, removes entries from `activeStats`, `sessionHeartbeat`, and `liveLocations` in RTDB.

#### `onSessionLocationCreated`
**File:** `functions/src/sessions/on_session_location_created.ts`
**Trigger:** Firestore subcollection doc created at `/sessions/{sessionId}/locations/{locationId}`

What it does: Creates an activity log (`type: location_update`) with enriched location data.

---

### 2.3 Photo Triggers

#### `onPhotoUpload`
**File:** `functions/src/photos/on_photo_upload.ts`
**Trigger:** Cloud Storage object finalized in `enterprises/{enterpriseId}/photos/`

What it does:
1. Skips non-images and existing thumbnails (`*_thumb.jpg`)
2. Downloads original image to `/tmp`
3. Generates 200x200 thumbnail using `sharp` (quality: 80)
4. Uploads thumbnail back to Storage
5. Updates Firestore photo doc with `thumbnailUrl`
6. Cleans up temp files

#### `onPhotoDocumentCreated`
**File:** `functions/src/photos/on_photo_document_created.ts`
**Trigger:** Firestore document created at `/photos/{photoId}`

What it does: Creates activity log (`type: photo_captured`).

---

### 2.4 Task Triggers

#### `onTaskAssigned`
**File:** `functions/src/tasks/on_task_assigned.ts`
**Trigger:** Firestore document created at `/tasks/{taskId}`

What it does:
1. Reads assigner's name for personalization
2. Sends FCM + in-app notification to assigned employee (with priority level)
3. Creates activity log (`type: task_started`)
4. Respects `sendNotification` flag on task doc

#### `onTaskCompleted`
**File:** `functions/src/tasks/on_task_completed.ts`
**Trigger:** Firestore document updated -- `status` changed to `completed`

What it does:
1. Creates activity log (`type: task_completed`)
2. Sends notification to admin + team lead

---

### 2.5 Chat Triggers

#### `onChatMessage`
**File:** `functions/src/chat/on_chat_message.ts`
**Trigger:** Firestore subcollection doc created at `/chatGroups/{groupId}/messages/{messageId}`

What it does:
1. Builds preview text based on message type (text/image/location)
2. Updates parent `/chatGroups/{groupId}` doc with `lastMessage` and `lastMessageAt`

#### `onGroupUpdated`
**File:** `functions/src/chat/on_group_updated.ts`
**Trigger:** Firestore document updated at `/chatGroups/{groupId}`

What it does: Creates activity log for group updates.

---

### 2.6 Force Logout

#### `onForceLogoutCreated`
**File:** `functions/src/force_logout/on_force_logout_created.ts`
**Trigger:** Firestore document written at `/forceLogout/{userId}`

What it does:
1. Reads old FCM token from the document
2. Sends **data-only** FCM message (`type: "force_logout"`) -- silent, no visible notification
3. Auto-deletes the trigger document after sending
4. Handles expired tokens gracefully

---

### 2.7 Scheduled Jobs (Cron)

All run in asia-south1 with 300s timeout.

| Job | Schedule | What It Does |
|-----|----------|--------------|
| `dailySummaryAggregator` | `29 18 * * *` (23:59 IST) | End-of-day reconciliation. Queries all completed sessions for today, aggregates per-employee stats, writes/overwrites `dailySummaries` docs. Uses 450-doc batches. 512MiB memory. |
| `sweepSignalLostSessions` | `*/30 * * * *` (every 30 min) | Auto-ends stale sessions. Checks RTDB presence, heartbeat, and location staleness. Auto-ends if: signal lost >60 min, no heartbeat >60 min, or session >16 hours. Cleans up RTDB nodes. Notifies employee. |
| `checkAnalyticsIntegrity` | `0 */6 * * *` (every 6 hours) | Audits data consistency. Verifies activity logs exist for sessions, photos, tasks. Checks active sessions have recent location updates (30min grace). Logs inconsistencies. |
| `sanitizeActiveStats` | Periodic | Removes stale entries from `activeStats` in RTDB. |
| `cleanupOldExports` | Periodic | Removes old export files from Cloud Storage. |

---

### 2.8 Callable Functions (HTTPS)

All require authentication.

#### `resolveUserOnLogin`
**File:** `functions/src/callable/resolve_user_on_login.ts`
**Purpose:** Handles the pre-created user migration flow on first login.

Flow:
1. Check if `/users/{uid}` already exists (already migrated) -- return it
2. If not, query for pre-created doc matching phone number
3. If found, migrate everything from old ID to new UID:
   - Create new user doc at `/users/{uid}`, delete old one
   - Set custom claims
   - Update `assignedTo` in all related tasks
   - Update `memberIds`/`leadIds` in groups
   - Update `memberIds`/`lastReadAt`/`createdBy` in chat groups
   - Update `employeeId` in photos
4. Return user data (or null if genuinely new user)

#### `exportReport`
**File:** `functions/src/callable/export_report.ts`
**Authorization:** Admin only

Generates CSV exports for: sessions, tasks, photos, attendance, summary, customers. Filters by date range and enterprise. Uploads CSV to Storage, returns download URL.

#### `ensureClaims`
**File:** `functions/src/callable/ensure_claims.ts`
**Authorization:** Admin only

Sets/refreshes custom claims for a target user (roles, activeRole, enterpriseId, groupId).

#### `updateUserRole`
**File:** `functions/src/callable/update_user_role.ts`

Changes a user's `activeRole` within their allowed `roles` array. Updates both Firestore doc and Auth custom claims.

#### `deleteUser`
**File:** `functions/src/callable/delete_user.ts`
**Authorization:** Admin only

Soft or hard deletes a user and their related data.

#### `adminCleanup`
**File:** `functions/src/callable/admin_cleanup.ts`
**Authorization:** Admin only

General-purpose admin maintenance operations.

#### `syncLinkedChatGroups`
**File:** `functions/src/callable/sync_linked_chat_groups.ts`
**Authorization:** Admin only

Syncs member lists between groups and their linked chat groups.

#### Migration Callables
- `migrateOrphanedTasks` -- reattach orphaned tasks
- `migrateGroupMemberIds` -- update group member references
- `migrateHistoricalAnalytics` -- backfill activity logs
- `migrateHistoricalPhotos` -- bulk update photo references

---

## 3. Database Schema

### 3.1 Firestore Collections

#### `/users/{userId}`
User profile and settings.
```
{
  name, phone, email,
  role, roles[], activeRole,
  enterpriseId, groupId,
  fcmToken, profileImageUrl,
  isActive, createdAt, updatedAt
}
```
**Subcollection:** `/users/{userId}/notifications` -- in-app notifications

#### `/sessions/{sessionId}`
Field work sessions.
```
{
  employeeId, enterpriseId, groupId,
  status: "active" | "completed" | "auto_ended",
  startTime, endTime,
  startLocation: { lat, lng, name },
  endLocation: { lat, lng, name },
  totalDistance, totalDuration,
  notes, autoEndReason
}
```
**Subcollection:** `/sessions/{sessionId}/locations/{locationId}` -- GPS breadcrumbs

#### `/photos/{photoId}`
Geotagged field photos.
```
{
  employeeId, enterpriseId, sessionId,
  imageUrl, thumbnailUrl,
  location: { lat, lng, name },
  category, notes, timestamp
}
```

#### `/tasks/{taskId}`
Assigned tasks and follow-ups.
```
{
  title, description, priority,
  assignedTo, assignedBy,
  enterpriseId, groupId,
  status: "pending" | "in_progress" | "completed",
  dueDate, completedAt, createdAt,
  sendNotification, isFollowUp
}
```

#### `/groups/{groupId}`
Teams/zones.
```
{
  name, enterpriseId,
  memberIds[], leadId, leadIds[],
  createdAt, updatedAt
}
```

#### `/dailySummaries/{employeeId}_{YYYY-MM-DD}`
Aggregated daily stats.
```
{
  employeeId, enterpriseId, date,
  totalDistance, totalDuration,
  sessionCount, locationsVisited[],
  photosCount, tasksCompleted
}
```

#### `/chatGroups/{groupId}`
Chat rooms.
```
{
  name, enterpriseId, type,
  memberIds[], linkedGroupId,
  lastMessage, lastMessageAt,
  createdBy, createdAt, updatedAt
}
```
**Subcollection:** `/chatGroups/{groupId}/messages/{messageId}`

#### `/activityLogs/{logId}`
Audit trail for all major actions.
```
{
  employeeId, enterpriseId, sessionId,
  type: "session_start" | "session_end" | "location_update" |
        "photo_captured" | "task_started" | "task_completed",
  title, detail, payload: {},
  date (YYYY-MM-DD in IST), timestamp
}
```

#### `/forceLogout/{userId}`
Single-device enforcement trigger (auto-deleted after processing).

---

### 3.2 Realtime Database Nodes

| Node | Structure | Purpose |
|------|-----------|---------|
| `presence/{enterpriseId}/{userId}` | `{ status, signalLostAt, currentSessionId, lastSeen }` | Online/offline presence |
| `liveLocations/{enterpriseId}/{userId}` | `{ lat, lng, updatedAt }` | Real-time map tracking (admin/TL only) |
| `activeStats/{enterpriseId}/{userId}` | `{ ... }` | Live activity metrics |
| `sessionHeartbeat/{enterpriseId}/{userId}` | `{ lastSeen }` | Periodic heartbeat for staleness detection |
| `deviceSessions/{userId}` | `{ deviceId, ... }` | Multi-device detection |

---

## 4. Cloud Storage Structure

```
enterprises/
  {enterpriseId}/
    photos/{userId}/          -- field photos (10MB max, images only)
      {photo}.jpg
      {photo}_thumb.jpg       -- auto-generated thumbnail
    profiles/{userId}/        -- profile avatars
    chat/{groupId}/           -- chat images (10MB max)
    exports/                  -- CSV/report exports (admin only)
```

---

## 5. Security Rules

### Firestore Rules (`firestore.rules`)

Role-based access using custom claims:

| Collection | Who Can Read | Who Can Write |
|------------|-------------|---------------|
| `users` | Self, Admin, Team Lead (same enterprise) | Self (update), Admin (create/delete) |
| `sessions` | Owner, Admin, Team Lead (same group) | Owner (create/update), never delete |
| `photos` | Owner, Admin, Team Lead (same group) | Owner (CRUD), Admin (delete) |
| `tasks` | Assignee, Admin, Team Lead | Admin/TL (create), Assignee (update status) |
| `groups` | All in enterprise | Admin only |
| `dailySummaries` | Owner, Admin, Team Lead (same group) | Cloud Functions only |
| `chatGroups` | Members, Admin | Admin (CRUD), Members (update lastReadAt) |
| `activityLogs` | Owner, Admin, Team Lead (same group) | Owner (create only) |

Key helper functions in rules:
- `isAdmin()` / `isTeamLead()` / `isEmployee()` -- check `request.auth.token` claims
- `belongsToEnterprise(id)` -- enterprise scoping
- `isInMyGroup(userId)` -- team lead checks group membership

### RTDB Rules (`database.rules.json`)

| Path | Read | Write |
|------|------|-------|
| `presence/{eid}/{uid}` | Enterprise members | User only |
| `liveLocations/{eid}/{uid}` | Admin/Team Lead | User only |
| `activeStats/{eid}/{uid}` | Enterprise members | User only |
| `sessionHeartbeat/{eid}/{uid}` | Enterprise members | User only |
| `deviceSessions/{uid}` | User only | User only |

### Storage Rules (`storage.rules`)

- Photos: user uploads own, admin can read all in enterprise
- Profiles: user uploads own, all in enterprise can read
- Chat: all enterprise members can upload/read
- Exports: admin read only, Cloud Functions write

---

## 6. Firestore Indexes

Key composite indexes (`firestore.indexes.json`):

**Sessions:**
- `(employeeId, status, startTime DESC)` -- active sessions by user
- `(enterpriseId, startTime DESC)` -- admin session list
- `(employeeId, startTime DESC)` -- employee history

**Activity Logs:**
- `(employeeId, timestamp DESC)` -- employee activity feed
- `(enterpriseId, timestamp DESC)` -- admin activity feed
- `(employeeId, type, timestamp DESC)` -- filtered by type
- `(sessionId, timestamp DESC)` -- session timeline

**Photos:**
- `(employeeId, timestamp DESC)`
- `(enterpriseId, category, timestamp)`
- `(sessionId, timestamp DESC)`

**Tasks:**
- `(assignedTo, createdAt DESC)`
- `(enterpriseId, createdAt DESC)`

**Daily Summaries:**
- `(employeeId, date DESC)`
- `(enterpriseId, date DESC)`

**Chat Groups:**
- `(enterpriseId, memberIds CONTAINS, updatedAt DESC)`

**Users:**
- `(enterpriseId, role)`
- `(phone, enterpriseId)`

---

## 7. Authentication & Custom Claims

**Auth methods:**
- Employee/Team Lead: Phone number + OTP
- Admin: Email + Password

**Custom claims structure** (set on Firebase Auth token):
```json
{
  "roles": ["employee", "team_lead", "admin"],
  "activeRole": "team_lead",
  "role": "team_lead",           // backward compat
  "enterpriseId": "enterprise_123",
  "groupId": "group_456"          // optional
}
```

**Who sets claims:**
- `onUserCreate` trigger -- when user doc is first created
- `resolveUserOnLogin` callable -- during pre-created user migration
- `ensureClaims` callable -- manual admin refresh

**Convention:** Admin's UID === their `enterpriseId`. This is how the system identifies the enterprise owner.

---

## 8. Notification System

**Dual-channel approach:**

1. **In-app:** Write to `/users/{userId}/notifications` (Firestore doc)
2. **Push:** Send via FCM (`admin.messaging().send()`)

**Implementation:** `functions/src/utils/send_notification.ts`

Behavior:
- Always writes Firestore notification doc (persists even if push fails)
- Sends FCM push if user has valid `fcmToken`
- Auto-cleans invalid FCM tokens on delivery failure
- Separate Android notification channels for tasks vs general
- Data-only FCM for system events (force logout -- no visible notification)

**Recipient lookup:** `functions/src/utils/lookup_recipients.ts`
- Finds admin (= enterpriseId) and team lead (query groups for leadId/leadIds)
- Deduplicates, excludes the triggering employee

---

## 9. Utility Modules

| Module | File | Purpose |
|--------|------|---------|
| `sendNotification` | `functions/src/utils/send_notification.ts` | FCM + in-app notification delivery |
| `lookupRecipients` | `functions/src/utils/lookup_recipients.ts` | Find admin + team lead for an employee |
| `upsertActivityLog` | `functions/src/utils/activity_log.ts` | Create/update activity log docs with IST dates. Uses deterministic IDs for idempotency on retries. |
| `enrichLocationUpdate` | `functions/src/logs/enrich_location_update.ts` | Enrich location logs with address metadata |

---

## 10. Data Flow Examples

### Employee Starts a Session
```
1. App writes session doc to /sessions/{id} (status: "active")
2. App sets RTDB nodes: presence, activeStats, sessionHeartbeat, liveLocations
3. onSessionStarted trigger fires:
   - Creates activityLog (type: session_start)
   - lookupRecipients -> finds admin + team lead
   - sendNotification -> FCM push + Firestore notification
4. App begins periodic location writes to /sessions/{id}/locations/
5. Each location write triggers onSessionLocationCreated -> activityLog
```

### Employee Ends a Session
```
1. App updates session doc: status -> "completed", sets endTime
2. onSessionEnded trigger fires:
   - Creates activityLog (type: session_end)
   - Notifies admin + team lead
3. onSessionComplete trigger fires:
   - Reads all /sessions/{id}/locations/ docs
   - Calculates trusted distance (Haversine + outlier filtering)
   - Creates/updates dailySummary doc
4. App clears RTDB nodes
```

### Signal Lost Auto-End
```
1. sweepSignalLostSessions runs every 30 min
2. Checks RTDB: presence.lastSeen, sessionHeartbeat.lastSeen, liveLocations.updatedAt
3. If all stale >60 min OR session >16 hours:
   - Updates session: status -> "auto_ended", reason -> "signal_lost"
   - Cleans up RTDB nodes
   - Notifies employee
   - Triggers onSessionEnded + onSessionComplete
```

### Photo Upload
```
1. App uploads image to Storage: enterprises/{eid}/photos/{uid}/{file}
2. App creates Firestore doc at /photos/{id}
3. onPhotoUpload trigger (Storage):
   - Downloads original, generates 200x200 thumbnail via sharp
   - Uploads thumbnail, updates Firestore doc with thumbnailUrl
4. onPhotoDocumentCreated trigger:
   - Creates activityLog (type: photo_captured)
```

### Task Assignment
```
1. Admin creates doc at /tasks/{id}
2. onTaskAssigned trigger:
   - Reads assigner name
   - Sends FCM + in-app notification to assignee (with priority)
   - Creates activityLog (type: task_started)
3. Employee updates task status -> "completed"
4. onTaskCompleted trigger:
   - Creates activityLog (type: task_completed)
   - Notifies admin + team lead
```

### Pre-Created User Login (Migration)
```
1. Admin pre-creates user doc at /users/{phone-based-id}
2. Employee installs app, logs in with phone -> gets Firebase Auth UID
3. App calls resolveUserOnLogin callable
4. Function queries Firestore for doc matching phone number
5. If found, migrates:
   - Creates /users/{uid}, deletes /users/{old-id}
   - Updates tasks, groups, chatGroups, photos references
   - Sets custom claims
6. Returns user data to app
```

---

## 11. Frontend Service Layer

**Location:** `lib/services/`

| Service | What It Does |
|---------|-------------|
| `firestore_service.dart` | All Firestore CRUD and stream operations |
| `realtime_db_service.dart` | RTDB reads/writes for presence, live locations, heartbeat |
| `storage_service.dart` | Cloud Storage upload/download |
| `auth_service.dart` | Firebase Auth, token management, role routing |
| `notification_service.dart` | Local notification handling, FCM token management |
| `location_service.dart` | GPS tracking, background location |
| `image_processing_service.dart` | Camera capture, watermarking, upload |
| `connectivity_monitor.dart` | Network state, presence heartbeat |
| `admin_activity_feed_service.dart` | Activity log queries for admin dashboard |

---

## 12. Deployment

```bash
# Build TypeScript
cd functions && npm run build

# Deploy everything
firebase deploy

# Deploy only functions
firebase deploy --only functions

# Deploy only rules
firebase deploy --only firestore:rules,database,storage

# View logs
firebase functions:log
```

**Emulator ports (local dev):**
- Functions: 5001
- Firestore: 8080
- Auth: 9099
- RTDB: 9000

---

## Key Design Decisions

| Decision | Why |
|----------|-----|
| IST hardcoded for all dates | All users are in India |
| Admin UID = enterpriseId | Simplifies enterprise ownership lookup |
| Dual notification (Firestore + FCM) | Ensures notifications persist even if push fails |
| Deterministic activity log IDs | Prevents duplicates on Cloud Function retries |
| Haversine with outlier filtering | GPS noise/teleportation creates fake distance |
| Multi-signal staleness (presence + heartbeat + location) | No single signal is reliable enough alone |
| Data-only FCM for force logout | Silent action, no user-visible notification needed |
| 450-doc batch size | Stay under Firestore 500 write limit |
| 16-hour hard session cutoff | Prevents infinite ghost sessions |
