<div align="center">

# Izumi

**Field Workforce Management & Intelligence Platform**

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Firebase](https://img.shields.io/badge/Firebase-Backend-FFCA28?logo=firebase&logoColor=black)](https://firebase.google.com)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS-green)]()
[![License](https://img.shields.io/badge/License-Proprietary-red)]()

---

*Real-time GPS tracking, live dashboards, photo intelligence, and analytics for distributed field teams.*

</div>

---

## Overview

Izumi is a full-stack mobile platform built for enterprises managing field workforces — sales teams, delivery fleets, agricultural field agents, and service technicians. It provides real-time visibility into where employees are, what they're doing, and how they're performing.

### Key Capabilities

| Feature | Description |
|---------|-------------|
| **Live GPS Tracking** | Sub-minute location updates with activity-aware polling (walking, driving, stationary) |
| **Session Management** | Clock-in/out with automatic session lifecycle, crash recovery, and ghost session prevention |
| **Live Dashboard** | Google Maps with real-time employee markers, status indicators, and draggable employee list |
| **Photo Intelligence** | Geotagged field photos with category tagging, customer association, and thumbnail generation |
| **Analytics Engine** | Daily/weekly/monthly breakdowns with per-employee duration, distance, and productivity metrics |
| **Activity Timeline** | Chronological feed of all field events — sessions, locations, photos, tasks |
| **Task Assignment** | Create and assign tasks to field employees with real-time completion tracking |
| **Team Chat** | Group messaging with image sharing, location sharing, and read receipts |
| **Offline Resilience** | SQLite buffer for GPS data, offline job queue for photos and messages |
| **Multi-Role Access** | Admin, Team Lead, and Employee roles with role-based routing and permissions |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Flutter App (Dart)                       │
├──────────┬──────────┬──────────┬──────────┬─────────────────────┤
│ Provider │ GoRouter │ Foreground│ SQLite  │  Google Maps        │
│  State   │   Nav    │  Service │ Buffer  │  Flutter Plugin     │
├──────────┴──────────┴──────────┴──────────┴─────────────────────┤
│                     Firebase Backend                            │
├──────────┬──────────┬──────────┬──────────┬─────────────────────┤
│Firestore │  RTDB   │ Storage  │  Auth   │  Cloud Functions     │
│ Sessions │ Presence │  Photos  │  JWT    │  Triggers +          │
│ Logs     │ Live Loc │  Exports │  Claims │  Schedulers          │
│ Photos   │ Stats   │          │         │  Callables           │
└──────────┴──────────┴──────────┴──────────┴─────────────────────┘
```

### Tech Stack

| Layer | Technology |
|-------|-----------|
| **Frontend** | Flutter 3.x, Dart, Provider, GoRouter |
| **Maps** | Google Maps Flutter, Geolocator, Geocoding |
| **Backend** | Firebase (Firestore, Realtime Database, Auth, Storage, Cloud Functions) |
| **Tracking** | Android Foreground Service, Activity Recognition, SQLite batch sync |
| **Charts** | fl_chart |
| **Notifications** | FCM + Flutter Local Notifications |
| **Native** | Kotlin (Android session guard), Swift (iOS) |

---

## App Screens

### Admin Screens

| Screen | Purpose |
|--------|---------|
| **Dashboard** | Full-screen map with live employee markers, draggable bottom sheet with status filters and employee list |
| **Analytics** | Enterprise-wide metrics with daily bar charts, employee performance cards, period selectors (Today/Week/Month/Custom) |
| **Employee Detail** | Live route map, real-time duration timer, distance/photos stats, activity feed (last 24h) |
| **Employee Activity** | Historical route visualization, session-grouped timeline, photo captures, date range navigation |
| **Management** | Group and user management with CRUD operations |
| **Chat** | Group conversations with text, image, and location messages |

### Employee Screens

| Screen | Purpose |
|--------|---------|
| **Home** | Session start/stop, live tracking status, current location display |
| **Camera** | Geotagged photo capture with category and customer tagging |
| **Tasks** | Assigned task list with completion workflow |
| **History** | Personal activity timeline and session history |
| **Gallery** | Photo library with date grouping and category filters |

---

## Tracking Engine

The GPS tracking system is designed for reliability across all Android OEMs (Samsung, Xiaomi, Motorola, Oppo, etc.):

```
Session Start
    │
    ├─► Foreground Service launched (persistent notification)
    ├─► Activity Recognition started (STILL / WALKING / DRIVING)
    ├─► RTDB presence set to "active"
    ├─► onDisconnect handler set to "signal_lost"
    │
    ▼
Polling Loop (adaptive interval)
    │
    ├─► STILL → 5 min interval, medium accuracy
    ├─► WALKING → 60s interval, medium accuracy
    ├─► DRIVING → 20s interval, high accuracy
    │
    ├─► GPS fix → accuracy filter (≤30m) → speed filter (≤100 m/s)
    ├─► Write to SQLite pending_locations buffer
    ├─► Flush to Firestore every 20 locations or 20 minutes
    ├─► Update RTDB liveLocation + activeStats
    │
    ▼
Session End (manual or auto)
    │
    ├─► Final GPS snapshot + location flush
    ├─► Firestore session doc updated (endTime, duration, distance)
    ├─► RTDB presence → "offline", cleanup activeStats/heartbeat/liveLocations
    ├─► Local push notification to employee
    └─► Cloud Function computes daily summary + trusted distance
```

### Crash Recovery

| Scenario | Recovery Mechanism |
|----------|-------------------|
| App swiped from recents | `onDestroy()` fire-and-forget cleanup (< 2s), sets presence to offline |
| onDestroy fails | `SessionTaskRemovalService.kt` safety net (3s delay, checks RTDB first) |
| Phone loses internet | RTDB `onDisconnect` sets "signal_lost", server sweep auto-ends after 15 min |
| App crashes | SQLite session state restored on restart, pending locations preserved |
| Phone reboots | `BootReceiver` checks for orphaned active sessions |

---

## Cloud Functions

| Function | Trigger | Purpose |
|----------|---------|---------|
| `onSessionStarted` | Firestore write | Writes `session_started` activity log |
| `onSessionEnded` | Firestore write | Writes `session_ended` activity log |
| `onSessionComplete` | Firestore update | Computes trusted distance, creates daily summary |
| `onSessionLocationCreated` | Firestore create | Writes `location_update` activity log with geocoded address |
| `onPhotoDocumentCreated` | Firestore create | Generates thumbnail, writes `photo_captured` activity log |
| `onPresenceOffline` | RTDB write | Auto-ends session if heartbeat stale > 1 hour |
| `sweepSignalLostSessions` | Scheduled (10 min) | Ends signal-lost sessions > 15 min, force-ends sessions > 16 hours |
| `sanitizeActiveStats` | Scheduled (10 min) | Validates distance calculations, corrects implausible jumps |
| `dailySummaryAggregator` | Scheduled | Aggregates daily employee metrics |
| `forceEndGhostSessions` | Callable (admin) | One-click cleanup of all stuck/ghost sessions |
| `backfillActivityLogs` | Callable (admin) | Backfills missing timeline data from sessions/photos |

---

## Project Structure

```
lib/
├── core/
│   ├── constants/          # Colors, typography, spacing, shadows
│   └── ui/                 # Icon definitions
├── models/                 # Data models (User, Session, Photo, Task, etc.)
├── providers/              # State management (ChangeNotifier providers)
├── repositories/           # Firestore CRUD operations
├── screens/
│   ├── admin/              # Dashboard, Analytics, Employee Detail, Management
│   ├── employee/           # Home, Camera, Tasks, History, Profile
│   └── shared/             # Chat, Notifications
├── services/               # RTDB service, activity feed, geocoding, location
├── tracking/               # Foreground service, task handler, sync manager, SQLite store
├── widgets/                # Reusable UI components (glass panels, buttons, inputs)
└── router/                 # GoRouter configuration with role-based guards

functions/src/
├── auth/                   # User creation trigger
├── sessions/               # Session lifecycle triggers
├── photos/                 # Photo processing triggers
├── tasks/                  # Task assignment/completion triggers
├── chat/                   # Chat message triggers
├── scheduled/              # Cron jobs (sweep, sanitize, aggregate, cleanup)
├── callable/               # Admin tools (export, cleanup, backfill, migrations)
└── utils/                  # Shared utilities (notifications, activity log writer)

android/
└── app/src/main/kotlin/    # SessionTaskRemovalService, BootReceiver, MainActivity
```

---

## Getting Started

### Prerequisites

- Flutter SDK 3.x+
- Android Studio / VS Code
- Firebase project with Firestore, RTDB, Auth, Storage, Cloud Functions
- Google Maps API key (Maps SDK for Android + iOS enabled)
- Node.js 22+ (for Cloud Functions)

### Setup

```bash
# Clone the repository
git clone https://github.com/pratxf/Izumi.git
cd Izumi

# Install Flutter dependencies
flutter pub get

# Install Cloud Functions dependencies
cd functions && npm install && cd ..

# Configure Firebase
flutterfire configure

# Add Google Maps API key
# Android: android/app/src/main/AndroidManifest.xml
# iOS: ios/Runner/AppDelegate.swift

# Run the app
flutter run
```

### Build

```bash
# Android APK
flutter build apk --release

# Android App Bundle (Play Store)
flutter build appbundle --release

# iOS
flutter build ios --release
```

### Deploy Cloud Functions

```bash
cd functions
npm run build
firebase deploy --only functions
```

---

## Environment

| Config | Location |
|--------|----------|
| Firebase options | `lib/firebase_options.dart` (auto-generated) |
| Android manifest | `android/app/src/main/AndroidManifest.xml` |
| iOS config | `ios/Runner/AppDelegate.swift` |
| Cloud Functions | `functions/src/` |
| Firestore indexes | `firestore.indexes.json` |
| Firestore rules | `firestore.rules` |
| RTDB rules | `database.rules.json` |

---

<div align="center">

**Built by [@pratxf](https://github.com/pratxf)**

</div>
