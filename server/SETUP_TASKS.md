# Quick Setup for Tasks Feature

Run these commands in order:

## 1. Run Migration
```bash
php artisan migrate
```

## 2. Verify Routes
```bash
php artisan route:list --path=api/tasks
```

## 3. Clear Cache (if needed)
```bash
php artisan route:clear
php artisan cache:clear
```

## 4. Start/Restart Server
```bash
php artisan serve
```

## 5. Test API
Open browser and go to:
```
http://localhost:8000/api/tasks?user_id=test&user_role=admin
```

You should see:
```json
{
  "status": "success",
  "data": []
}
```

## If you see 404 error:
1. Make sure server is running
2. Check if TaskController.php exists in app/Http/Controllers/
3. Check if routes are in routes/api.php
4. Restart the server

## Create a Test Task (Optional)
```bash
curl -X POST http://localhost:8000/api/tasks \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Test Task",
    "description": "This is a test task",
    "category": "project",
    "priority": "high",
    "deadline_date": "2024-12-31",
    "deadline_time": "17:00:00",
    "created_by": "admin-user-id",
    "assigned_to": "admin-user-id"
  }'
```
