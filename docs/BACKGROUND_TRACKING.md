# Background Tracking System

## Overview

Izumi uses a foreground service to continuously track employee location during active field sessions. The system is designed for reliability on aggressive Android OEMs (Samsung, Xiaomi, etc.) that kill background processes.

## Architecture

```
Employee taps "Start Session"
        |
        v
SessionProvider.startSession()
        |
        +---> Create Firestore session doc (status: active)
        +---> Set RTDB presence (status: active)
        +---> Setup onDisconnect (auto signal_lost)
        +---> Start foreground service (TrackingForegroundService)
        +---> Start native SessionTaskGuard (Android)
        |
        v
SessionTrackingTaskHandler.onStart()
        |
        +---> Load context from shared storage
        +---> Restore session state from SQLite (crash recovery)
        +---> Start SyncManager (buffer + flush)
        +---> Start activity recognition
        +---> Send initial heartbeat to RTDB
        +---> First GPS poll
        |
        v
    [Tracking Loop]
        |
        +---> onRepeatEvent (every 60s) --> _pollLocation()
        +---> Activity recognition --> adjust poll interval
        +---> Heartbeat timer (every 15 min) --> RTDB presence + session validation
        +---> SyncManager flush (every 20 min or 20 locations)
        +---> 7 PM IST reminder (one-shot timer, UTC-computed)
```

## Components

### 1. Foreground Service (`tracking_foreground_service.dart`)

Manages the Android foreground service lifecycle.

**Configuration:**
- Repeat interval: **60 seconds**
- Auto-run on boot: **enabled**
- Auto-run on package replaced: **enabled**
- Wake lock: **enabled**
- WiFi lock: **enabled**
- Notification channel: `izumi_tracking`
- Service types: `location`, `dataSync`

**Key Methods:**
| Method | Purpose |
|--------|---------|
| `startTracking()` | Start service with session context. If already running, sends refresh_context instead of restarting (avoids onDestroy race) |
| `ensureTrackingRunning()` | Idempotent — refreshes context if running, starts if not |
| `stopTracking()` | Stops service, optionally clears stored context |
| `flushNow()` / `finalFlush()` | Commands to flush location buffer to Firestore |
| `requestLocationSnapshot()` | Manual GPS poll |
| `requestImmediateHeartbeat()` | Force heartbeat to RTDB |

### 2. Task Handler (`tracking_task_handler.dart`)

The core background task running inside the foreground service.

**Lifecycle:**
| Callback | When | What it does |
|----------|------|-------------|
| `onStart()` | Service starts | Init Firebase, load context, start activity recognition, first heartbeat + poll |
| `onRepeatEvent()` | Every 60s | Triggers `_pollLocation()` |
| `onReceiveData()` | Main app sends command | Handles: refresh_context, heartbeat, poll_now, flush_now, final_flush |
| `onDestroy()` | Service killed | Auto-ends session if not a normal end |

**Adaptive Polling:**

The poll interval adjusts based on detected activity:

| Activity | Interval | GPS Accuracy |
|----------|----------|-------------|
| STILL | 5 minutes | Medium |
| WALKING / ON_FOOT / RUNNING | 60 seconds | Medium |
| IN_VEHICLE / ON_BICYCLE | 20 seconds | High |

Activity recognition uses `flutter_activity_recognition`. Defaults to WALKING after 30 seconds if no activity detected.

**Quality Filters:**

Every GPS fix is validated before acceptance:

| Filter | Threshold | Purpose |
|--------|-----------|---------|
| Accuracy | <= 40m | Reject poor GPS fixes |
| Movement | >= 30m | Discard stationary noise |
| Speed | <= 90 km/h | Reject impossible jumps |

STILL-mode fixes are accepted for position updates but their distance contribution is excluded to prevent jitter inflation.

**Heartbeat:**
- Sent every **15 minutes** to RTDB
- Updates `presence/{enterpriseId}/{employeeId}` with status and lastSeen
- Updates `sessionHeartbeat/{enterpriseId}/{employeeId}` with sessionId and lastSeen
- Each heartbeat also validates the Firestore session is still active (guards against stale foreground service)
- Used by dashboard and server sweep to detect stale/dead sessions

