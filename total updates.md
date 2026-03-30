# Total Updates

This document summarizes the major work completed from yesterday onward across tracking, offline sync, analytics, admin history, media uploads, platform setup, release work, and follow-up bug fixes.

## 1. Tracking Architecture Rebuild

- Refactored the app from UI-owned tracking to a foreground-service-driven tracking model.
- `session_provider.dart` was reduced to a session/UI coordinator instead of owning a timer or continuous GPS stream.
- `tracking_foreground_service.dart` was introduced/expanded to start and manage the headless foreground tracking service.
- `tracking_task_handler.dart` now runs the background tracking isolate independently of the UI.
- `sync_manager.dart` now handles periodic background flushing of buffered tracking data.
- `pending_location_store.dart` stores location fixes locally in SQLite before sync.

### New behavior

- Session start creates the Firestore session and sets RTDB presence.
- Tracking continues through the foreground task instead of depending on an open screen.
- Session duration is calculated in UI from `startTime` rather than a provider-owned 1-second timer.
- Background tracking remains resilient to weak signal and app backgrounding.

## 2. Battery Optimization and Motion-Driven Polling

- Added activity-recognition-driven tracking profiles:
  - `STILL` -> 5 minutes
  - `WALKING` / `RUNNING` / `ON_BICYCLE` -> 60 seconds
  - `IN_VEHICLE` -> 20 seconds
- Each GPS poll uses a time limit to avoid long hangs in dead zones.
- Distance accumulation happens locally in the background isolate.
- If activity recognition is unavailable, fallback behavior was set to the safer walking profile instead of a faster fallback.

### Android/iOS hardening

- Added foreground-service permissions and service declarations in Android manifest.
- Added battery optimization bypass checks on Android.
- Added iOS background/task configuration support and related registration.
- Fixed Android notification small icon handling so background notifications no longer show a blank white block.

## 3. Offline-First Tracking Sync

- Tracking now buffers location points locally in SQLite instead of writing every fix directly to Firestore.
- RTDB heartbeat and live presence are maintained separately from Firestore history.
- Added reconnect flush behavior and periodic flush support.
- Added final flush support on session end.

### Later fix

- Corrected the flush behavior so buffered GPS points are not turned into an activity log on every poll.
- The session `locations` subcollection now receives the latest buffered point on flush instead of one document per sampled GPS fix.
- This reduced activity-feed spam that previously appeared minute by minute.

## 4. Presence and Session Lifecycle

- Presence now uses explicit states:
  - `active`
  - `signal_lost`
  - `offline`
- `onDisconnect()` was changed to mark `signal_lost` rather than immediate offline.
- Added server-side auto-ending for stale `signal_lost` sessions after one hour.
- Added cleaner shutdown flow:
  - final queue flush
  - stop foreground service
  - clear disconnect behavior
  - mark Firestore session ended
  - clear RTDB live state

### RTDB rules fix

- Fixed a real-time database rules gap: `sessionHeartbeat` had no client write rule.
- This was causing `[firebase_database/permission-denied]` during end session and could interfere with background heartbeat writes.
- Updated `database.rules.json` and deployed new database rules.

## 5. Cloud Functions and Backend Cleanup

- Removed legacy heartbeat cleanup conflict so only the newer `signal_lost` sweeper remains relevant.
- Added or updated canonical analytics/event writers for:
  - session start/end
  - session auto-end
  - location updates from session location docs
  - photo creation
  - task start
  - task completion
- Added an analytics integrity checker scheduled function.
- Deployed new Functions to Firebase.

## 6. Unified Offline Queue for Chat and Photos

- Added a shared `offline_jobs` SQLite table and queue model/store.
- Added a durable file manager that copies captured photos from volatile cache into app-managed storage before queueing.
- Implemented `offline_queue_manager.dart` to process pending chat and photo jobs in FIFO order.
- Hooked queue processing to connectivity restoration and manual triggers.

### Photo queue behavior

- Photos now queue locally first, upload later, and survive app restart/offline periods.
- Image compression runs off the main isolate before upload.
- Storage uploads use deterministic paths based on `clientRequestId` to prevent blob leaks on retries.
- Queued photo jobs can also include:
  - share-to-chat targets
  - follow-up task instructions
- Those chained writes are committed atomically in Firestore after upload.

### Later retry/duplicate fix

- Fixed queued photo jobs getting stuck in `processing` after interrupted uploads.
- Added stale `processing` recovery in `offline_queue_manager.dart`.
- Made queued photo Firestore doc IDs deterministic based on job ID, so retries no longer create fresh photo docs each time.
- Made related queued share/follow-up docs deterministic too.
- Added deduplication in `photo_provider.dart` by `clientRequestId`.
- Prevented retry from re-triggering a job that is already pending or processing.

## 7. Optimistic UI for Chat, Tasks, and Photos

- Added `UploadStatus` model for pending/success/error state.
- Chat sending became optimistic:
  - local pending item appears immediately
  - success/error resolves asynchronously
  - retry support added
