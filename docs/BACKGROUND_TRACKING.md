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
        +---> Heartbeat timer (every 25 min) --> RTDB presence
        +---> SyncManager flush (every 20 min or 20 locations)
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
| Accuracy | <= 30m | Reject poor GPS fixes |
| Movement | >= 15m | Discard stationary noise |
| Speed | <= 100 m/s (~360 km/h) | Reject impossible jumps |

**Heartbeat:**
- Sent every **25 minutes** to RTDB
- Updates `presence/{enterpriseId}/{employeeId}` with status and lastSeen
- Updates `sessionHeartbeat/{enterpriseId}/{employeeId}` with sessionId and lastSeen
- Used by dashboard to detect stale/dead sessions

**onDestroy Auto-End Logic:**
1. Checks if context was cleared from shared storage (normal end) — skips auto-end
2. Checks if session < 30 seconds old (likely a restart) — skips auto-end
3. Flushes remaining location buffer
4. Writes session end to Firestore (status: `auto_ended`)
5. Writes activity log entry
6. Sets RTDB presence to `signal_lost`
7. Sends local push notification to employee

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
3. Creates Firestore batch:
   - Location doc in `sessions/{sessionId}/locations/{docId}`
   - Updates session `totalDistance` and `lastSyncAt`
   - Activity log entry for location update
4. Commits batch
5. Deletes flushed rows from SQLite
6. Fires sync event to main app

**Reverse Geocoding:**
- Uses `geocoding` package
- Builds address: street > thoroughfare > name, subLocality, locality
- Falls back to "Lat: X.XXXX, Lng: Y.YYYY" on failure

### 4. Pending Location Store (`pending_location_store.dart`)

SQLite persistence layer for offline-first location tracking.

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
1. Check location permissions
2. Get current position (10s timeout, fallback to last known)
3. Reverse geocode address
4. Create Firestore session doc {status: active, startTime, employeeId, enterpriseId}
5. Parallel:
   - Set RTDB presence to active
   - Setup onDisconnect for signal_lost
   - Update live location in RTDB
   - Start foreground tracking service
6. Write check-in location to session/locations subcollection
7. Start native Android task guard
```

### End Session
```
1. Final flush of location buffer (waits up to 25s)
2. Stop foreground service (clear context so onDestroy skips auto-end)
3. Stop native Android task guard
4. Clear RTDB onDisconnect handler
5. Update Firestore session: endTime, status=completed, totalDuration, totalDistance
6. Set RTDB presence to offline
7. Clear activeStats, heartbeat, liveLocation from RTDB
8. Write check-out location to session/locations subcollection
9. Write daily summary
```

## RTDB Paths

| Path | Purpose | Updated By |
|------|---------|-----------|
| `presence/{eid}/{uid}` | Employee online status | Heartbeat (25m), session start/end, onDisconnect |
| `liveLocations/{eid}/{uid}` | Live GPS position | Each accepted poll |
| `activeStats/{eid}/{uid}` | Live session stats | Each accepted poll |
| `sessionHeartbeat/{eid}/{uid}` | Service alive signal | Heartbeat timer (25m) |

## Stale Session Detection

The dashboard provider detects dead sessions using two signals:

| Signal | Threshold | Meaning |
|--------|-----------|---------|
| Live location age | > 25 min | GPS polling stopped |
| Heartbeat age | > 35 min | Foreground service died |

If BOTH are stale, status is set to `signal_lost` regardless of RTDB presence status.

The server-side sweep (`sweepSignalLostSessions`) runs every 30 minutes and auto-ends:
- Sessions with `signal_lost` status > 1 hour
- Sessions with `active` status but stale `lastSeen` > 1 hour