**7 PM IST Daily Reminder:**
- A one-shot timer scheduled on each service start fires at 19:00 IST (calculated in UTC to avoid device-local timezone drift)
- Sends a local push notification reminding the employee to end their session if still active

**onDestroy Behavior (FIX 6 — OEM Kill Recovery):**

`onDestroy` does **NOT** auto-end the session. It signals for recovery instead:

1. Checks if context was cleared (normal end) — skips entirely
2. Checks if session < 30 seconds old (likely a service restart) — skips
3. Sets RTDB `presence.status` to `signal_lost`
4. Persists a `needs_resume` hint (with timestamp) to SharedPreferences

On next app open, `SessionProvider.loadActiveSession` reads the hint:
- Gap < 2 hours → silently resumes tracking (restarts foreground service, rebinds connectivity)
- Gap ≥ 2 hours → properly ends the session (`auto_ended`, reason: `oem_kill`)

`sweepSignalLostSessions` (runs every 10 min server-side) is the safety net for devices that never reopen the app.

### 3. Sync Manager (`sync_manager.dart`)

Manages the buffer of pending GPS locations and flushes them to Firestore.

**Flush Triggers:**
| Trigger | Condition |
|---------|-----------|
| Threshold | >= 20 pending locations |
| Periodic | Every 20 minutes |
| Reconnect | Connectivity restored after offline |
| Manual | `flushNow()` or `finalFlush()` command |

**Flush Operation:**
1. Reads all pending locations from SQLite
2. Reverse-geocodes latest location (5s timeout)
3. Creates Firestore batch (max 490 location docs per batch, 1 slot reserved for session update):
   - Location docs in `sessions/{sessionId}/locations/{docId}`
   - Updates session `lastSyncAt` (client does **not** write `totalDistance` — server recalculates trusted distance via Haversine on session complete)
   - One activity log entry for the flush (latest position only, not per-point)
4. Commits batch (splits into multiple batches if > 490 locations)
5. Deletes flushed rows from SQLite
6. Fires sync event to main app

On reconnect after offline period, `SyncManager` validates the Firestore session is still active before restoring presence — prevents zombie sessions from coming back online.

**Reverse Geocoding:**
- Uses `geocoding` package
- Builds address: street > thoroughfare > name, subLocality, locality
- Falls back to "Lat: X.XXXX, Lng: Y.YYYY" on failure

### 4. Pending Location Store (`pending_location_store.dart`)

SQLite persistence layer for offline-first location tracking.

Backed by the shared `AppDatabase` (`app_database.dart`), currently at schema version **6**. The same database also hosts the `offline_jobs` table used by `OfflineQueueManager` for chat/send retries.

**Schema history:**
- v1–2: `pending_locations` + `offline_jobs`
- v3: Added `session_state`; also added `idempotency_key` column to `offline_jobs`
- v4–5: Fixed `idempotency_key` for fresh installs that missed it
- v6: Dropped `diagnostic_logs` table (current)

`OfflineQueueManager` hardening:
- `_staleProcessingTimeout` is **30s**.
- `start()` runs `_cleanupStuckJobsOnStartup()` before the first `processQueue()`: orphaned `processing` jobs reset to `pending` (retryCount=0); exhausted `error` jobs marked `failed`.
- `_nextEligibleJob` defensively flips exhausted error jobs to `failed` before iterating.
- `clearFailedChatJobs()` deletes permanently-failed chat jobs; called from `ChatConversationScreen.initState`.
- `_processChatJob` calls `ChatRepository.sendMessage(groupId, message)` without a documentId; dedup uses `clientRequestId` in the payload.

**Tables:**

**`pending_locations`** — GPS points awaiting sync
| Column | Type | Purpose |
|--------|------|---------|
| session_id | TEXT | Links to Firestore session |
| enterprise_id | TEXT | Enterprise reference |
| employee_id | TEXT | Employee reference |
| latitude / longitude | REAL | GPS coordinates |
| accuracy | REAL | Horizontal accuracy (meters) |
| speed | REAL | Speed (m/s) |
| heading | REAL | Bearing (degrees) |
| activity_type | TEXT | WALKING, STILL, etc. |
| activity_confidence | INTEGER | 0-100 |
| cumulative_distance_km | REAL | Running total |
| captured_at_ms | INTEGER | Capture timestamp |

