# Analytics & Live Dashboard

## Overview

The admin sees two real-time views:
1. **Dashboard** — Live employee cards with status, location, and session stats
2. **Analytics** — Historical activity, sessions, photos, and summary stats by date range

Both combine data from **Firestore** (persisted) and **RTDB** (live).

---

## Live Dashboard

### Architecture

```
RTDB Streams (real-time)          Firestore (today's completed data)
        |                                    |
        v                                    v
DashboardProvider ----merges----> getEmployeeStats()
        |                                    |
        v                                    v
  dashboard_screen.dart          employee_detail_screen.dart
```

### Data Sources

| Source | Path | Data | Update Frequency |
|--------|------|------|-----------------|
| Presence | `presence/{eid}` | status, lastSeen, sessionId | Every 25 min (heartbeat) |
| Live Location | `liveLocations/{eid}` | lat, lng, address, accuracy | Every 20s-5min (adaptive poll) |
| Active Stats | `activeStats/{eid}` | distance, duration, photos, tasks, sessionStartTimeMs | Every accepted poll |
| Daily Summaries | Firestore `dailySummaries` | Completed session totals for today | On session end |

### Employee Status Resolution

`DashboardProvider.getEmployeeStatus(userId)` determines badge color:

```
1. If RTDB presence.status == 'signal_lost' or 'location_lost'
   → signal_lost (yellow badge)

2. If RTDB presence.status == 'active':
   a. If liveLocation updated within 25 min → active (green badge)
   b. If heartbeat within 35 min → active (green badge)
   c. If BOTH liveLocation AND heartbeat are stale → signal_lost (yellow badge)

3. If RTDB presence.status == 'break':
   a. If heartbeat within 35 min → break
   b. If heartbeat stale → signal_lost

4. Default → offline (grey badge)
```

### Dashboard Screen

**Overview Section:**
- Active count (with animated pulse dot)
- Offline count

**Employee Cards:**
- Profile image, name
- Status badge (Active / Offline / Signal Lost)
- Location name (reverse geocoded via GeocodingCache)
- Stats: Duration (HH:MM), Distance (km), Photos today

**Filters:**
- Search by name or address
- Status filter chips: Active, Offline, Signal Lost

### Employee Detail Screen

Shows when admin taps an employee card:

- **Status banner** — Active / Signal Lost with description
- **Session stats** — Duration (HH:MM:SS with live timer), Distance (km)
- **Action buttons** — Assign Task, View Photos
- **Photos section** — Recent captured photos
- **Live Activity Feed** — Last 24 hours of activity (sessions, locations, photos)

**Live Timer:** 1-second refresh updates session duration display in real-time.

---

## Analytics System

### Architecture

```
Period Selection (Today / Week / Month / Custom)
        |
        v
AnalyticsProvider.loadAnalytics()
        |
        +---> Fetch employees (non-admin) from Firestore
        +---> Stream dailySummaries by enterprise + date range
        +---> Stream activityLogs by enterprise
        +---> Stream activeStats from RTDB (live sessions)
        +---> Load actual photo counts from photos collection
        |
        v
   _recomputeTotals()
        |
        +---> Sum completed session data (from dailySummaries)
        +---> Add live session data (from RTDB activeStats)
        +---> No double-counting: summaries only written on session end
        |
        v
  analytics_screen.dart
        |
        +---> Enterprise summary (total hours, distance, photos, tasks)
        +---> Employee list sorted by duration
        +---> Tap employee → EmployeeActivityScreen
```

### Period Options

| Period | Date Range |
|--------|-----------|
| Today | Midnight to now |
| This Week | Monday midnight to now |
| This Month | 1st of month midnight to now |
| Custom | User-selected start/end dates |

### Employee Stats Computation

`AnalyticsProvider.getEmployeeStats(employeeId)`:

```
Completed data (Firestore dailySummaries):
  + totalDuration, totalDistance, photosCount, tasksCompleted

Live data (RTDB activeStats, if session is active):
  + Live duration = now - sessionStartTimeMs
  + Live distance, photos, tasks

= Merged total (no overlap because summaries are written only after session ends)
```

### Employee Activity Screen

Shows detailed timeline for a single employee over a date range.

**Sections:**
1. **Summary Card** — Duration, Distance, Photos
2. **Captures** — Photo gallery (expandable grid)
3. **Activity Timeline** — Chronological feed of events

**Data Loading via `AdminActivityFeedService.loadRangeFeed()`:**

