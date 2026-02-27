# Task Management API Endpoints

## Base URL
`http://localhost:8000/api`

## Task Endpoints

### 1. Get All Tasks
**GET** `/tasks?user_id={userId}&user_role={role}`

**Query Parameters:**
- `user_id` (required): User ID
- `user_role` (required): 'admin' or 'employee'

**Response:**
```json
{
  "status": "success",
  "data": [
    {
      "id": "uuid",
      "title": "Task Title",
      "description": "Task description",
      "category": "project",
      "priority": "high",
      "status": "in_progress",
      "deadline_date": "2024-12-31",
      "deadline_time": "17:00:00",
      "created_by": "user_id",
      "assigned_to": "user_id",
      "creator_name": "John Doe",
      "assignee_name": "Jane Smith",
      "createdAt": "2024-01-01 10:00:00",
      "updatedAt": "2024-01-01 10:00:00"
    }
  ]
}
```

### 2. Create Task
**POST** `/tasks`

**Request Body:**
```json
{
  "title": "Task Title",
  "description": "Task description",
  "category": "project",
  "priority": "high",
  "deadline_date": "2024-12-31",
  "deadline_time": "17:00:00",
  "created_by": "user_id",
  "assigned_to": "user_id"
}
```

**Response:**
```json
{
  "status": "success",
  "message": "Task created successfully",
  "data": { ... }
}
```

### 3. Get Single Task
**GET** `/tasks/{id}`

**Response:**
```json
{
  "status": "success",
  "data": { ... }
}
```

### 4. Update Task
**PUT** `/tasks/{id}`

**Request Body:**
```json
{
  "title": "Updated Title",
  "description": "Updated description",
  "priority": "critical",
  "status": "in_progress"
}
```

**Response:**
```json
{
  "status": "success",
  "message": "Task updated successfully",
  "data": { ... }
}
```

### 5. Delete Task
**DELETE** `/tasks/{id}`

**Response:**
```json
{
  "status": "success",
  "message": "Task deleted successfully"
}
```

### 6. Update Task Status
**PATCH** `/tasks/{id}/status`

**Request Body:**
```json
{
  "status": "completed"
}
```

**Response:**
```json
{
  "status": "success",
  "message": "Task status updated successfully",
  "data": { ... }
}
```

## Task Categories
- `daily` - Daily tasks
- `project` - Project tasks
- `personal` - Personal tasks
- `family` - Family tasks
- `other` - Other tasks

## Task Priorities
- `low` - Low priority
- `medium` - Medium priority
- `high` - High priority
- `critical` - Critical priority

## Task Status
- `assigned` - Grey (newly assigned)
- `in_progress` - Yellow (work in progress)
- `completed` - Green (finished)
- `paused` - Orange (temporarily stopped)
- `need_help` - Red (requires assistance)

## Business Rules

### Admin:
- Can create all task types for self
- Can create project tasks for employees
- Sees ALL project tasks (from all users)
- Sees own personal tasks

### Employee:
- Can create all task types for self
- Sees only own tasks
- Sees project tasks assigned by admin