**`session_state`** — Crash recovery
| Column | Type | Purpose |
|--------|------|---------|
| session_id | TEXT | Active session ID |
| employee_id / enterprise_id | TEXT | Context |
| start_time_ms | INTEGER | Session start |
| total_distance_km | REAL | Running distance |
| last_lat / last_lng | REAL | Last known position |
| last_synced_at_ms | INTEGER | Last flush time |
| status | TEXT | 'active' or 'ending' |

### 5. Native Session Guard

**Dart wrapper:** `session_task_guard.dart`
**Kotlin service:** `SessionTaskRemovalService.kt`

Handles the case where the user swipes the app from recent apps. The Flutter engine may be dead, so a native Android service takes over.

**Flow:**
1. `SessionTaskGuard.start()` persists session context to SharedPreferences
2. If app is swiped from recents, `onTaskRemoved()` fires
3. Reads context from SharedPreferences
4. Validates session is still active in Firestore
5. Batch update: sets session to `auto_ended`, writes activity log
6. Updates RTDB: sets presence to `offline`, clears activeStats and heartbeat
7. Clears SharedPreferences

**Safety:** `SessionTaskGuard.stop()` is called during normal session end to prevent spurious auto-end.

## Session Lifecycle

### Start Session
```
1. DeviceHealthMonitor.runAllChecks() — block start if location-always / battery
   optimization / notifications (Android 13+) are missing
2. Validate location permission
3. Get current position (10s timeout, fallback to last known)
4. Reverse geocode address
5. Reset RTDB activeStats and clear any stale nodes from prior sessions
6. Create Firestore session doc {status: active, startTime, employeeId, enterpriseId}
7. Clear stale SQLite pending_locations from any prior session
8. Write session_started activity log (fire-and-forget)
9. Parallel:
   - Set RTDB presence to active + setup onDisconnect → signal_lost
   - Update live location in RTDB
   - Start foreground tracking service (TrackingForegroundService.startTracking)
10. Write check-in location to session/locations subcollection
11. Start native Android task guard (SessionTaskGuard.start)
12. Bind connectivity monitor; clear FIX-6 needs_resume flag from SharedPreferences
```

### End Session
```
1. Final flush of location buffer (waits up to 5s)
2. Stop foreground service — marks context as 'ending' first (race condition guard),
   then clears context so onDestroy skips FIX-6 signal_lost path
3. Stop native Android task guard
4. Clear RTDB onDisconnect handler
5. Update Firestore session: endTime, status=completed, totalDuration, totalDistance
6. Set RTDB presence to offline
7. Clear activeStats, heartbeat, liveLocation from RTDB
8. Write check-out location to session/locations subcollection
9. Write session_ended activity log; upsert daily summary
```

## RTDB Paths

| Path | Purpose | Updated By |
|------|---------|-----------|
| `presence/{eid}/{uid}` | Employee online status | Heartbeat (25m), session start/end, onDisconnect |
| `liveLocations/{eid}/{uid}` | Live GPS position | Each accepted poll |
| `activeStats/{eid}/{uid}` | Live session stats | Each accepted poll |
| `sessionHeartbeat/{eid}/{uid}` | Service alive signal | Heartbeat timer (25m) |

## Stale Session Detection

The dashboard provider detects dead sessions using two client-side signals:

| Signal | Threshold | Meaning |
|--------|-----------|---------|
| Live location age | > 25 min | GPS polling stopped |
| Heartbeat age | > 35 min | Foreground service died (heartbeat fires every 15 min) |

If BOTH are stale, status is set to `signal_lost` regardless of RTDB presence status.

The server-side sweep (`sweepSignalLostSessions`) runs every **10 minutes** and auto-ends:
- Sessions with `signal_lost` status > **15 min**
- Sessions with `active`/`break` status where ALL of presence, heartbeat, and location are stale > **15 min**
- Any session exceeding **16 hours** (hard cutoff)
- Also cleans up orphaned RTDB nodes without a matching Firestore session