```
Step 1: Load sessions via SessionQueryHelper (5 fallback layers):
        1. Employee-scoped query with date range
        2. Employee-scoped unfiltered, filter in memory
        3. Enterprise-wide query with date range
        4. Enterprise-wide unfiltered, filter in memory
        5. DailySummary-based session discovery (last resort)
        Results cached via QueryCache (TTL: 2 min)

Step 2: Load activity logs (parallel queries)
        - By employee IDs + date range
        - By session IDs + date range
        Fallback: unfiltered queries

Step 3: Load photos (parallel queries)
        - By employee IDs
        - By session IDs
        Fallback: unfiltered queries

Step 4: Load session locations (from sessions/*/locations subcollection)

Step 5: Extract photos from activity log metadata (payload.photoUrl)

Step 6: Enterprise-wide photo fallback (query by enterpriseId, filter client-side)

Step 7: Merge, deduplicate, sort by timestamp
```

**Location Display Thinning:**
- Location entries are thinned to one per 20-minute interval (`_locationDisplayInterval`) to avoid flooding the feed

**Deduplication:**
- Location logs: Grouped by minute-bucket + coordinates + detail + session ID
- Other logs: Deduplicated by document ID
- Synthetic session boundary logs added if missing (session_started, session_ended)

### Daily Summary Aggregator (Cloud Function)

**Schedule:** Runs daily at **23:59 IST** (18:29 UTC)
**Region:** asia-south1

**Process:**
1. Calculates today's date boundaries in IST
2. For each enterprise, queries completed sessions for the day
3. Aggregates per employee: duration, distance, photos, tasks, locations visited
4. Writes `dailySummaries` documents (overwrites client-written data for accuracy)
5. Doc ID format: `{employeeId}_{YYYY-MM-DD}`

**Note:** Client also writes dailySummaries immediately after session end for instant analytics updates. The Cloud Function overwrites these at end of day to ensure accuracy.

---

## Firestore Data Structure

### sessions
```
sessions/{sessionId}
├── enterpriseId: string
├── employeeId: string
├── startTime: timestamp
├── endTime: timestamp?
├── status: "active" | "completed" | "auto_ended"
├── totalDuration: int (seconds)
├── totalDistance: double (km)
├── photosCount: int
├── tasksCompleted: int
├── notes: string?
├── autoEndReason: string?
├── autoEndSource: string?
├── locationLostAt: timestamp?
├── createdAt: timestamp
│
└── locations/{locationId}
    ├── latitude: double
    ├── longitude: double
    ├── address: string
    ├── timestamp: timestamp
    ├── type: "check_in" | "visit" | "check_out" | "location_update" | "auto_end"
    └── title: string
```

### photos
```
photos/{photoId}
├── clientRequestId: string?
├── enterpriseId: string
├── employeeId: string
├── sessionId: string
├── imageUrl: string
├── thumbnailUrl: string
├── timestamp: timestamp
├── location: string
├── latitude: double
├── longitude: double
├── geotagData: { date, time, coordinates }
├── category: string? ("distributor" | "farmer")
├── customerType: string? ("new" | "old")
├── customerName: string?
├── customerPhone: string?
├── notes: string?
├── groupId: string?
├── hasFollowUp: bool
└── createdAt: timestamp
```

### users
```
users/{authUid}
├── name: string
├── phone: string
├── email: string?
├── roles: ["admin"] | ["team_lead"] | ["employee"]
├── activeRole: "admin" | "team_lead" | "employee"
├── enterpriseId: string
├── groupId: string?
├── migratedFrom: string?
├── profileImageUrl: string?
├── fcmToken: string?
├── createdAt: timestamp
├── updatedAt: timestamp
│
└── notifications/{notificationId}
    ├── title: string
    ├── body: string
    ├── type: "task" | "location" | "system" | "report" | "alert"
    ├── isRead: bool
    ├── data: { action, taskId, sessionId, ... }
    └── createdAt: timestamp
```

### activityLogs
```
activityLogs/{logId}
├── enterpriseId: string
├── employeeId: string
├── sessionId: string?
├── orgId: string?
├── type: "location_update" | "photo_captured" | "session_start" | "session_end"
│         | "session_auto_ended" | "task_started" | "task_completed"
├── title: string
├── detail: string
├── timestamp: timestamp
├── date: string? (YYYY-MM-DD)
├── metadata: { reason, source, ... }?
└── payload: { lat, lng, address, photoUrl, ... }?
```

### dailySummaries
```
dailySummaries/{employeeId}_{YYYY-MM-DD}
├── enterpriseId: string
├── employeeId: string
├── date: timestamp (midnight)
├── totalDuration: int (seconds)
├── totalDistance: double (km)
├── photosCount: int
├── tasksCompleted: int
├── locationsVisited: [string]
├── sessionIds: [string]
└── isOffDuty: bool
```

