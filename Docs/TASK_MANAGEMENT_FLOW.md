# Task Management System - Complete Flow Documentation

## Table of Contents
1. [System Overview](#system-overview)
2. [User Roles](#user-roles)
3. [Task Categories](#task-categories)
4. [Task Status & Colors](#task-status--colors)
5. [Task Priority Levels](#task-priority-levels)
6. [Admin Flow](#admin-flow)
7. [Employee Flow](#employee-flow)
8. [Task Lifecycle](#task-lifecycle)
9. [Business Rules](#business-rules)
10. [UI/UX Flow](#uiux-flow)

---

## System Overview

The Employee Task Management (ETM) system allows organizations to manage tasks across different categories with role-based access control. The system supports two user roles (Admin and Employee) with different permissions and visibility rules.

---

## User Roles

### 1. Admin
**Permissions:**
- Create all types of tasks for self
- Create project tasks for employees
- View ALL project tasks (from all users) and give all employee dropdown 
- View own personal tasks (Daily, Personal, Family, Other)
- Edit and delete tasks
- Update task status
- Assign tasks to employees

**Dashboard View:**
- All project tasks (company-wide)
- Own personal tasks only

### 2. Employee
**Permissions:**
- Create all types of tasks for self
- View only own tasks (all categories)
- View project tasks assigned by admin
- Update status of own tasks
- Edit own tasks
- Cannot assign tasks to others

**Dashboard View:**
- Own tasks only (all categories)
- Project tasks assigned by admin

---

## Task Categories

### 1. Daily Task
- **Purpose:** Routine daily activities
- **Examples:** Check emails, daily standup, review reports
- **Visibility:** Creator only (except admin sees all projects)
- **Icon:** 📅 Calendar

### 2. Project Task
- **Purpose:** Work-related project activities
- **Examples:** Complete feature, fix bug, client meeting
- **Visibility:** 
  - Admin: ALL project tasks (company-wide)
  - Employee: Own project tasks + assigned by admin
- **Icon:** 💼 Work briefcase
- **Special:** Admin can assign to employees

### 3. Personal Task
- **Purpose:** Individual personal goals
- **Examples:** Learn new skill, read documentation
- **Visibility:** Creator only
- **Icon:** 👤 Person

### 4. Family Task
- **Purpose:** Family-related activities
- **Examples:** Family event, personal appointment
- **Visibility:** Creator only
- **Icon:** 👨‍👩‍👧‍👦 Family

### 5. Other Task
- **Purpose:** Miscellaneous tasks
- **Examples:** Any task not fitting other categories
- **Visibility:** Creator only
- **Icon:** ⋯ More options

---

## Task Status & Colors

### Status Flow
```
Assigned → In Progress → Completed
    ↓           ↓
  Paused    Need Help
```

### Status Definitions

| Status | Color | Hex Code | Description | When to Use |
|--------|-------|----------|-------------|-------------|
| **Assigned** | Grey | `#9E9E9E` | Task is assigned but not started | Initial state when task is created |
| **In Progress** | Yellow/Orange | `#FF9800` | Task is actively being worked on | When employee starts working |
| **Completed** | Green | `#4CAF50` | Task is finished | When task is done |
| **Paused** | Amber | `#FFC107` | Task is temporarily stopped | When work is interrupted |
| **Need Help** | Red | `#F44336` | Task is blocked, needs assistance | When employee needs help |

### Status Transitions

**From Assigned:**
- → In Progress (Start working)
- → Need Help (Blocked immediately)

**From In Progress:**
- → Completed (Finish task)
- → Paused (Temporary stop)
- → Need Help (Encountered blocker)

**From Paused:**
- → In Progress (Resume work)
- → Need Help (Found issue)

**From Need Help:**
- → In Progress (Issue resolved)
- → Paused (Waiting for help)

**From Completed:**
- No transitions (final state)

---

## Task Priority Levels

| Priority | Color | Badge Color | Use Case |
|----------|-------|-------------|----------|
| **Low** | Blue | `#2196F3` | Nice to have, no deadline pressure |
| **Medium** | Orange | `#FF9800` | Normal priority, standard deadline |
| **High** | Deep Orange | `#FF5722` | Important, tight deadline |
| **Critical** | Red | `#F44336` | Urgent, immediate attention required |

---

## Admin Flow

### Creating Tasks

#### For Self (All Categories)
```
1. Admin Dashboard
   ↓
2. Click "Tasks" from sidebar
   ↓
3. Click "+" FAB button
   ↓
4. Select Category (Daily/Project/Personal/Family/Other)
   ↓
5. "Assign To" = Self (default)
   ↓
6. Fill task details:
   - Title
   - Description
   - Priority
   - Deadline (Date & Time)
   ↓
7. Click "Create Task"
   ↓
8. Task appears in task list
```

#### For Employee (Project Only)
```
1. Admin Dashboard
   ↓
2. Click "Tasks" from sidebar
   ↓
3. Click "+" FAB button
   ↓
4. Select Category = "Project Task"
   ↓
5. "Assign To" = Employee
   ↓
6. Dropdown of emplyee 
   ↓
7. Fill task details:
   - Title
   - Description
   - Priority
   - Deadline (Date & Time)
   ↓
8. Click "Create Task"
   ↓
9. Task appears in admin's project list
10. Task appears in employee's task list
```

### Viewing Tasks

**Admin sees:**
- ALL project tasks (from all employees + self)
- Own personal tasks (Daily, Personal, Family, Other)

**Filter Options:**
- All
- Assigned
- In Progress
- Completed
- Paused
- Need Help   and use icons and consize the properly 

### Managing Tasks

```
1. Click on task card
   ↓
2. View task details
   ↓
3. Options:
   - Edit task
   - Update status
   - Delete task
   - Reassign (for project tasks)
```

---

## Employee Flow

### Creating Tasks

#### For Self (All Categories)
```
1. Employee Dashboard
   ↓
2. Click "Tasks" from sidebar
   ↓
3. Click "+" FAB button
   ↓
4. Select Category (Daily/Project/Personal/Family/Other)
   ↓
5. "Assign To" = Self (only option)
   ↓
6. Fill task details:
   - Title
   - Description
   - Priority
   - Deadline (Date & Time)
   ↓
7. Click "Create Task"
   ↓
8. Task appears in task list
```

**Note:** Employee can create project tasks, and admin will see them in the project tasks list.

### Viewing Tasks

**Employee sees:**
- Own tasks (all categories)
- Project tasks assigned by admin

**Filter Options:**
- All
- Assigned
- In Progress
- Completed
- Paused
- Need Help

### Updating Task Status

```
1. Click on task card
   ↓
2. View task details
   ↓
3. Click "Update Status"
   ↓
4. Select new status:
   - In Progress (started working)
   - Paused (temporary stop)
   - Need Help (blocked)
   - Completed (finished)
   ↓
5. Status updated
6. Color changes accordingly
```

---

## Task Lifecycle

### Complete Task Journey

```
┌─────────────────────────────────────────────────────────┐
│ 1. CREATION                                             │
│    - Admin/Employee creates task                        │
│    - Status: Assigned (Grey)                            │
│    - Appears in respective dashboards                   │
└─────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────┐
│ 2. START WORK                                           │
│    - Employee updates status to "In Progress"           │
│    - Status: In Progress (Yellow/Orange)                │
│    - Visible to admin (if project task)                 │
└─────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────┐
│ 3. WORK IN PROGRESS                                     │
│    - Employee works on task                             │
│    - Can pause if needed → Paused (Amber)               │
│    - Can request help → Need Help (Red)                 │
│    - Can resume from paused → In Progress               │
└─────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────┐
│ 4. COMPLETION                                           │
│    - Employee marks as "Completed"                      │
│    - Status: Completed (Green)                          │
│    - Admin can view completed tasks                     │
│    - Task archived (optional)                           │
└─────────────────────────────────────────────────────────┘
```

### Status Change Scenarios

#### Scenario 1: Smooth Completion
```
Assigned → In Progress → Completed
(Grey)   → (Yellow)    → (Green)
```

#### Scenario 2: With Pause
```
Assigned → In Progress → Paused → In Progress → Completed
(Grey)   → (Yellow)    → (Amber) → (Yellow)    → (Green)
```

#### Scenario 3: Need Help
```
Assigned → In Progress → Need Help → In Progress → Completed
(Grey)   → (Yellow)    → (Red)     → (Yellow)    → (Green)
```

#### Scenario 4: Blocked from Start
```
Assigned → Need Help → In Progress → Completed
(Grey)   → (Red)     → (Yellow)    → (Green)
```

---

## Business Rules

### Task Creation Rules

1. **Admin can:**
   - Create any task type for self
   - Create project tasks for employees
   - Must provide employee ID when assigning

2. **Employee can:**
   - Create any task type for self only
   - Cannot assign tasks to others
   - Can create project tasks (visible to admin)

3. **Required Fields:**
   - Task title (mandatory)
   - Category (mandatory)
   - Priority (mandatory, default: medium)
   - Created by (auto-filled)
   - Assigned to (auto-filled or selected)

4. **Optional Fields:**
   - Description
   - Deadline date
   - Deadline time

### Task Visibility Rules

1. **Project Tasks:**
   - Admin sees ALL project tasks (company-wide)
   - Employee sees only own project tasks
   - Employee sees project tasks assigned by admin

2. **Personal Tasks (Daily/Personal/Family/Other):**
   - Only creator can see
   - Admin sees only own personal tasks
   - Employee sees only own personal tasks

3. **Filtering:**
   - Users can filter by status
   - Filters apply to visible tasks only

### Task Modification Rules

1. **Edit Task:**
   - Creator can edit own tasks
   - Admin can edit any project task
   - Cannot change creator or initial assignment

2. **Update Status:**
   - Assigned user can update status
   - Admin can update status of any project task
   - Status must follow valid transitions

3. **Delete Task:**
   - Creator can delete own tasks
   - Admin can delete any project task
   - Deleted tasks are permanently removed

---

## UI/UX Flow

### Task List Screen

```
┌─────────────────────────────────────────┐
│ ← Tasks                    🔔 ⎋         │
├─────────────────────────────────────────┤
│ [All] [Assigned] [In Progress] ...      │ ← Filter chips
├─────────────────────────────────────────┤
│                                         │
│ ┌─────────────────────────────────────┐ │
│ │ 💼 Complete Documentation           │ │
│ │ Write API docs for task system      │ │
│ │ [HIGH]                              │ │
│ │ 🟡 IN PROGRESS    📅 27/02/2024     │ │
│ │ 👤 Assigned to: John Doe            │ │
│ └─────────────────────────────────────┘ │
│                                         │
│ ┌─────────────────────────────────────┐ │
│ │ 📅 Daily Standup                    │ │
│ │ Team sync meeting                   │ │
│ │ [MEDIUM]                            │ │
│ │ ⚪ ASSIGNED       📅 27/02/2024     │ │
│ └─────────────────────────────────────┘ │
│                                         │
│                                    [+]  │ ← FAB button
└─────────────────────────────────────────┘
```

### Create Task Screen

```
┌─────────────────────────────────────────┐
│ ← Create Task                           │
├─────────────────────────────────────────┤
│ Task Category                           │
│ [Project Task ▼]                        │
│                                         │
│ Assign To (Admin only for Project)     │
│ ○ Self                                  │
│ ● Employee [Employee ID: _______]       │
│                                         │
│ Task Title                              │
│ [_____________________________]         │
│                                         │
│ Description / Subtask                   │
│ [_____________________________]         │
│ [_____________________________]         │
│                                         │
│ Priority                                │
│ [Low] [Medium✓] [High] [Critical]       │
│                                         │
│ Deadline                                │
│ [📅 27/02/2024] [🕐 14:30]             │
│                                         │
│ [      Create Task      ]               │
└─────────────────────────────────────────┘
```

### Task Detail Screen (Future)

```
┌─────────────────────────────────────────┐
│ ← Task Details                     ⋮    │
├─────────────────────────────────────────┤
│ 💼 Complete Documentation               │
│ [HIGH]                                  │
│                                         │
│ Description:                            │
│ Write comprehensive API documentation   │
│ for the task management system          │
│                                         │
│ Status: 🟡 IN PROGRESS                  │
│ Priority: High                          │
│ Category: Project                       │
│                                         │
│ Created by: Admin User                  │
│ Assigned to: John Doe                   │
│                                         │
│ Deadline: 27/02/2024 at 17:00          │
│ Created: 25/02/2024 at 10:00           │
│                                         │
│ [Update Status]  [Edit]  [Delete]       │
└─────────────────────────────────────────┘
```

---

## Key Features Summary

### ✅ Implemented
- Task creation with all categories
- Role-based task visibility
- Status management with colors
- Priority levels
- Deadline tracking
- Filter by status
- Clean, simple UI
- Pull-to-refresh
- Error handling

### 🚧 To Be Implemented
- Task detail view
- Task editing
- Task deletion
- Employee selector (dropdown)
- Task comments/notes
- Task attachments
- Notifications
- Task history/audit log
- Search functionality
- Sort options
- Task statistics/reports

---

## API Integration

### Endpoints Used

1. **GET** `/api/tasks?user_id={id}&user_role={role}`
   - Fetch tasks based on role

2. **POST** `/api/tasks`
   - Create new task

3. **PUT** `/api/tasks/{id}`
   - Update task details

4. **PATCH** `/api/tasks/{id}/status`
   - Update task status only

5. **DELETE** `/api/tasks/{id}`
   - Delete task

---

## Best Practices

### For Admins
1. Use project tasks for work-related assignments
2. Set appropriate priorities
3. Provide clear descriptions
4. Set realistic deadlines
5. Monitor task progress regularly
6. Help employees when status is "Need Help"

### For Employees
1. Update status promptly
2. Use "Need Help" when blocked
3. Use "Paused" for interruptions
4. Mark completed tasks immediately
5. Create project tasks for visibility
6. Keep personal tasks organized

---

## Troubleshooting

### Common Issues

**Issue:** Can't see project tasks
- **Solution:** Check user role, admin sees all, employee sees own

**Issue:** Can't assign to employee
- **Solution:** Only admin can assign project tasks

**Issue:** Status not updating
- **Solution:** Check network connection, verify API is running

**Issue:** Task not appearing
- **Solution:** Check filters, pull to refresh

---

## Future Enhancements

1. **Notifications**
   - Push notifications for task assignments
   - Deadline reminders
   - Status change alerts

2. **Collaboration**
   - Task comments
   - File attachments
   - Task sharing

3. **Analytics**
   - Task completion rates
   - Time tracking
   - Performance metrics

4. **Advanced Features**
   - Recurring tasks
   - Task templates
   - Subtasks/checklists
   - Task dependencies

---

**Document Version:** 1.0  
**Last Updated:** February 27, 2024  
**Author:** ETM Development Team
