# Izumi - App UI Screens

Field Workforce Intelligence Platform built with Flutter.
Glassmorphism design system | GoRouter navigation | Provider state management

---

## Table of Contents

1. [Authentication Screens](#1-authentication-screens)
2. [Employee Screens](#2-employee-screens)
3. [Admin Screens](#3-admin-screens)
4. [Chat Screens](#4-chat-screens)
5. [Notifications](#5-notifications)
6. [Reusable Widgets](#6-reusable-widgets)
7. [Navigation Flows](#7-navigation-flows)

---

## 1. Authentication Screens

### 1.1 Welcome Screen

- **File:** `lib/screens/auth/welcome_screen.dart`
- **Class:** `WelcomeScreen`
- **Route:** `/`
- **Purpose:** Initial login screen with phone number entry and role selection

**Key UI Components:**
- Phone number input with country code (+91)
- Role selection (employee, team_lead, admin)
- Glassmorphism card layout
- Error handling for multi-device sessions

---

### 1.2 Enterprise Login Screen

- **File:** `lib/screens/auth/enterprise_login_screen.dart`
- **Class:** `EnterpriseLoginScreen`
- **Route:** `/enterprise-login`
- **Purpose:** Email/password login for enterprise admins

**Key UI Components:**
- Email input field
- Password input with visibility toggle
- Enterprise authentication flow
- Login button

---

### 1.3 OTP Screen

- **File:** `lib/screens/auth/otp_screen.dart`
- **Class:** `OtpScreen`
- **Route:** `/otp`
- **Purpose:** OTP verification after phone login

**Key UI Components:**
- 6-digit OTP input field with auto-submit
- 45-second resend timer
- Phone number display
- Role and name parameters

---

## 2. Employee Screens

### 2.1 Employee Shell (Navigation Container)

- **File:** `lib/screens/employee/employee_shell.dart`
- **Class:** `EmployeeShell`
- **Purpose:** Main navigation wrapper with bottom nav bar

**Bottom Nav Tabs (5):**
1. Home
2. Gallery
3. Tasks (Todo)
4. History
5. Chat

---

### 2.2 Home Screen

- **File:** `lib/screens/employee/home_screen.dart`
- **Class:** `HomeScreen`
- **Route:** `/employee/home`
- **Purpose:** Main dashboard showing IDLE or ACTIVE session state

**Key UI Components:**
- Start/End work session buttons
- Real-time location tracking indicator
- Session state management (IDLE/ACTIVE)
- Unread notifications indicator
- Task summary widgets
- Quick navigation to camera, profile, notifications

---

### 2.3 Gallery Screen

- **File:** `lib/screens/employee/gallery_screen.dart`
- **Class:** `GalleryScreen`
- **Route:** `/employee/gallery`
- **Purpose:** Personal photo gallery with search and date filtering

**Key UI Components:**
- Photo grid display with thumbnails
- Search bar (by location/metadata)
- Date filtering
- Upload status tracking
- Offline queue management indicator
- Tap to open photo detail

---

### 2.4 Todo/Tasks Screen

- **File:** `lib/screens/employee/todo_screen.dart`
- **Class:** `TodoScreen`
- **Route:** `/employee/tasks`
- **Purpose:** Task management with employee/team lead views

**Key UI Components:**
- Tabs: Tasks and Follow-ups
- Status filters (All, Pending, Completed)
- Task cards with priority indicators
- Due date tracking
- Team lead view: manage subordinate tasks
- Task creation button (team lead only)

---

### 2.5 History Screen

- **File:** `lib/screens/employee/history_screen.dart`
- **Class:** `HistoryScreen`
- **Route:** `/employee/history`
- **Purpose:** Work session logs and daily summaries

**Key UI Components:**
- Monthly calendar view with work summary
- Daily session timeline
- Session location logs
- Distance tracking per session
- Session duration display
- Expandable session details

---

### 2.6 Camera Screen

- **File:** `lib/screens/employee/camera_screen.dart`
- **Class:** `CameraScreen`
- **Route:** `/employee/camera`
- **Purpose:** Geotagged photo capture for field documentation

**Key UI Components:**
- Live camera preview
- Flash mode toggle
- Camera switch (front/back)
- GPS location tagging overlay
- Photo capture button with timestamp
- Permission handling dialogs

---

### 2.7 Preview Screen

- **File:** `lib/screens/employee/preview_screen.dart`
- **Class:** `PreviewScreen`
- **Route:** `/employee/camera/preview`
- **Purpose:** Photo preview with metadata entry form

**Key UI Components:**
- Full image preview
- Location display with GPS coordinates
- Timestamp
- Category selection (Distributor, Farmer, etc.)
- Customer type toggle (New, Existing)
- Name, phone, notes input fields
- Follow-up checkbox
- Upload to cloud or chat group buttons

---

### 2.8 Profile Screen

- **File:** `lib/screens/employee/profile_screen.dart`
- **Class:** `ProfileScreen`
- **Route:** `/employee/profile`
- **Purpose:** User profile with settings

**Key UI Components:**
- Profile avatar/photo
- User information display
- User role badge
- Settings menu
- Logout button

---

### 2.9 Edit Profile Screen

- **File:** `lib/screens/employee/edit_profile_screen.dart`
- **Class:** `EditProfileScreen`
- **Route:** `/employee/edit-profile`
- **Purpose:** Update personal profile information

**Key UI Components:**
- Name and phone editing fields
- Avatar upload (gallery or camera)
- Form validation
- Save button

---

### 2.10 End of Day Screen

- **File:** `lib/screens/employee/end_of_day_screen.dart`
- **Class:** `EndOfDayScreen`
- **Route:** `/employee/end-of-day`
- **Purpose:** Work session summary shown when ending work

**Key UI Components:**
- Session duration display
- Total distance traveled
- Location list visited
- Photos captured count
- Tasks completed count
- Confirm end session button

---

### 2.11 Image Detail Screen

- **File:** `lib/screens/employee/image_detail_screen.dart`
- **Class:** `ImageDetailScreen`
- **Route:** `/employee/image-detail`
- **Purpose:** Full-screen 9:16 image viewer with metadata

**Key UI Components:**
- Hero image animation
- GPS overlay on map
- Camera metadata display
- Customer details (name, phone, category)
- Notes section
- Download/save functionality
- Verification status badge

---

### 2.12 Monitor Screen (Team Lead)

- **File:** `lib/screens/employee/monitor_screen.dart`
- **Class:** `MonitorScreen`
- **Route:** `/employee/monitor` (team lead) or `/admin/tasks` (admin)
- **Purpose:** Monitor team tasks and employee work

**Key UI Components:**
- Task filtering and status tracking
- Employee status display
- Admin task management view
- Live task update indicators

---

### 2.13 Team Screen

- **File:** `lib/screens/employee/team_screen.dart`
- **Class:** `TeamScreen`
- **Purpose:** Team lead's team management dashboard

**Key UI Components:**
- Team member list with online/offline status
- Alphabetical filtering (A-Z)
- Employee detail navigation
- Member count

---

### 2.14 Team Lead Employee Detail Screen

- **File:** `lib/screens/employee/team_lead_employee_detail_screen.dart`
- **Class:** `TeamLeadEmployeeDetailScreen`
- **Route:** `/employee/team-lead-detail`
- **Purpose:** Team lead viewing subordinate employee details

**Key UI Components:**
- Employee summary stats
- Activity feed
- Recent photos grid
- Online status indicator
- Work session info

---

## 3. Admin Screens

### 3.1 Admin Shell (Navigation Container)

- **File:** `lib/screens/admin/admin_shell.dart`
- **Class:** `AdminShell`
- **Purpose:** Main admin navigation wrapper with bottom nav bar

**Bottom Nav Tabs (5):**
1. Dashboard
2. Tasks
3. Analytics
4. Management
5. Chat

---

### 3.2 Dashboard Screen

- **File:** `lib/screens/admin/dashboard_screen.dart`
- **Class:** `DashboardScreen`
- **Route:** `/admin/dashboard`
- **Purpose:** Enterprise admin overview with real-time employee list

**Key UI Components:**
- Real-time employee status cards (active/inactive)
- Search bar
- Status filtering
- Employee metrics and stats
- Team presence indicators
- Location display per employee
- Tap to navigate to employee details

---

### 3.3 Analytics Screen

- **File:** `lib/screens/admin/analytics_screen.dart`
- **Class:** `AnalyticsScreen`
- **Route:** `/admin/analytics`
- **Purpose:** Enterprise-wide activity analytics

**Key UI Components:**
- Period selector (Today, This Week, This Month, Custom)
- Activity overview cards
- Employee performance metrics
- Drill-down to individual employee
- Search functionality

---

### 3.4 Management Screen

- **File:** `lib/screens/admin/management_screen.dart`
- **Class:** `ManagementScreen`
- **Route:** `/admin/management`
- **Purpose:** Tab container for users and groups management

**Key UI Components:**
- Two tabs: User Management | Groups Management
- Search and filter bar
- Add user / Add group buttons

---

### 3.5 Create Task Screen

- **File:** `lib/screens/admin/create_task_screen.dart`
- **Class:** `CreateTaskScreen`
- **Route:** `/admin/create-task`
- **Purpose:** Create and assign tasks to employees/teams

**Key UI Components:**
- Task title and description inputs
- Assignment type selector (Individual, Team Lead, Group)
- Priority selector (High, Medium, Low)
- Due date picker
- Assignee selection dropdown
- Send notification toggle
- Form validation and submit button

---

### 3.6 Create Group Screen

- **File:** `lib/screens/admin/create_group_screen.dart`
- **Class:** `CreateGroupScreen`
- **Route:** `/admin/create-group`
- **Purpose:** Create team groups with member management

**Key UI Components:**
- Group name input
- Team lead assignment dropdown
- Member selection with alphabet filter
- Optional chat group creation toggle
- Chat mode selection (Open / Broadcast)
- Member list preview

---

### 3.7 Edit Group Screen

- **File:** `lib/screens/admin/edit_group_screen.dart`
- **Class:** `EditGroupScreen`
- **Route:** `/admin/edit-group`
- **Purpose:** Modify existing group settings and members

**Key UI Components:**
- Edit group name field
- Update team leads
- Add/remove members with search
- Save changes button

---

### 3.8 Employee Detail Screen

- **File:** `lib/screens/admin/employee_detail_screen.dart`
- **Class:** `EmployeeDetailScreen`
- **Route:** `/admin/employee/:id`
- **Purpose:** Detailed employee view with activity and photos

**Key UI Components:**
- Real-time employee stats (distance, photos, tasks)
- Activity feed (24-hour window)
- Photo gallery grid with preview
- Work session details
- Online/offline status indicator

---

### 3.9 Employee Activity Screen

- **File:** `lib/screens/admin/employee_activity_screen.dart`
- **Class:** `EmployeeActivityScreen`
- **Purpose:** Detailed activity analysis for a specific employee

**Key UI Components:**
- Period selection (Today, Week, Month, Custom)
- Activity timeline visualization
- Live and aggregate statistics
- Linked employee tracking

---

### 3.10 Add User Screen

- **File:** `lib/screens/admin/add_user_screen.dart`
- **Class:** `AddUserScreen`
- **Route:** `/admin/add-user`
- **Purpose:** Add new employees to the enterprise

**Key UI Components:**
- Name input field
- Phone input with country code selector
- Role selection (Employee, Team Lead, Admin)
- Validation and submit button

---

### 3.11 User Management Screen

- **File:** `lib/screens/admin/user_management_screen.dart`
- **Class:** `UserManagementScreen`
- **Purpose:** List and manage all enterprise users (tab within Management)

**Key UI Components:**
- User list with pagination
- Search and filter bar
- Alphabetical sorting
- User status indicators
- Delete/edit action buttons

---

### 3.12 Groups Screen

- **File:** `lib/screens/admin/groups_screen.dart`
- **Class:** `GroupsScreen`
- **Purpose:** List and manage all team groups (tab within Management)

**Key UI Components:**
- Group list display
- Member count per group
- Quick actions (Edit, Delete)
- Navigation to group details

---

### 3.13 Export Data Screen

- **File:** `lib/screens/admin/export_data_screen.dart`
- **Class:** `ExportDataScreen`
- **Route:** `/admin/export`
- **Purpose:** Configure and generate data exports

**Key UI Components:**
- Category selection (Distributor, Farmer)
- Password entry for export
- File format selection
- Download generated export button

---

### 3.14 Images Screen

- **File:** `lib/screens/admin/images_screen.dart`
- **Class:** `ImagesScreen`
- **Route:** `/admin/employee-images`
- **Purpose:** View cloud images across all employees

**Key UI Components:**
- Employee filter dropdown
- Search functionality
- Image grid display with thumbnails
- Filter by employee

---

## 4. Chat Screens

### 4.1 Chat Groups Screen

- **File:** `lib/screens/chat/chat_groups_screen.dart`
- **Class:** `ChatGroupsScreen`
- **Route:** `/employee/chat` or `/admin/chat`
- **Purpose:** List of chat groups (shared by employees and admins)

**Key UI Components:**
- Chat group list with last message preview
- Unread message count indicators
- Last message timestamp
- Group creation button (admin only)
- Sort and search functionality

---

### 4.2 Chat Conversation Screen

- **File:** `lib/screens/chat/chat_conversation_screen.dart`
- **Class:** `ChatConversationScreen`
- **Route:** `/chat/conversation`
- **Purpose:** Main chat interface for group conversations

**Key UI Components:**
- Message list with chat bubbles
- Text message input field
- Image/photo send capability
- Message timestamps
- User avatars
- Swipe-to-reply gesture
- Real-time message updates
- Camera access button
- Failed messages show the actual Firebase error text inline next to a red refresh-circle icon (tap-to-retry). Backed by `ChatMessageModel.errorMessage: String?`.
- WhatsApp-style floating date pill overlays the top of the message list, showing the date of the topmost-visible message (`Today` / `Yesterday` / `DD MMM YYYY`, IST / Asia/Kolkata). Fades out after 2s of scroll inactivity via a 200ms `AnimatedOpacity`. Matches the styling of the static per-group date separators, which remain unchanged.
- On `initState`, the screen calls `OfflineQueueManager.clearFailedChatJobs()` as a safety net to remove permanently-failed chat jobs from the local queue.

---

### 4.3 Chat Camera Screen

- **File:** `lib/screens/chat/chat_camera_screen.dart`
- **Class:** `ChatCameraScreen`
- **Route:** `/chat/camera`
- **Purpose:** Capture and send geotagged photos to chat groups

**Key UI Components:**
- Live camera preview
- Real-time location display
- Flash mode toggle
- Camera switch (front/back)
- GPS coordinates capture overlay
- Capture button

---

### 4.4 Create Chat Group Screen

- **File:** `lib/screens/chat/create_chat_group_screen.dart`
- **Class:** `CreateChatGroupScreen`
- **Route:** `/admin/create-chat-group`
- **Purpose:** Create new chat groups with members

**Key UI Components:**
- Group name input
- Member selection with alphabet filter
- Mode selection (Open / Broadcast)
- Selected member list preview

---

### 4.5 Edit Chat Group Screen

- **File:** `lib/screens/chat/edit_chat_group_screen.dart`
- **Class:** `EditChatGroupScreen`
- **Route:** `/admin/edit-chat-group`
- **Purpose:** Update chat group settings and members

**Key UI Components:**
- Edit group name field
- Update members list
- Change mode (Open / Broadcast)
- Linked group handling
- Save button

---

### 4.6 Chat Image Send Screen

- **File:** `lib/screens/chat/chat_image_send_screen.dart`
- **Class:** `ChatImageSendScreen`
- **Purpose:** Preview and send photos in chat

**Key UI Components:**
- Image preview
- Caption input field
- Send button with upload progress indicator
- File validation

---

## 5. Notifications

### 5.1 Notifications Screen

- **File:** `lib/screens/notifications/notifications_screen.dart`
- **Class:** `NotificationsScreen`
- **Route:** `/employee/notifications`
- **Purpose:** Central notification hub

**Key UI Components:**
- Notification list with timestamps
- Real-time updates from Firestore
- Tap to navigate to relevant screen
- Notification dismissal
- Sorted by recency (newest first)
- Unread status tracking

---

## 6. Reusable Widgets

**Location:** `lib/widgets/`

### Buttons
| Widget | File | Purpose |
|--------|------|---------|
| `HoldButton` | `hold_button.dart` | Long-press/hold interaction button |
| `PrimaryButton` | `primary_button.dart` | Main action button (glass style) |
| `SecondaryButton` | `secondary_button.dart` | Alternative action button |

### Cards
| Widget | File | Purpose |
|--------|------|---------|
| `EmployeeCard` | `employee_card.dart` | Employee profile card with status |
| `StatCard` | `stat_card.dart` | Statistics display card with icon, label, value |
| `CompactStatCard` | `stat_card.dart` | Smaller variant of StatCard |
| `TaskCard` | `task_card.dart` | Task information card with priority and due date |

### Glass/Design System
| Widget | File | Purpose |
|--------|------|---------|
| `GradientBackground` | `gradient_background.dart` | App-wide gradient background wrapper |
| `GradientScaffold` | `gradient_background.dart` | Scaffold with gradient background |
| `ScrollableContentPanel` | `gradient_background.dart` | Scrollable content wrapper |
| `GlassPanel` | `glass_panel.dart` | Glassmorphism panel container |
| `GlassCard` | `glass_panel.dart` | Extended glass panel variant |
| `GlassChip` | `glass_chip.dart` | Filter/tag chip with glass effect |
| `GlassBadge` | `glass_badge.dart` | Status badge with glass effect |
| `GlassIconButton` | `glass_icon_button.dart` | Icon button with glass styling |
| `GlassListTile` | `glass_list_tile.dart` | List item with glass styling |
| `GlassSectionHeader` | `glass_section_header.dart` | Section header component |

### Inputs
| Widget | File | Purpose |
|--------|------|---------|
| `GlassInputField` | `text_input_field.dart` | Base glass-style text input with prefix/suffix |
| `TextInputField` | `text_input_field.dart` | Extended glass input with label, icon, error states |
| `OtpInputField` | `otp_input_field.dart` | 6-digit OTP input with auto-submit |
| `PhoneInputField` | `phone_input_field.dart` | Phone number input with country code |
| `AlphabetFilter` | `alphabet_filter.dart` | Sort toggle button (A-Z ascending/descending) |

### Navigation
| Widget | File | Purpose |
|--------|------|---------|
| `AppHeader` | `app_header.dart` | Top app bar with title and actions |
| `BottomNavBar` | `bottom_nav_bar.dart` | Bottom navigation (role-specific tabs) |

---

## 7. Navigation Flows

### Employee Flow
```
Welcome (/) --> OTP (/otp) --> Home (/employee/home)
                                  |
                  +---------------+---------------+---------------+
                  |               |               |               |
               Camera          Tasks          History          Chat
            /employee/      /employee/      /employee/      /employee/
             camera           tasks          history          chat
                |                                               |
             Preview                                      Conversation
          /employee/                                      /chat/
        camera/preview                                  conversation
```

### Admin Flow
```
Welcome (/) --> OTP or Enterprise Login --> Dashboard (/admin/dashboard)
                                               |
                   +---------------------------+---------------------------+
                   |               |               |                       |
                Tasks          Analytics       Management               Chat
             /admin/tasks    /admin/analytics  /admin/management       /admin/chat
                   |               |               |                       |
             Create Task    Employee Activity   Add User / Groups    Conversation
           /admin/create-task                  /admin/add-user        /chat/conversation

Other Admin Routes:
  /admin/employee/:id       Employee Detail (real-time stats, photos, activity)
  /admin/employee-images    Enterprise-wide image gallery
  /admin/export             CSV data export
  /admin/profile            Admin profile (reuses ProfileScreen with isAdmin flag)
  /admin/edit-profile       Admin edit profile (reuses EditProfileScreen)
  /admin/create-group       Create team group
  /admin/edit-group         Edit team group
  /admin/create-chat-group  Create chat group
  /admin/edit-chat-group    Edit chat group
```

### Team Lead Flow
```
Welcome (/) --> OTP --> Home (/employee/home)
                          |
          +---------------+---------------+
          |               |               |
        Tasks          Monitor          Team
     /employee/      /employee/      Team Members
       tasks          monitor           List
          |                               |
     Create Task              Employee Detail
   /admin/create-task    /employee/team-lead-detail
```

### Shared Chat Routes (No Shell)
```
/chat/conversation    ChatConversationScreen (shared by employee and admin)
/chat/camera          ChatCameraScreen (capture and send geotagged photos)
```

### Screen Reuse
| Screen | Employee Route | Admin Route | Differentiator |
|--------|---------------|-------------|----------------|
| ProfileScreen | `/employee/profile` | `/admin/profile` | `isAdmin` flag |
| EditProfileScreen | `/employee/edit-profile` | `/admin/edit-profile` | None (same behavior) |
| MonitorScreen | `/employee/monitor` | `/admin/tasks` | `isAdmin`, `showFilter` flags |
| ChatGroupsScreen | `/employee/chat` | `/admin/chat` | Role-based create button |
| CreateTaskScreen | — | `/admin/create-task` | `isTeamLead` param for team leads |

### Deep Link Triggers (from Notifications)
| Notification Type | Employee Route | Admin Route |
|---|---|---|
| `TASK_ASSIGNED` | `/employee/tasks` | `/admin/tasks` |
| `TASK_COMPLETED` | `/employee/tasks` | `/admin/tasks` |
| `SESSION_STARTED` | `/employee/home` | `/admin/dashboard` |
| `SESSION_ENDED` | `/employee/home` | `/admin/dashboard` |
| `CHAT_MESSAGE` | `/chat/conversation` | `/chat/conversation` |

---

## Screen Count Summary

| Module | Screens |
|--------|---------|
| Authentication | 3 |
| Employee | 14 |
| Admin | 14 |
| Chat | 6 |
| Notifications | 1 |
| **Total** | **38** |

---

## State Management (Providers)

| Provider | Purpose |
|----------|---------|
| `AuthProvider` | Authentication state and user role |
| `SessionProvider` | Work session tracking |
| `PhotoProvider` | Photo management |
| `TaskProvider` | Task state |
| `GroupProvider` | Team groups |
| `UserProvider` | Enterprise users |
| `DashboardProvider` | Dashboard employee data |
| `AnalyticsProvider` | Analytics data |
| `TeamProvider` | Team lead's team data |
| `ChatProvider` | Chat messages and groups |