- Task completion became optimistic in the same way.
- Photo upload became optimistic with local thumbnails shown immediately and overlay status handling.

## 8. Analytics Migration and Canonical Event Pipeline

- Historical analytics migration was added and executed to backfill older data into `activityLogs`.
- Migrated and/or backfilled:
  - session start/end
  - historical photos
  - historical location stamps
  - available task history
- Introduced the goal that `activityLogs` becomes the canonical source of truth for timeline/history.
- RTDB is now treated as live state only.
- Daily summaries are treated as aggregated cache only.

## 9. Admin Analytics and History Refactor

- `employee_activity_screen.dart` was refactored to follow the selected analytics period rather than a separate internal day filter.
- Removed the duplicate inner date filter from employee analytics detail.
- Added shared admin feed logic in `admin_activity_feed_service.dart`.
- Both `employee_activity_screen.dart` and `employee_detail_screen.dart` now use a shared merged feed strategy rather than separate brittle read paths.

### Feed improvements

- Added linked-ID resolution for current and migrated employee IDs.
- Added session-ID-based reads in addition to employee-ID-based reads.
- Added merging and deduplication of employee-based and session-based results.
- Added fallback session history lookup by employee IDs for historical data.
- Added explicit `photo_captured` activity-log recovery so Analytics `Images` tab can recover work photos even when narrower photo queries fail.
- Added handling so admin session-location read failures do not collapse the whole detail load.

### Session stats improvements

- Added fallback for `Started` / `Ended` times using real historical sessions when activity logs are incomplete.
- Added support for loading historical sessions even when summaries do not provide enough session IDs.

## 10. Admin Dashboard and Presence Mapping

- Updated admin/dashboard presence parsing for:
  - `active`
  - `offline`
  - `signal_lost`
- Added manager-facing `signal_lost` treatment so workers are not misread as plain offline.
- Ensured elapsed session calculations continue while status is `signal_lost` until the backend ends the session.

## 11. Analytics / History Debugging Findings

- Confirmed several cases where summary data existed in Firebase but detail screens were blind to it.
- Verified that historical photos and migrated `photo_captured` logs existed for affected users such as Rajendra.
- Identified that admin detail loads were collapsing because of query path fragility and Firestore rules on `sessions/{sessionId}/locations`.
- Added app-side compatibility/fallback read paths without changing source-of-truth Firestore document structure.

## 12. UI / Design System and Icon Migration

- Performed a broad widget-tree redesign toward a cleaner glass/borderless visual style.
- Migrated the icon set from `iconsax` to `hugeicons`.
- Refined shared presentation components such as headers, chips, buttons, and inputs.
- Modernized chat bubbles, camera HUD, preview forms, chat list/group creation, gallery, and fullscreen photo views.
- Fixed semantic icon mismatches and text mojibake afterward.

## 13. Permissions and Native Behavior

- Confirmed camera, storage/photos, notification, and location permission flows remained in place.
- Session start still requires location permission and location services enabled.
- Added Android battery-optimization preflight checks for modern device/OEM behavior.

## 14. Release / Build / Deployment Work

- Updated release versions up to `1.0.21+34`.
- Updated Codemagic configuration accordingly.
- Built fresh release APKs and AABs multiple times during validation.
- Fixed Android release build issue caused by `disable_battery_optimization` by enabling Jetifier.
- Deployed Cloud Functions and Realtime Database rules as needed.

## 15. Code Quality and Stability Cleanup

- Removed dead code flagged by the linter.
- Fixed `use_build_context_synchronously` warnings.
- Adjusted analysis config to avoid third-party generated plugin noise.
- Restored a passing state for:
  - `dart analyze`
  - `flutter test`
  - Functions TypeScript build

## 16. Gallery / Media / Chat Bug Fixes

- Fixed deleted-chat preview issue where removed messages still appeared in chat list previews.
- Fixed gallery upload retry path that could produce duplicate tiles.
- Fixed background/local notification icon display.

## 17. Current Expected Behavior

- Worker tracking remains foreground-service based and offline-first.
- GPS sampling still follows motion-driven polling.
- Firestore timeline logging should now happen on flush behavior rather than on every GPS fix.
- Chat and photos are queue-backed and durable across offline/restart scenarios.
- Admin analytics/history now use a much more robust merged feed strategy.

## 18. Important Remaining Real-World Validation

The architecture and code were heavily stabilized, but these still need ongoing real-device validation:

- updated employee online session
- updated employee offline then reconnect
- mixed-version employee still on older build
- admin History last 24h
- admin Analytics detail for migrated old data
- gallery retry behavior under weak signal
- swipe-from-recents behavior on aggressive OEM Android devices

## 19. Data Safety Notes

- Distributor / farmer metadata stored on `photos` documents remains safe.
- Geotag and preview metadata remain safe on source photo docs.
- The migration work rebuilt analytics/timeline views from source data; it did not replace the original photo/source records.