### tasks
```
tasks/{taskId}
├── enterpriseId: string
├── title: string
├── description: string?
├── type: "task" | "followup"
├── priority: "high" | "medium" | "low"
├── status: "pending" | "completed"
├── assignedTo: string (userId)
├── assignedBy: string (userId)
├── assignedByName: string?
├── assignedToName: string?
├── groupId: string?
├── dueDate: timestamp
├── contactType: string?
├── contactPhone: string?
├── completedAt: timestamp?
├── sendNotification: bool
├── createdAt: timestamp
└── updatedAt: timestamp
```

### groups (teams)
```
groups/{groupId}
├── enterpriseId: string
├── name: string
├── leadIds: [string]
├── leadId: string (deprecated, backward compat)
├── color: string (hex)
├── memberIds: [string]
├── createdAt: timestamp
└── updatedAt: timestamp
```

### chatGroups
```
chatGroups/{groupId}
├── enterpriseId: string
├── name: string
├── description: string
├── linkedGroupId: string?
├── createdBy: string (userId)
├── memberIds: [string]
├── mode: "open" | "broadcast"
├── lastMessage: { type, text, senderName, imageUrl }?
├── lastMessageAt: timestamp?
├── lastReadAt: { userId: timestamp }
├── createdAt: timestamp
├── updatedAt: timestamp
│
└── messages/{messageId}
    ├── clientRequestId: string?
    ├── senderId: string
    ├── senderName: string
    ├── type: "text" | "image" | "location"
    ├── text: string?
    ├── imageUrl: string?
    ├── thumbnailUrl: string?
    ├── latitude: double?
    ├── longitude: double?
    ├── address: string?
    ├── caption: string?
    ├── createdAt: timestamp
    ├── isDeleted: bool
    ├── replyToId: string?
    ├── replyToSenderName: string?
    ├── replyToText: string?
    ├── replyToType: string?
    └── replyToImageUrl: string?
```

## RTDB Structure

```
presence/{enterpriseId}/{userId}
├── status: "active" | "break" | "offline" | "signal_lost"
├── lastSeen: serverTimestamp
├── currentSessionId: string?
└── signalLostAt: serverTimestamp?

liveLocations/{enterpriseId}/{userId}
├── latitude: number
├── longitude: number
├── address: string
├── updatedAt: serverTimestamp
└── accuracy: number

activeStats/{enterpriseId}/{userId}
├── sessionDuration: number (seconds)
├── distance: number (km)
├── photosToday: number
├── tasksToday: number
└── sessionStartTimeMs: number

sessionHeartbeat/{enterpriseId}/{userId}
├── sessionId: string
└── lastSeen: serverTimestamp

deviceSessions/{userId}
└── token: string (single-device enforcement)
```

## Key Constants

| Constant | Value | Location |
|----------|-------|---------|
| Foreground service repeat | 60s | tracking_foreground_service.dart |
| Poll interval (STILL) | 5 min | tracking_task_handler.dart |
| Poll interval (WALKING) | 60s | tracking_task_handler.dart |
| Poll interval (VEHICLE) | 20s | tracking_task_handler.dart |
| Heartbeat interval | 25 min | tracking_task_handler.dart |
| Buffer flush threshold | 20 locations | sync_manager.dart |
| Periodic flush interval | 20 min | sync_manager.dart |
| GPS accuracy filter | <= 100m | tracking_task_handler.dart |
| Movement filter | >= 15m | tracking_task_handler.dart |
| Speed spike filter | <= 100 m/s | tracking_task_handler.dart |
| Live location grace | 25 min | dashboard_provider.dart |
| Heartbeat stale grace | 35 min | dashboard_provider.dart |
| Signal lost max age | 15 min | sweep_signal_lost_sessions.ts |
| Stale heartbeat max age | 15 min | sweep_signal_lost_sessions.ts |
| Max session duration | 16 hours | sweep_signal_lost_sessions.ts |
| Presence offline heartbeat stale | 1 hour | on_presence_offline.ts |
| Daily summary schedule | 23:59 IST | daily_summary_aggregator.ts |
| Sweep signal lost schedule | Every 10 min | sweep_signal_lost_sessions.ts |
| Sanitize active stats schedule | Every 10 min | sanitize_active_stats.ts |
| Export cleanup schedule | Saturday 02:00 IST | cleanup_old_exports.ts |
| Analytics integrity check | Every 6 hours | check_analytics_integrity.ts |
| Location display thinning | 20 min | admin_activity_feed_service.dart |
| Query cache TTL | 2 min | query_cache.dart |
| Session query fallback layers | 5 | session_query_helper.dart |
| Geocoding timeout | 5s | sync_manager.dart, tracking_task_handler.dart |
| Geocoding cache precision | ~11m (4 decimal) | geocoding_cache.dart |
