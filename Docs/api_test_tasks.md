# Task API Testing

## Test the APIs using these commands:

### 1. Create a Task
```bash
curl -X POST http://localhost:8000/api/tasks \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Complete Project Documentation",
    "description": "Write comprehensive documentation for the ETM system",
    "category": "project",
    "priority": "high",
    "deadline_date": "2024-12-31",
    "deadline_time": "17:00:00",
    "created_by": "admin-user-id",
    "assigned_to": "employee-user-id"
  }'
```

### 2. Get All Tasks (Admin)
```bash
curl "http://localhost:8000/api/tasks?user_id=admin-user-id&user_role=admin"
```

### 3. Get All Tasks (Employee)
```bash
curl "http://localhost:8000/api/tasks?user_id=employee-user-id&user_role=employee"
```

### 4. Update Task Status
```bash
curl -X PATCH http://localhost:8000/api/tasks/{task-id}/status \
  -H "Content-Type: application/json" \
  -d '{
    "status": "in_progress"
  }'
```

### 5. Delete Task
```bash
curl -X DELETE http://localhost:8000/api/tasks/{task-id}
```
