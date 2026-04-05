<div align="center">

<img src="assets/branding/launcher_icon.png" width="120" alt="Izumi Logo" />

# IZUMI

### Field Workforce Management & Intelligence Platform

[![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![Firebase](https://img.shields.io/badge/Firebase-FFCA28?style=for-the-badge&logo=firebase&logoColor=black)](https://firebase.google.com)
[![Dart](https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white)](https://dart.dev)
[![Kotlin](https://img.shields.io/badge/Kotlin-7F52FF?style=for-the-badge&logo=kotlin&logoColor=white)](https://kotlinlang.org)
[![Google Maps](https://img.shields.io/badge/Google%20Maps-4285F4?style=for-the-badge&logo=googlemaps&logoColor=white)](https://developers.google.com/maps)

<br />

[![Android](https://img.shields.io/badge/Android-3DDC84?style=flat-square&logo=android&logoColor=white)]()
[![iOS](https://img.shields.io/badge/iOS-000000?style=flat-square&logo=apple&logoColor=white)]()
[![Node.js](https://img.shields.io/badge/Cloud%20Functions-Node%2022-339933?style=flat-square&logo=node.js&logoColor=white)]()
[![TypeScript](https://img.shields.io/badge/TypeScript-3178C6?style=flat-square&logo=typescript&logoColor=white)]()

<br />

**Real-time GPS tracking** &nbsp;&bull;&nbsp; **Live map dashboards** &nbsp;&bull;&nbsp; **Photo intelligence** &nbsp;&bull;&nbsp; **Enterprise analytics**

<br />

<img src="https://img.shields.io/badge/version-1.0.54-4F46E5?style=flat-square" />
<img src="https://img.shields.io/badge/build-passing-22C55E?style=flat-square" />
<img src="https://img.shields.io/badge/license-proprietary-EF4444?style=flat-square" />

---

</div>

<br />

## What is Izumi?

Izumi gives enterprises **complete real-time visibility** into their distributed field workforce. Whether you're managing sales reps across cities, agricultural field agents in rural areas, or delivery fleets on the road &mdash; Izumi tracks where your people are, what they're doing, and how they're performing.

> *One app for the field team. One dashboard for the enterprise.*

<br />

## Highlights

<table>
<tr>
<td width="50%">

### For Admins
- Live map with employee markers (active / signal lost / offline)
- Draggable bottom sheet with status filters and search
- Real-time route visualization per employee
- Analytics with daily bar charts and progress tracking
- One-click ghost session cleanup
- Task assignment and photo review

</td>
<td width="50%">

### For Field Employees
- One-tap session start with GPS tracking
- Activity-aware polling (walking / driving / stationary)
- Geotagged photo capture with categories
- Task completion workflow
- Personal activity history and timeline
- Offline-resilient &mdash; works without internet

</td>
</tr>
</table>

<br />

---

<br />

## Architecture

```
                           ┌──────────────────────────────────┐
                           │         IZUMI MOBILE APP         │
                           │           Flutter + Dart          │
                           └──────────┬───────────────────────┘
                                      │
                    ┌─────────────────┼─────────────────┐
                    │                 │                 │
              ┌─────▼─────┐   ┌──────▼──────┐   ┌─────▼─────┐
              │  Provider  │   │  Foreground  │   │  SQLite   │
              │   State    │   │   Service    │   │  Buffer   │
              │ Management │   │ GPS + Activity│   │ Offline   │
              └─────┬─────┘   └──────┬──────┘   └─────┬─────┘
                    │                │                 │
                    └────────────────┼─────────────────┘
                                     │
                    ┌────────────────▼────────────────┐
                    │        FIREBASE BACKEND         │
                    ├────────┬────────┬───────┬───────┤
                    │        │        │       │       │
               Firestore   RTDB   Storage   Auth   Functions
               ─────────  ──────  ───────  ──────  ─────────
               Sessions   Presence Photos   JWT    Triggers
               Logs       Live Loc Exports  Claims Schedulers
               Photos     Stats            Roles  Callables
               Tasks      Heartbeat
               Chat
                    │
                    └────────────────────────────────────┘
```

<br />

### Tech Stack

<table>
<tr>
<td><strong>Frontend</strong></td>
<td>Flutter 3.x &bull; Dart &bull; Provider &bull; GoRouter &bull; Google Maps Flutter &bull; fl_chart</td>
</tr>
<tr>
<td><strong>Backend</strong></td>
<td>Cloud Firestore &bull; Realtime Database &bull; Firebase Auth &bull; Cloud Storage &bull; Cloud Functions v2</td>
</tr>
<tr>
<td><strong>Tracking</strong></td>
<td>Android Foreground Service &bull; Activity Recognition &bull; SQLite batch sync &bull; Geolocator &bull; Geocoding</td>
</tr>
<tr>
<td><strong>Native</strong></td>
<td>Kotlin (SessionTaskRemovalService, BootReceiver) &bull; Swift (iOS lifecycle)</td>
</tr>
<tr>
<td><strong>Notifications</strong></td>
<td>FCM &bull; Flutter Local Notifications &bull; Force logout via remote message</td>
</tr>
</table>

<br />

---

<br />

## Core Features

### Live Dashboard &mdash; *see everyone, everywhere*

Full-screen Google Maps with custom employee markers. Active employees glow indigo. Signal-lost employees glow amber. Tap a marker to zoom in and highlight their card. Drag the bottom sheet up for the full employee list with search, status filters, distance, and duration.

<br />

### GPS Tracking Engine &mdash; *built for the real world*

The tracking system is designed to survive every Android OEM's battery optimization. It adapts polling frequency based on what the employee is doing:

| Activity | Poll Interval | Accuracy | Use Case |
|----------|:------------:|:--------:|----------|
| **Stationary** | 5 min | Medium | Employee at a store or office |
| **Walking** | 60s | Medium | On-foot field visits |
| **Driving** | 20s | High | In-vehicle transit |

Every GPS fix passes through:
1. **Accuracy filter** &mdash; rejects fixes worse than 30m
2. **Speed spike filter** &mdash; rejects impossible speeds (> 360 km/h)
3. **SQLite buffer** &mdash; stored locally, flushed to Firestore in batches
4. **RTDB live update** &mdash; real-time position visible on admin dashboard

<br />

### Session Lifecycle &mdash; *no ghost sessions, ever*

```
 START                    TRACKING                         END
  ━━━━                    ━━━━━━━━                        ━━━━
   │                         │                              │
   ├─ Reset RTDB stats       ├─ Adaptive GPS polling        ├─ Final flush
   ├─ Clear stale data       ├─ SQLite buffer writes        ├─ Firestore update
   ├─ Create Firestore doc   ├─ Periodic Firestore flush    ├─ RTDB → offline
   ├─ Write activity log     ├─ RTDB live location          ├─ Cancel onDisconnect
   ├─ Set presence active    ├─ Heartbeat (25 min)          ├─ Push notification
   ├─ Setup onDisconnect     │                              ├─ Activity log
   └─ Start foreground svc   │                              └─ Stop foreground svc
```

<br />

### Crash Recovery Matrix

| Scenario | What Happens | Recovery Time |
|----------|-------------|:------------:|
| App swiped from recents | `onDestroy` fires, sets offline, ends session | **< 5 seconds** |
| `onDestroy` killed by OS | `SessionTaskRemovalService.kt` safety net | **< 8 seconds** |
| Phone loses internet | RTDB `onDisconnect` &rarr; signal_lost &rarr; server sweep | **15 minutes** |
| App force-stopped / crashes | SQLite state restored on next launch | **Next app open** |
| Phone reboots | `BootReceiver` detects orphaned session | **On boot** |
| All else fails | Admin presses "Clear Ghost Sessions" | **Instant** |

<br />

### Analytics &mdash; *measure what matters*

- **Period selectors**: Today / Week / Month / Custom date range
- **Enterprise summary**: Total hours, kilometers, photos across all employees
- **Daily bar chart**: Hours per day with fl_chart visualization
- **Employee cards**: Duration, distance, photos with relative progress bars
- **Drill-down**: Full activity timeline per employee with session grouping

<br />

### Activity Timeline &mdash; *every event, in order*

```
 Session Started      ●───── 9:00 AM    Gohana, Shiv Nagar, Panipat
                      │
 Tracked Location     ●───── 9:15 AM    NH 709AD, Panipat
                      │
 Tracked Location     ●───── 9:30 AM    653456, Huda, Panipat
                      │
 Photo Captured       ●───── 9:45 AM    farmer  ·  Rajesh Kumar
                      │
 Tracked Location     ●───── 10:00 AM   92JF+M6V, Panipat
                      │
 Session Ended        ●───── 11:30 AM   Duration: 2h 30m  ·  15.6 km
```

Each event is backfilled from Firestore sessions, locations, and photos. Future events are written automatically by Cloud Function triggers.

<br />

---

<br />

## Cloud Functions

<table>
<tr>
<th>Function</th>
<th>Trigger</th>
<th>What it does</th>
</tr>
<tr><td><code>onSessionStarted</code></td><td>Firestore create</td><td>Writes <code>session_started</code> to activity timeline</td></tr>
<tr><td><code>onSessionEnded</code></td><td>Firestore update</td><td>Writes <code>session_ended</code> with duration and distance</td></tr>
<tr><td><code>onSessionComplete</code></td><td>Firestore update</td><td>Computes trusted distance via Haversine, creates daily summary</td></tr>
<tr><td><code>onSessionLocationCreated</code></td><td>Firestore create</td><td>Writes <code>location_update</code> with geocoded address</td></tr>
<tr><td><code>onPhotoDocumentCreated</code></td><td>Firestore create</td><td>Generates thumbnail, writes <code>photo_captured</code> log</td></tr>
<tr><td><code>onPresenceOffline</code></td><td>RTDB write</td><td>Auto-ends session if heartbeat stale > 1 hour</td></tr>
<tr><td><code>sweepSignalLostSessions</code></td><td>Cron (10 min)</td><td>Ends signal-lost > 15 min, force-ends > 16 hours</td></tr>
<tr><td><code>sanitizeActiveStats</code></td><td>Cron (10 min)</td><td>Detects and corrects implausible distance jumps</td></tr>
<tr><td><code>dailySummaryAggregator</code></td><td>Cron</td><td>Aggregates daily employee performance metrics</td></tr>
<tr><td><code>forceEndGhostSessions</code></td><td>Callable</td><td>Admin one-click cleanup of all stuck sessions</td></tr>
<tr><td><code>backfillActivityLogs</code></td><td>Callable</td><td>Generates missing timeline data from historical sessions</td></tr>
</table>

<br />

---

<br />

## Project Structure

```
izumi/
│
├── lib/
│   ├── core/                   Design system (colors, typography, icons)
│   ├── models/                 Data models (User, Session, Photo, Task, Chat)
│   ├── providers/              State management (8 ChangeNotifier providers)
│   ├── repositories/           Firestore CRUD layer
│   ├── screens/
│   │   ├── admin/              Dashboard, Analytics, Employee Detail, Management
│   │   ├── employee/           Home, Camera, Tasks, History, Profile, Gallery
│   │   └── shared/             Chat, Notifications
│   ├── services/               RTDB, activity feed, geocoding, location
│   ├── tracking/               Foreground service, GPS handler, sync manager
│   ├── widgets/                Glass panels, buttons, inputs, navigation
│   └── router/                 GoRouter with role-based guards
│
├── android/
│   └── .../kotlin/             SessionTaskRemovalService, BootReceiver
│
├── ios/
│   └── Runner/                 AppDelegate with Maps SDK
│
└── functions/src/
    ├── sessions/               Session lifecycle triggers
    ├── photos/                 Photo processing + thumbnail generation
    ├── scheduled/              Sweep, sanitize, aggregate, cleanup
    ├── callable/               Admin tools (export, ghost cleanup, backfill)
    └── utils/                  Notifications, activity log writer
```

<br />

---

<br />

## Quick Start

```bash
# Clone
git clone https://github.com/pratxf/Izumi.git && cd Izumi

# Flutter
flutter pub get

# Cloud Functions
cd functions && npm install && cd ..

# Configure Firebase
flutterfire configure

# Run
flutter run
```

### Build for Production

```bash
flutter build apk --release          # Android APK
flutter build appbundle --release     # Play Store bundle
flutter build ios --release           # iOS
```

### Deploy Functions

```bash
cd functions && npm run build && firebase deploy --only functions
```

<br />

### Environment Setup

| What | Where |
|------|-------|
| Firebase config | `lib/firebase_options.dart` |
| Maps API key (Android) | `android/app/src/main/AndroidManifest.xml` |
| Maps API key (iOS) | `ios/Runner/AppDelegate.swift` |
| Firestore indexes | `firestore.indexes.json` |
| Cloud Functions | `functions/src/` |

<br />

---

<br />

<div align="center">

### Built with precision by **[@pratxf](https://github.com/pratxf)**

<br />

<sub>Izumi &mdash; because knowing where your team is shouldn't be guesswork.</sub>

</div>
