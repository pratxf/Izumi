# Izumi - Complete Firebase Backend Architecture

**Version:** 1.0
**Project:** Izumi - Field Workforce Management & Intelligence Platform
**Platform:** Flutter (Cross-platform Mobile)
**Date:** February 2026

---

## Table of Contents

1. [Frontend Analysis](#1-frontend-analysis)
2. [Firebase Architecture Design](#2-firebase-architecture-design)
3. [Data Models](#3-data-models)
4. [API & Function Flow](#4-api--function-flow)
5. [Security & Roles](#5-security--roles)
6. [Analytics & Logging](#6-analytics--logging)
7. [Implementation Plan](#7-implementation-plan)
8. [Task Plan](#8-task-plan)

---

## 1. Frontend Analysis

### 1.1 Application Overview

Izumi is a **Field Workforce Management & Intelligence Platform** designed for enterprises to track, manage, and analyze field employee activities in real-time.

### 1.2 Screens & User Flows

#### Authentication Screens
| Screen | File | Purpose |
|--------|------|---------|
| Welcome Screen | `welcome_screen.dart` | Phone input with role selection (Employee/Team Lead/Enterprise) |
| OTP Screen | `otp_screen.dart` | 4-digit OTP verification for phone auth |
| Enterprise Login | `enterprise_login_screen.dart` | Email/Password for admin access |

#### Employee Screens
| Screen | File | Purpose |
|--------|------|---------|
| Employee Shell | `employee_shell.dart` | Bottom navigation wrapper (4 tabs) |
| Home Screen | `home_screen.dart` | Session tracker (duration, distance, location, active tasks) |
| Camera Screen | `camera_screen.dart` | Geotagged photo capture with watermark overlay |
| Gallery Screen | `gallery_screen.dart` | Photo gallery organized by date with search |
| Todo Screen | `todo_screen.dart` | Task/Follow-up list with status filtering |
| History Screen | `history_screen.dart` | Monthly summary and daily session logs with timeline |
| Profile Screen | `profile_screen.dart` | User profile with settings menu |
| End of Day Screen | `end_of_day_screen.dart` | Session summary with stats and notes |
| Image Detail Screen | `image_detail_screen.dart` | Full image details view |

#### Admin Screens
| Screen | File | Purpose |
|--------|------|---------|
| Admin Shell | `admin_shell.dart` | Bottom navigation wrapper (5 tabs) |
| Dashboard Screen | `dashboard_screen.dart` | Employee overview with search, stats, employee cards |
| Analytics Screen | `analytics_screen.dart` | Employee performance breakdown with period selection |
| Tasks Screen | `tasks_screen.dart` | Task management with filtering |
| Create Task Screen | `create_task_screen.dart` | Task creation form with assignment options |
| Groups Screen | `groups_screen.dart` | Team/group management |
| Create Group Screen | `create_group_screen.dart` | Group creation form |
| Edit Group Screen | `edit_group_screen.dart` | Group editing with member management |
| Employee Detail Screen | `employee_detail_screen.dart` | Individual employee details |
| Export Data Screen | `export_data_screen.dart` | Data export functionality |
| Images Screen | `images_screen.dart` | All captured images management |

### 1.3 Data Entities Identified

| Entity | Description | Inferred From |
|--------|-------------|---------------|
| **User** | Employee/Team Lead/Admin profiles | Profile screen, dashboard, auth flows |
| **Session** | Work session with start/end times | Home screen, end of day screen |
| **Photo** | Geotagged images with metadata | Camera screen, gallery screen |
| **Task** | Assigned tasks and follow-ups | Todo screen, tasks screen |
| **Group** | Teams/zones with members | Groups screen |
| **LocationLog** | GPS checkpoints during session | History screen timeline |
| **DailySummary** | Aggregated daily statistics | History screen, analytics |
| **ActivityLog** | Real-time activity events | Analytics screen expanded logs |

### 1.4 Real-time vs Non-Real-time Requirements

| Feature | Type | Justification |
|---------|------|---------------|
| Employee location tracking | **Real-time** | Admin dashboard shows live locations |
| Session status (active/break/offline) | **Real-time** | Dashboard needs instant status updates |
| Task completion status | Near real-time | Admin needs timely updates |
| Photo uploads | Non-real-time | Can be batched/queued |
| Analytics/Reports | Non-real-time | Aggregated data, periodic refresh |
| History logs | Non-real-time | Historical data, no urgency |

### 1.5 Authentication Flows

```
Employee/Team Lead Flow:
Phone Number -> OTP Verification -> Role Selection -> Main App

Enterprise Admin Flow:
Email + Password -> Admin Dashboard

Post-Auth Routing:
- role == 'employee' -> EmployeeShell(isTeamLead: false)
- role == 'team_lead' -> EmployeeShell(isTeamLead: true)
- role == 'admin' -> AdminShell
```

---

## 2. Firebase Architecture Design

### 2.1 Firebase Services Stack

```
+------------------------------------------------------------------+
|                        FIREBASE PROJECT                           |
+------------------------------------------------------------------+
|                                                                    |
|  +------------------+    +------------------+    +---------------+ |
|  | Authentication   |    | Cloud Firestore  |    | Realtime DB   | |
|  | - Phone (OTP)    |    | - Primary DB     |    | - Live        | |
|  | - Email/Password |    | - Structured     |    |   Location    | |
|  | - Custom Claims  |    |   Data           |    | - Presence    | |
|  +------------------+    +------------------+    +---------------+ |
|                                                                    |
|  +------------------+    +------------------+    +---------------+ |
|  | Cloud Storage    |    | Cloud Functions  |    | FCM           | |
|  | - Photos         |    | - Triggers       |    | - Push        | |
|  | - Exports        |    | - HTTPS APIs     |    |   Notifs      | |
|  | - Reports        |    | - Scheduled Jobs |    | - Topics      | |
|  +------------------+    +------------------+    +---------------+ |
|                                                                    |
|  +------------------+    +------------------+                      |
|  | Analytics        |    | Crashlytics      |                      |
|  | - Events         |    | - Error Tracking |                      |
|  | - User Props     |    | - Performance    |                      |
|  +------------------+    +------------------+                      |
|                                                                    |
+------------------------------------------------------------------+
```

### 2.2 Database Choice: Firestore vs Realtime Database

| Use Case | Database | Justification |
|----------|----------|---------------|
| User profiles | **Firestore** | Complex queries, structured data |
| Sessions | **Firestore** | Rich queries, aggregations |
| Tasks | **Firestore** | Filtering, sorting, relationships |
| Groups | **Firestore** | Nested data, member lists |
| Photos metadata | **Firestore** | Complex queries by date/location |
| History & Summaries | **Firestore** | Aggregation queries |
| **Live Location** | **Realtime DB** | Low-latency real-time sync |
| **Presence Status** | **Realtime DB** | Online/offline detection |
| **Active Session State** | **Realtime DB** | Instant status updates |

### 2.3 Firestore Collection Structure

```
/enterprises/{enterpriseId}
    - name: string
    - createdAt: timestamp
    - settings: map

/users/{userId}
    - enterpriseId: string
    - name: string
    - phone: string
    - email: string (nullable)
    - role: 'employee' | 'team_lead' | 'admin'
    - groupId: string (nullable)
    - profileImageUrl: string (nullable)
    - fcmToken: string
    - createdAt: timestamp
    - updatedAt: timestamp

/sessions/{sessionId}
    - enterpriseId: string
    - employeeId: string
    - startTime: timestamp
    - endTime: timestamp (nullable)
    - status: 'active' | 'completed'
    - totalDuration: number (seconds)
    - totalDistance: number (km)
    - photosCount: number
    - tasksCompleted: number
    - notes: string
    - createdAt: timestamp

/sessions/{sessionId}/locations/{locationId}
    - latitude: number
    - longitude: number
    - address: string
    - timestamp: timestamp
    - type: 'check_in' | 'visit' | 'check_out'
    - title: string

/photos/{photoId}
    - enterpriseId: string
    - employeeId: string
    - sessionId: string
    - imageUrl: string
    - thumbnailUrl: string
    - timestamp: timestamp
    - location: string
    - latitude: number
    - longitude: number
    - geotagData: map { date, time, coordinates }
    - createdAt: timestamp

/tasks/{taskId}
    - enterpriseId: string
    - title: string
    - description: string
    - type: 'task' | 'followup'
    - priority: 'high' | 'medium' | 'low'
    - status: 'pending' | 'completed'
    - assignedTo: string (userId)
    - assignedBy: string (userId)
    - groupId: string (nullable)
    - dueDate: timestamp
    - contactType: string (nullable, for followups)
    - contactPhone: string (nullable)
    - completedAt: timestamp (nullable)
    - sendNotification: boolean
    - createdAt: timestamp
    - updatedAt: timestamp

/groups/{groupId}
    - enterpriseId: string
    - name: string
    - leadId: string (userId)
    - color: string (hex)
    - memberIds: array<string>
    - createdAt: timestamp
    - updatedAt: timestamp

/dailySummaries/{summaryId}
    - enterpriseId: string
    - employeeId: string
    - date: timestamp (start of day)
    - totalDuration: number (seconds)
    - totalDistance: number (km)
    - photosCount: number
    - tasksCompleted: number
    - locationsVisited: array<string>
    - sessionIds: array<string>

/activityLogs/{logId}
    - enterpriseId: string
    - employeeId: string
    - type: 'location_update' | 'task_started' | 'task_completed' | 'photo_captured' | 'session_started' | 'session_ended' | 'break'
    - title: string
    - detail: string
    - timestamp: timestamp
    - metadata: map
```

### 2.4 Realtime Database Structure

```json
{
  "presence": {
    "{enterpriseId}": {
      "{userId}": {
        "status": "active|break|offline",
        "lastSeen": 1707321600000,
        "currentSessionId": "session123"
      }
    }
  },
  "liveLocations": {
    "{enterpriseId}": {
      "{userId}": {
        "latitude": 17.4065,
        "longitude": 78.4842,
        "address": "Hitech City, Hyderabad",
        "updatedAt": 1707321600000,
        "accuracy": 10
      }
    }
  },
  "activeStats": {
    "{enterpriseId}": {
      "{userId}": {
        "sessionDuration": 27000,
        "distance": 12.4,
        "photosToday": 5,
        "tasksToday": 2
      }
    }
  }
}
```

### 2.5 Firebase Storage Structure

```
/enterprises/{enterpriseId}/
    /photos/{userId}/{date}/{photoId}.jpg
    /photos/{userId}/{date}/{photoId}_thumb.jpg
    /exports/{exportId}.csv
    /reports/{reportId}.pdf
    /profiles/{userId}/avatar.jpg
```

### 2.6 Cloud Functions Architecture

```
+------------------------------------------------------------------+
|                      CLOUD FUNCTIONS                              |
+------------------------------------------------------------------+
|                                                                    |
|  TRIGGERS:                                                         |
|  +------------------------+    +-------------------------------+   |
|  | onUserCreate           |    | onSessionComplete             |   |
|  | - Initialize user      |    | - Calculate stats             |   |
|  | - Set custom claims    |    | - Update daily summary        |   |
|  +------------------------+    +-------------------------------+   |
|                                                                    |
|  +------------------------+    +-------------------------------+   |
|  | onPhotoUpload          |    | onTaskAssigned                |   |
|  | - Generate thumbnail   |    | - Send push notification      |   |
|  | - Extract EXIF         |    | - Log activity                |   |
|  +------------------------+    +-------------------------------+   |
|                                                                    |
|  HTTPS CALLABLE:                                                   |
|  +------------------------+    +-------------------------------+   |
|  | verifyOTP              |    | createTask                    |   |
|  | registerUser           |    | assignTask                    |   |
|  | updateProfile          |    | completeTask                  |   |
|  +------------------------+    +-------------------------------+   |
|                                                                    |
|  +------------------------+    +-------------------------------+   |
|  | startSession           |    | getAnalytics                  |   |
|  | endSession             |    | exportReport                  |   |
|  | updateLocation         |    | getEmployeeDetails            |   |
|  +------------------------+    +-------------------------------+   |
|                                                                    |
|  SCHEDULED:                                                        |
|  +------------------------+    +-------------------------------+   |
|  | dailySummaryAggregator |    | cleanupOldExports             |   |
|  | - Runs at 11:59 PM     |    | - Runs weekly                 |   |
|  +------------------------+    +-------------------------------+   |
|                                                                    |
+------------------------------------------------------------------+
```

---

## 3. Data Models

### 3.1 User Model

```typescript
interface User {
  // Primary Key
  id: string;                    // Firebase Auth UID

  // Profile
  name: string;                  // "Rahul Kumar"
  phone: string;                 // "+91 98765 43210"
  email?: string;                // "admin@company.com" (admins only)
  profileImageUrl?: string;      // Storage URL

  // Organization
  enterpriseId: string;          // Parent enterprise
  role: 'employee' | 'team_lead' | 'admin';
  groupId?: string;              // Assigned group/zone

  // Device
  fcmToken?: string;             // Push notification token

  // Metadata
  createdAt: Timestamp;
  updatedAt: Timestamp;
}
```

**Read Pattern:** Frequent reads by admin for dashboard
**Write Pattern:** Infrequent (profile updates)
**Expected Growth:** 10-10,000 users per enterprise
**Indexes Required:**
- `enterpriseId` + `role`
- `enterpriseId` + `groupId`

---

### 3.2 Session Model

```typescript
interface Session {
  // Primary Key
  id: string;                    // Auto-generated

  // Relationships
  enterpriseId: string;
  employeeId: string;

  // Session Data
  startTime: Timestamp;
  endTime?: Timestamp;           // Null if active
  status: 'active' | 'completed';

  // Statistics (calculated)
  totalDuration: number;         // Seconds
  totalDistance: number;         // Kilometers
  photosCount: number;
  tasksCompleted: number;

  // User Input
  notes?: string;                // End of day notes

  // Metadata
  createdAt: Timestamp;
}

interface SessionLocation {
  // Subcollection: /sessions/{sessionId}/locations/{locationId}
  id: string;
  latitude: number;
  longitude: number;
  address: string;
  timestamp: Timestamp;
  type: 'check_in' | 'visit' | 'check_out';
  title: string;                 // "Client Visit: Site 4B"
}
```

**Read Pattern:** High reads for active sessions, history queries
**Write Pattern:** Frequent updates during active session
**Expected Growth:** 1-3 sessions per employee per day
**Indexes Required:**
- `employeeId` + `startTime` (DESC)
- `enterpriseId` + `status`
- `employeeId` + `status`

---

### 3.3 Photo Model

```typescript
interface Photo {
  // Primary Key
  id: string;                    // Auto-generated

  // Relationships
  enterpriseId: string;
  employeeId: string;
  sessionId: string;

  // Storage
  imageUrl: string;              // Full resolution URL
  thumbnailUrl: string;          // 200x200 thumbnail URL

  // Geolocation
  location: string;              // "Rajendra Nagar"
  latitude: number;              // 17.4065
  longitude: number;             // 78.4842

  // Watermark Data (embedded in image)
  geotagData: {
    date: string;                // "04 Feb 2026"
    time: string;                // "14:32:15 PM"
    coordinates: string;         // "Lat: 17.4065 N | Long: 78.4842 E"
  };

  // Metadata
  timestamp: Timestamp;
  createdAt: Timestamp;
}
```

**Read Pattern:** Gallery queries by date, admin image viewing
**Write Pattern:** Bursts during active session
**Expected Growth:** 5-50 photos per employee per day
**Indexes Required:**
- `employeeId` + `timestamp` (DESC)
- `enterpriseId` + `timestamp` (DESC)
- `sessionId`

---

### 3.4 Task Model

```typescript
interface Task {
  // Primary Key
  id: string;                    // Auto-generated

  // Relationships
  enterpriseId: string;
  assignedTo: string;            // Employee userId
  assignedBy: string;            // Admin userId
  groupId?: string;              // For group assignments

  // Task Details
  title: string;                 // "Visit ABC Distributor"
  description?: string;
  type: 'task' | 'followup';
  priority: 'high' | 'medium' | 'low';
  status: 'pending' | 'completed';

  // Follow-up specific
  contactType?: string;          // "Farmer"
  contactPhone?: string;         // "+1 (555) 012-3456"

  // Timing
  dueDate: Timestamp;
  completedAt?: Timestamp;

  // Options
  sendNotification: boolean;

  // Metadata
  createdAt: Timestamp;
  updatedAt: Timestamp;
}
```

**Read Pattern:** Employee todo list, admin task management
**Write Pattern:** Moderate (create, status updates)
**Expected Growth:** 5-20 tasks per employee per week
**Indexes Required:**
- `assignedTo` + `status` + `type`
- `enterpriseId` + `status`
- `assignedTo` + `dueDate`

---

### 3.5 Group Model

```typescript
interface Group {
  // Primary Key
  id: string;                    // Auto-generated

  // Relationships
  enterpriseId: string;
  leadId: string;                // Team lead userId

  // Group Details
  name: string;                  // "North Zone"
  color: string;                 // "#4F46E5" (hex color)
  memberIds: string[];           // Array of userIds

  // Metadata
  createdAt: Timestamp;
  updatedAt: Timestamp;
}
```

**Read Pattern:** Admin group management, employee group info
**Write Pattern:** Infrequent (group management)
**Expected Growth:** 5-50 groups per enterprise
**Indexes Required:**
- `enterpriseId`
- `leadId`

---

### 3.6 Daily Summary Model

```typescript
interface DailySummary {
  // Primary Key (composite)
  id: string;                    // "{employeeId}_{YYYY-MM-DD}"

  // Relationships
  enterpriseId: string;
  employeeId: string;

  // Date
  date: Timestamp;               // Start of day (00:00:00)

  // Aggregated Stats
  totalDuration: number;         // Seconds
  totalDistance: number;         // Kilometers
  photosCount: number;
  tasksCompleted: number;
  locationsVisited: string[];    // Location names
  sessionIds: string[];          // Related sessions

  // Status
  isOffDuty: boolean;
}
```

**Read Pattern:** History screen, analytics queries
**Write Pattern:** Once per day (end of day or scheduled function)
**Expected Growth:** 1 per employee per day
**Indexes Required:**
- `employeeId` + `date` (DESC)
- `enterpriseId` + `date` (DESC)

---

### 3.7 Activity Log Model

```typescript
interface ActivityLog {
  // Primary Key
  id: string;                    // Auto-generated

  // Relationships
  enterpriseId: string;
  employeeId: string;
  sessionId?: string;

  // Activity
  type: 'location_update' | 'task_started' | 'task_completed' |
        'photo_captured' | 'session_started' | 'session_ended' | 'break';
  title: string;                 // "Location Update"
  detail: string;                // "Checked in at Sector 45, Gurgaon"

  // Additional Data
  metadata?: {
    taskId?: string;
    photoId?: string;
    latitude?: number;
    longitude?: number;
  };

  // Timing
  timestamp: Timestamp;
}
```

**Read Pattern:** Analytics expanded logs
**Write Pattern:** High frequency during active sessions
**Expected Growth:** 20-100 logs per employee per day
**Indexes Required:**
- `employeeId` + `timestamp` (DESC)
- `enterpriseId` + `timestamp` (DESC)

---

## 4. API & Function Flow

### 4.1 Authentication APIs

| Function | Type | Description | Input | Output |
|----------|------|-------------|-------|--------|
| `sendOTP` | HTTPS Callable | Send OTP to phone | `{ phone, role }` | `{ success, verificationId }` |
| `verifyOTP` | HTTPS Callable | Verify OTP code | `{ verificationId, code }` | `{ success, token, isNewUser }` |
| `registerUser` | HTTPS Callable | Create new user | `{ name, phone, role, enterpriseId }` | `{ userId }` |
| `loginEnterprise` | Native Firebase Auth | Email/password login | `{ email, password }` | Auth token |
| `logout` | Client-side | Sign out | - | - |

### 4.2 Session APIs

| Function | Type | Description | Input | Output |
|----------|------|-------------|-------|--------|
| `startSession` | HTTPS Callable | Begin work session | `{ employeeId }` | `{ sessionId }` |
| `updateLocation` | HTTPS Callable | Log location point | `{ sessionId, lat, lng, address }` | `{ success }` |
| `endSession` | HTTPS Callable | End work session | `{ sessionId, notes }` | `{ summary }` |
| `getActiveSession` | HTTPS Callable | Get current session | `{ employeeId }` | `{ session }` or null |
| `getSessionHistory` | Client Query | Fetch session history | Firestore query | Sessions list |

### 4.3 Photo APIs

| Function | Type | Description | Input | Output |
|----------|------|-------------|-------|--------|
| `uploadPhoto` | Client + Storage | Upload geotagged photo | File + metadata | `{ photoId, url }` |
| `onPhotoUpload` | Storage Trigger | Generate thumbnail | Storage event | Thumbnail created |
| `getPhotos` | Client Query | Fetch photos by date | Firestore query | Photos list |
| `deletePhoto` | HTTPS Callable | Remove photo | `{ photoId }` | `{ success }` |

### 4.4 Task APIs

| Function | Type | Description | Input | Output |
|----------|------|-------------|-------|--------|
| `createTask` | HTTPS Callable | Create new task | Task data | `{ taskId }` |
| `assignTask` | HTTPS Callable | Assign to employee | `{ taskId, employeeId }` | `{ success }` |
| `completeTask` | HTTPS Callable | Mark as complete | `{ taskId }` | `{ success }` |
| `getTasks` | Client Query | Fetch tasks | Firestore query | Tasks list |
| `onTaskAssigned` | Firestore Trigger | Send notification | Create event | Push sent |

### 4.5 Group APIs

| Function | Type | Description | Input | Output |
|----------|------|-------------|-------|--------|
| `createGroup` | HTTPS Callable | Create new group | Group data | `{ groupId }` |
| `updateGroup` | HTTPS Callable | Update group details | `{ groupId, data }` | `{ success }` |
| `addMember` | HTTPS Callable | Add member to group | `{ groupId, userId }` | `{ success }` |
| `removeMember` | HTTPS Callable | Remove member | `{ groupId, userId }` | `{ success }` |
| `getGroups` | Client Query | Fetch groups | Firestore query | Groups list |

### 4.6 Analytics APIs

| Function | Type | Description | Input | Output |
|----------|------|-------------|-------|--------|
| `getAnalytics` | HTTPS Callable | Get analytics data | `{ enterpriseId, period }` | Analytics summary |
| `getEmployeeStats` | HTTPS Callable | Individual stats | `{ employeeId, period }` | Employee stats |
| `exportReport` | HTTPS Callable | Generate export | `{ type, period }` | `{ downloadUrl }` |
| `getDailySummary` | Client Query | Fetch daily summaries | Firestore query | Summaries list |

### 4.7 UI Action to Firebase Operation Mapping

```
+------------------------------------------------------------------+
|  UI ACTION                    |  FIREBASE OPERATION              |
+------------------------------------------------------------------+
| Enter phone, select role      | Call sendOTP()                   |
| Enter OTP, tap Verify         | Call verifyOTP()                 |
| Tap "Start Session"           | Call startSession()              |
|                               | Update RTDB presence             |
|                               | Start location updates           |
+------------------------------------------------------------------+
| Tap camera shutter            | Upload to Storage                |
|                               | Create Firestore photo doc       |
|                               | Trigger thumbnail generation     |
+------------------------------------------------------------------+
| Tap "End Session"             | Call endSession()                |
|                               | Calculate session stats          |
|                               | Update RTDB presence offline     |
|                               | Create/update daily summary      |
+------------------------------------------------------------------+
| Admin creates task            | Call createTask()                |
|                               | Trigger push notification        |
+------------------------------------------------------------------+
| Employee completes task       | Call completeTask()              |
|                               | Log activity                     |
|                               | Update task status               |
+------------------------------------------------------------------+
| Admin views dashboard         | Query RTDB for live locations    |
|                               | Query Firestore for user data    |
|                               | Stream presence updates          |
+------------------------------------------------------------------+
| View analytics                | Call getAnalytics()              |
|                               | Query daily summaries            |
|                               | Aggregate stats                  |
+------------------------------------------------------------------+
| Export CSV                    | Call exportReport()              |
|                               | Generate CSV in Cloud Function   |
|                               | Upload to Storage                |
|                               | Return download URL              |
+------------------------------------------------------------------+
```

---

## 5. Security & Roles

### 5.1 Role Definitions

| Role | Description | Permissions |
|------|-------------|-------------|
| **employee** | Field worker | Own data only (sessions, photos, tasks) |
| **team_lead** | Team supervisor | Own data + team members + create tasks for team |
| **admin** | Enterprise administrator | All data within enterprise |

### 5.2 Custom Claims Setup

```typescript
// Set during user creation
admin.auth().setCustomUserClaims(uid, {
  role: 'employee' | 'team_lead' | 'admin',
  enterpriseId: 'enterprise123',
  groupId: 'group456' // optional
});
```

### 5.3 Firestore Security Rules

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    // Helper functions
    function isAuthenticated() {
      return request.auth != null;
    }

    function getUserRole() {
      return request.auth.token.role;
    }

    function getEnterpriseId() {
      return request.auth.token.enterpriseId;
    }

    function isAdmin() {
      return getUserRole() == 'admin';
    }

    function isTeamLead() {
      return getUserRole() == 'team_lead';
    }

    function isEmployee() {
      return getUserRole() == 'employee';
    }

    function belongsToEnterprise(enterpriseId) {
      return getEnterpriseId() == enterpriseId;
    }

    function isOwner(userId) {
      return request.auth.uid == userId;
    }

    // Users collection
    match /users/{userId} {
      // Read: Own profile OR admin in same enterprise
      allow read: if isAuthenticated() &&
        (isOwner(userId) ||
         (isAdmin() && belongsToEnterprise(resource.data.enterpriseId)));

      // Create: Admin only
      allow create: if isAuthenticated() && isAdmin();

      // Update: Own profile OR admin
      allow update: if isAuthenticated() &&
        (isOwner(userId) ||
         (isAdmin() && belongsToEnterprise(resource.data.enterpriseId)));

      // Delete: Admin only
      allow delete: if isAuthenticated() && isAdmin();
    }

    // Sessions collection
    match /sessions/{sessionId} {
      allow read: if isAuthenticated() &&
        (isOwner(resource.data.employeeId) ||
         isAdmin() && belongsToEnterprise(resource.data.enterpriseId));

      allow create: if isAuthenticated() &&
        isOwner(request.resource.data.employeeId);

      allow update: if isAuthenticated() &&
        isOwner(resource.data.employeeId);

      allow delete: if false; // Never delete sessions

      // Session locations subcollection
      match /locations/{locationId} {
        allow read, write: if isAuthenticated() &&
          isOwner(get(/databases/$(database)/documents/sessions/$(sessionId)).data.employeeId);
      }
    }

    // Photos collection
    match /photos/{photoId} {
      allow read: if isAuthenticated() &&
        (isOwner(resource.data.employeeId) ||
         isAdmin() && belongsToEnterprise(resource.data.enterpriseId));

      allow create: if isAuthenticated() &&
        isOwner(request.resource.data.employeeId);

      allow delete: if isAuthenticated() &&
        (isOwner(resource.data.employeeId) || isAdmin());
    }

    // Tasks collection
    match /tasks/{taskId} {
      allow read: if isAuthenticated() &&
        (isOwner(resource.data.assignedTo) ||
         isAdmin() && belongsToEnterprise(resource.data.enterpriseId) ||
         isTeamLead() && belongsToEnterprise(resource.data.enterpriseId));

      allow create: if isAuthenticated() &&
        (isAdmin() || isTeamLead()) &&
        belongsToEnterprise(request.resource.data.enterpriseId);

      allow update: if isAuthenticated() &&
        (isOwner(resource.data.assignedTo) ||
         isAdmin() && belongsToEnterprise(resource.data.enterpriseId));

      allow delete: if isAuthenticated() &&
        isAdmin() && belongsToEnterprise(resource.data.enterpriseId);
    }

    // Groups collection
    match /groups/{groupId} {
      allow read: if isAuthenticated() &&
        belongsToEnterprise(resource.data.enterpriseId);

      allow create, update, delete: if isAuthenticated() &&
        isAdmin() && belongsToEnterprise(resource.data.enterpriseId);
    }

    // Daily Summaries
    match /dailySummaries/{summaryId} {
      allow read: if isAuthenticated() &&
        (isOwner(resource.data.employeeId) ||
         isAdmin() && belongsToEnterprise(resource.data.enterpriseId));

      // Only Cloud Functions can write
      allow write: if false;
    }

    // Activity Logs
    match /activityLogs/{logId} {
      allow read: if isAuthenticated() &&
        (isOwner(resource.data.employeeId) ||
         isAdmin() && belongsToEnterprise(resource.data.enterpriseId));

      allow create: if isAuthenticated() &&
        isOwner(request.resource.data.employeeId);
    }
  }
}
```

### 5.4 Realtime Database Security Rules

```json
{
  "rules": {
    "presence": {
      "$enterpriseId": {
        ".read": "auth != null && auth.token.enterpriseId == $enterpriseId",
        "$userId": {
          ".write": "auth != null && auth.uid == $userId"
        }
      }
    },
    "liveLocations": {
      "$enterpriseId": {
        ".read": "auth != null && auth.token.enterpriseId == $enterpriseId && auth.token.role == 'admin'",
        "$userId": {
          ".read": "auth != null && (auth.uid == $userId || auth.token.role == 'admin')",
          ".write": "auth != null && auth.uid == $userId"
        }
      }
    },
    "activeStats": {
      "$enterpriseId": {
        ".read": "auth != null && auth.token.enterpriseId == $enterpriseId",
        "$userId": {
          ".write": "auth != null && auth.uid == $userId"
        }
      }
    }
  }
}
```

### 5.5 Storage Security Rules

```javascript
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {

    function isAuthenticated() {
      return request.auth != null;
    }

    function isAdmin() {
      return request.auth.token.role == 'admin';
    }

    function belongsToEnterprise(enterpriseId) {
      return request.auth.token.enterpriseId == enterpriseId;
    }

    function isOwner(userId) {
      return request.auth.uid == userId;
    }

    // Enterprise photos
    match /enterprises/{enterpriseId}/photos/{userId}/{allPaths=**} {
      allow read: if isAuthenticated() &&
        (isOwner(userId) ||
         isAdmin() && belongsToEnterprise(enterpriseId));

      allow write: if isAuthenticated() &&
        isOwner(userId) &&
        belongsToEnterprise(enterpriseId) &&
        request.resource.size < 10 * 1024 * 1024 && // 10MB limit
        request.resource.contentType.matches('image/.*');
    }

    // Profile images
    match /enterprises/{enterpriseId}/profiles/{userId}/{fileName} {
      allow read: if isAuthenticated() && belongsToEnterprise(enterpriseId);
      allow write: if isAuthenticated() && isOwner(userId);
    }

    // Exports (admin only)
    match /enterprises/{enterpriseId}/exports/{fileName} {
      allow read: if isAuthenticated() && isAdmin() && belongsToEnterprise(enterpriseId);
      allow write: if false; // Only Cloud Functions
    }
  }
}
```

### 5.6 Protection Against Abuse

| Threat | Mitigation |
|--------|------------|
| Unauthorized access | Role-based security rules, custom claims |
| Data leakage | Enterprise-scoped queries, rule enforcement |
| Invalid writes | Schema validation in Cloud Functions |
| Rate limiting | Firebase App Check, Cloud Functions quotas |
| Large file uploads | Storage size limits (10MB) |
| Fake locations | Server-side location validation (Cloud Functions) |
| Session manipulation | Server-side session management |

---

## 6. Analytics & Logging

### 6.1 Firebase Analytics Events

| Event Name | Parameters | When Triggered |
|------------|------------|----------------|
| `login` | `method`, `role` | User logs in |
| `session_start` | `employee_id` | Work session started |
| `session_end` | `duration`, `distance`, `photos`, `tasks` | Work session ended |
| `photo_captured` | `location`, `session_id` | Photo taken |
| `task_completed` | `task_id`, `task_type` | Task marked complete |
| `task_created` | `task_type`, `priority` | Admin creates task |
| `group_created` | `member_count` | Admin creates group |
| `export_generated` | `export_type`, `period` | Report exported |
| `screen_view` | `screen_name`, `screen_class` | Screen navigation |

### 6.2 User Properties

| Property | Type | Description |
|----------|------|-------------|
| `user_role` | string | employee/team_lead/admin |
| `enterprise_id` | string | Organization identifier |
| `group_id` | string | Team/zone assignment |
| `account_created` | timestamp | Registration date |

### 6.3 Error Monitoring (Crashlytics)

```dart
// Capture non-fatal errors
FirebaseCrashlytics.instance.recordError(
  exception,
  stackTrace,
  reason: 'Location update failed',
  fatal: false,
);

// Set user context
FirebaseCrashlytics.instance.setUserIdentifier(userId);
FirebaseCrashlytics.instance.setCustomKey('enterprise_id', enterpriseId);
FirebaseCrashlytics.instance.setCustomKey('role', userRole);
```

### 6.4 Performance Monitoring

| Trace | What to Measure |
|-------|-----------------|
| `session_start_time` | Time to start a session |
| `photo_upload_time` | Photo upload latency |
| `dashboard_load_time` | Admin dashboard load time |
| `location_update_time` | Location sync latency |
| `analytics_fetch_time` | Analytics data load time |

### 6.5 Cloud Logging Strategy

```typescript
// Cloud Function logging
import * as functions from 'firebase-functions';

functions.logger.info('Session started', {
  userId: context.auth.uid,
  sessionId: sessionId,
  timestamp: new Date().toISOString()
});

functions.logger.error('Photo upload failed', {
  userId: context.auth.uid,
  error: error.message,
  photoId: photoId
});
```

---

## 7. Implementation Plan

### Phase 1: Core Setup (Week 1)

**Objective:** Firebase project configuration and base structure

| Task | Description | Deliverable |
|------|-------------|-------------|
| 1.1 | Create Firebase project | Project console access |
| 1.2 | Enable Firebase services | Auth, Firestore, RTDB, Storage, Functions |
| 1.3 | Configure Flutter SDK | `google-services.json`, `GoogleService-Info.plist` |
| 1.4 | Setup development environment | Firebase CLI, emulators |
| 1.5 | Create Firestore indexes | Index configuration file |
| 1.6 | Deploy initial security rules | Rules deployed |

---

### Phase 2: Authentication & User System (Week 2)

**Objective:** Complete authentication flow with role management

| Task | Description | Deliverable |
|------|-------------|-------------|
| 2.1 | Enable Phone authentication | Phone auth working |
| 2.2 | Enable Email/Password auth | Admin auth working |
| 2.3 | Implement `sendOTP` function | Cloud function deployed |
| 2.4 | Implement `verifyOTP` function | Cloud function deployed |
| 2.5 | Implement `registerUser` function | Cloud function deployed |
| 2.6 | Setup custom claims | Role claims working |
| 2.7 | Create Flutter auth service | `AuthService` class |
| 2.8 | Integrate auth with UI | Login flows working |

---

### Phase 3: Database & Core APIs (Week 3-4)

**Objective:** Firestore/RTDB structure and core CRUD operations

| Task | Description | Deliverable |
|------|-------------|-------------|
| 3.1 | Create Firestore collections | Collections created |
| 3.2 | Create RTDB structure | RTDB nodes created |
| 3.3 | Implement User CRUD | User management working |
| 3.4 | Implement Session APIs | Session start/end working |
| 3.5 | Implement Location tracking | Location updates working |
| 3.6 | Implement Task CRUD | Task management working |
| 3.7 | Implement Group CRUD | Group management working |
| 3.8 | Implement Photo upload | Photo upload working |
| 3.9 | Create Flutter repository layer | Repository classes |
| 3.10 | Integrate with UI screens | Data binding complete |

---

### Phase 4: Cloud Functions (Week 5)

**Objective:** Server-side logic and triggers

| Task | Description | Deliverable |
|------|-------------|-------------|
| 4.1 | Setup Cloud Functions project | Project structure |
| 4.2 | Implement `onUserCreate` trigger | Custom claims set |
| 4.3 | Implement `onSessionComplete` trigger | Stats calculated |
| 4.4 | Implement `onPhotoUpload` trigger | Thumbnails generated |
| 4.5 | Implement `onTaskAssigned` trigger | Notifications sent |
| 4.6 | Implement scheduled daily aggregator | Summaries created |
| 4.7 | Implement export function | CSV generation |
| 4.8 | Deploy all functions | Functions live |

---

### Phase 5: Push Notifications (Week 6)

**Objective:** FCM integration for real-time alerts

| Task | Description | Deliverable |
|------|-------------|-------------|
| 5.1 | Configure FCM in Firebase console | FCM enabled |
| 5.2 | Setup APNs for iOS | iOS notifications working |
| 5.3 | Implement FCM token management | Token storage |
| 5.4 | Create notification topics | Topic subscriptions |
| 5.5 | Implement task notification logic | Task alerts working |
| 5.6 | Implement session reminders | Reminder notifications |
| 5.7 | Add notification handlers in app | Foreground/background handling |

---

### Phase 6: Security Rules (Week 7)

**Objective:** Production-ready security configuration

| Task | Description | Deliverable |
|------|-------------|-------------|
| 6.1 | Write Firestore security rules | Rules file |
| 6.2 | Write RTDB security rules | Rules file |
| 6.3 | Write Storage security rules | Rules file |
| 6.4 | Test all rule scenarios | Test results |
| 6.5 | Setup Firebase App Check | App Check enabled |
| 6.6 | Configure rate limiting | Abuse prevention |
| 6.7 | Security audit | Audit report |

---

### Phase 7: Testing & Optimization (Week 8)

**Objective:** Production readiness

| Task | Description | Deliverable |
|------|-------------|-------------|
| 7.1 | Unit test Cloud Functions | Test coverage |
| 7.2 | Integration testing | E2E tests |
| 7.3 | Performance testing | Load test results |
| 7.4 | Optimize Firestore queries | Query improvements |
| 7.5 | Implement offline support | Offline mode working |
| 7.6 | Configure caching strategies | Cache policies |
| 7.7 | Setup monitoring alerts | Alert rules |
| 7.8 | Production deployment | Live system |

---

## 8. Task Plan (Engineering Ready)

### Priority Legend
- **P0 (Critical):** Must complete before next phase
- **P1 (High):** Core functionality
- **P2 (Medium):** Important but not blocking
- **P3 (Low):** Nice to have

---

### Phase 1: Core Setup

| # | Task | Description | Dependencies | Priority | Effort |
|---|------|-------------|--------------|----------|--------|
| 1.1 | Create Firebase Project | Setup new Firebase project in console | None | P0 | 1h |
| 1.2 | Enable Core Services | Enable Auth, Firestore, RTDB, Storage, Functions | 1.1 | P0 | 1h |
| 1.3 | Configure Android | Add `google-services.json`, update gradle | 1.1 | P0 | 2h |
| 1.4 | Configure iOS | Add `GoogleService-Info.plist`, update podfile | 1.1 | P0 | 2h |
| 1.5 | Setup Firebase CLI | Install CLI, authenticate, init project | 1.1 | P0 | 1h |
| 1.6 | Setup Emulators | Configure local emulators for dev | 1.5 | P1 | 2h |
| 1.7 | Create Index Definitions | Define Firestore composite indexes | 1.2 | P1 | 2h |
| 1.8 | Initial Security Rules | Deploy placeholder rules | 1.2 | P0 | 1h |

---

### Phase 2: Authentication

| # | Task | Description | Dependencies | Priority | Effort |
|---|------|-------------|--------------|----------|--------|
| 2.1 | Enable Phone Auth | Configure phone auth in console | 1.2 | P0 | 1h |
| 2.2 | Enable Email Auth | Configure email/password auth | 1.2 | P0 | 30m |
| 2.3 | Create `sendOTP` Function | Cloud function to initiate OTP | 1.5 | P0 | 4h |
| 2.4 | Create `verifyOTP` Function | Cloud function to verify OTP | 2.3 | P0 | 4h |
| 2.5 | Create `registerUser` Function | Create user with profile | 2.4 | P0 | 4h |
| 2.6 | Implement Custom Claims | Set role claims on user creation | 2.5 | P0 | 2h |
| 2.7 | Create `AuthService` Class | Flutter service for auth operations | 2.4 | P0 | 4h |
| 2.8 | Create `AuthProvider` | State management for auth | 2.7 | P0 | 3h |
| 2.9 | Integrate Welcome Screen | Connect to Firebase auth | 2.7 | P0 | 3h |
| 2.10 | Integrate OTP Screen | Connect to OTP verification | 2.9 | P0 | 3h |
| 2.11 | Integrate Enterprise Login | Connect email/password auth | 2.7 | P0 | 2h |
| 2.12 | Implement Role-Based Routing | Route to correct shell by role | 2.6 | P0 | 2h |
| 2.13 | Implement Logout | Clear auth state, navigate to login | 2.7 | P1 | 1h |
| 2.14 | Add Auth Persistence | Remember login state | 2.7 | P1 | 2h |

---

### Phase 3: Database & APIs

| # | Task | Description | Dependencies | Priority | Effort |
|---|------|-------------|--------------|----------|--------|
| 3.1 | Create Users Collection | Setup Firestore users structure | 2.5 | P0 | 2h |
| 3.2 | Create Sessions Collection | Setup Firestore sessions structure | 3.1 | P0 | 2h |
| 3.3 | Create Photos Collection | Setup Firestore photos structure | 3.1 | P0 | 2h |
| 3.4 | Create Tasks Collection | Setup Firestore tasks structure | 3.1 | P0 | 2h |
| 3.5 | Create Groups Collection | Setup Firestore groups structure | 3.1 | P0 | 2h |
| 3.6 | Create Daily Summaries Collection | Setup aggregation collection | 3.2 | P1 | 2h |
| 3.7 | Create Activity Logs Collection | Setup activity logging | 3.1 | P2 | 2h |
| 3.8 | Setup RTDB Presence | Real-time presence structure | 1.2 | P0 | 3h |
| 3.9 | Setup RTDB Live Locations | Real-time location structure | 3.8 | P0 | 3h |
| 3.10 | Create `UserRepository` | CRUD operations for users | 3.1 | P0 | 4h |
| 3.11 | Create `SessionRepository` | CRUD operations for sessions | 3.2 | P0 | 6h |
| 3.12 | Create `PhotoRepository` | CRUD operations for photos | 3.3 | P0 | 4h |
| 3.13 | Create `TaskRepository` | CRUD operations for tasks | 3.4 | P0 | 4h |
| 3.14 | Create `GroupRepository` | CRUD operations for groups | 3.5 | P0 | 4h |
| 3.15 | Create `LocationService` | Handle location updates | 3.9 | P0 | 6h |
| 3.16 | Implement `startSession` | Start work session logic | 3.11 | P0 | 4h |
| 3.17 | Implement `endSession` | End session with summary | 3.16 | P0 | 4h |
| 3.18 | Implement Photo Upload | Storage + Firestore integration | 3.12 | P0 | 6h |
| 3.19 | Integrate Home Screen | Session state, live stats | 3.16 | P0 | 4h |
| 3.20 | Integrate Camera Screen | Photo capture + upload | 3.18 | P0 | 4h |
| 3.21 | Integrate Gallery Screen | Photo listing | 3.12 | P0 | 3h |
| 3.22 | Integrate Todo Screen | Task listing, completion | 3.13 | P0 | 4h |
| 3.23 | Integrate History Screen | Session history, summaries | 3.11 | P0 | 4h |
| 3.24 | Integrate Dashboard Screen | Employee list, live status | 3.10, 3.8 | P0 | 6h |
| 3.25 | Integrate Analytics Screen | Stats, employee breakdown | 3.10 | P0 | 4h |
| 3.26 | Integrate Tasks Screen (Admin) | Task management | 3.13 | P0 | 4h |
| 3.27 | Integrate Groups Screen | Group management | 3.14 | P0 | 4h |
| 3.28 | Integrate Profile Screen | User profile display | 3.10 | P1 | 2h |

---

### Phase 4: Cloud Functions

| # | Task | Description | Dependencies | Priority | Effort |
|---|------|-------------|--------------|----------|--------|
| 4.1 | Setup Functions Project | Initialize TypeScript project | 1.5 | P0 | 2h |
| 4.2 | Create `onUserCreate` Trigger | Set custom claims on user creation | 4.1 | P0 | 3h |
| 4.3 | Create `onSessionComplete` Trigger | Calculate final session stats | 4.1 | P0 | 4h |
| 4.4 | Create `onPhotoUpload` Trigger | Generate thumbnail | 4.1 | P1 | 4h |
| 4.5 | Create `onTaskAssigned` Trigger | Send push notification | 4.1, 5.1 | P1 | 3h |
| 4.6 | Create Daily Summary Aggregator | Scheduled function (11:59 PM) | 4.1 | P1 | 4h |
| 4.7 | Create `exportReport` Function | Generate CSV export | 4.1 | P2 | 6h |
| 4.8 | Create `cleanupOldExports` | Weekly cleanup scheduled | 4.7 | P3 | 2h |
| 4.9 | Deploy Functions to Production | Deploy all functions | 4.2-4.8 | P0 | 2h |

---

### Phase 5: Push Notifications

| # | Task | Description | Dependencies | Priority | Effort |
|---|------|-------------|--------------|----------|--------|
| 5.1 | Configure FCM Console | Enable Cloud Messaging | 1.1 | P0 | 1h |
| 5.2 | Configure APNs (iOS) | Upload APNs key/certificate | 5.1 | P0 | 2h |
| 5.3 | Add FCM to Flutter | Install firebase_messaging package | 5.1 | P0 | 2h |
| 5.4 | Implement Token Management | Store FCM token in Firestore | 5.3, 3.1 | P0 | 3h |
| 5.5 | Implement Notification Handler | Handle foreground/background | 5.3 | P0 | 4h |
| 5.6 | Create Notification Topics | Admin, group-based topics | 5.4 | P1 | 2h |
| 5.7 | Test End-to-End Notifications | Verify all notification paths | 5.5, 4.5 | P0 | 3h |

---

### Phase 6: Security Rules

| # | Task | Description | Dependencies | Priority | Effort |
|---|------|-------------|--------------|----------|--------|
| 6.1 | Write Firestore Rules | Complete security rules | 3.1-3.7 | P0 | 6h |
| 6.2 | Write RTDB Rules | Presence/location rules | 3.8-3.9 | P0 | 3h |
| 6.3 | Write Storage Rules | Photo/export access rules | 3.18 | P0 | 3h |
| 6.4 | Create Rules Test Suite | Test security scenarios | 6.1-6.3 | P0 | 6h |
| 6.5 | Enable App Check | Prevent unauthorized access | 6.1-6.3 | P1 | 3h |
| 6.6 | Configure Function IAM | Least-privilege access | 4.9 | P1 | 2h |
| 6.7 | Security Audit | Review all access paths | 6.1-6.6 | P0 | 4h |

---

### Phase 7: Testing & Optimization

| # | Task | Description | Dependencies | Priority | Effort |
|---|------|-------------|--------------|----------|--------|
| 7.1 | Unit Test Cloud Functions | Jest test suite | 4.1-4.8 | P0 | 8h |
| 7.2 | Integration Test Auth Flow | Test login/logout | 2.7-2.14 | P0 | 4h |
| 7.3 | Integration Test Session Flow | Test start/end session | 3.16-3.17 | P0 | 4h |
| 7.4 | Load Test Dashboard | Simulate 100+ employees | 3.24 | P1 | 4h |
| 7.5 | Optimize Firestore Queries | Add missing indexes, pagination | 3.10-3.14 | P1 | 4h |
| 7.6 | Implement Offline Mode | Firestore persistence | All | P1 | 6h |
| 7.7 | Add Query Caching | Reduce redundant reads | 3.10-3.14 | P2 | 4h |
| 7.8 | Setup Cloud Monitoring | Alerts for errors/quotas | All | P1 | 3h |
| 7.9 | Performance Profiling | Identify bottlenecks | All | P1 | 4h |
| 7.10 | Production Deployment | Final deployment checklist | All | P0 | 4h |

---

## Appendix A: Cost Estimation

### Firestore Costs (per 100 employees, per month)

| Operation | Estimate | Cost |
|-----------|----------|------|
| Document reads | ~500,000/month | ~$0.18 |
| Document writes | ~100,000/month | ~$0.18 |
| Document deletes | ~1,000/month | ~$0.002 |
| Storage | ~1 GB | ~$0.18 |
| **Total Firestore** | | **~$0.55/month** |

### Storage Costs (per 100 employees, per month)

| Item | Estimate | Cost |
|------|----------|------|
| Photo storage | ~50 GB | ~$1.30 |
| Downloads | ~100 GB | ~$12 |
| **Total Storage** | | **~$13.30/month** |

### Cloud Functions (per 100 employees, per month)

| Resource | Estimate | Cost |
|----------|----------|------|
| Invocations | ~200,000 | Free tier |
| Compute time | ~50,000 GB-seconds | ~$2 |
| **Total Functions** | | **~$2/month** |

### **Estimated Total: ~$16/month for 100 employees**

---

## Appendix B: Index Configuration

```yaml
# firestore.indexes.json
{
  "indexes": [
    {
      "collectionGroup": "users",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "enterpriseId", "order": "ASCENDING" },
        { "fieldPath": "role", "order": "ASCENDING" }
      ]
    },
    {
      "collectionGroup": "sessions",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "employeeId", "order": "ASCENDING" },
        { "fieldPath": "startTime", "order": "DESCENDING" }
      ]
    },
    {
      "collectionGroup": "sessions",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "enterpriseId", "order": "ASCENDING" },
        { "fieldPath": "status", "order": "ASCENDING" }
      ]
    },
    {
      "collectionGroup": "photos",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "employeeId", "order": "ASCENDING" },
        { "fieldPath": "timestamp", "order": "DESCENDING" }
      ]
    },
    {
      "collectionGroup": "tasks",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "assignedTo", "order": "ASCENDING" },
        { "fieldPath": "status", "order": "ASCENDING" },
        { "fieldPath": "type", "order": "ASCENDING" }
      ]
    },
    {
      "collectionGroup": "dailySummaries",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "employeeId", "order": "ASCENDING" },
        { "fieldPath": "date", "order": "DESCENDING" }
      ]
    },
    {
      "collectionGroup": "activityLogs",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "employeeId", "order": "ASCENDING" },
        { "fieldPath": "timestamp", "order": "DESCENDING" }
      ]
    }
  ]
}
```

---

## Appendix C: Environment Configuration

### Development
```
FIREBASE_PROJECT_ID=izumi-dev
FIREBASE_REGION=asia-south1
USE_EMULATORS=true
```

### Staging
```
FIREBASE_PROJECT_ID=izumi-staging
FIREBASE_REGION=asia-south1
USE_EMULATORS=false
```

### Production
```
FIREBASE_PROJECT_ID=izumi-prod
FIREBASE_REGION=asia-south1
USE_EMULATORS=false
```

---

**Document End**

*This architecture document is implementation-ready and can be directly used by the development team to build the complete Firebase backend for the Izumi platform.*
