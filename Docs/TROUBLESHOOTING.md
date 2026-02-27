# Troubleshooting Guide - 404 Error on Tasks API

## Error: "Server error: 404"

This error means the API endpoint is not found. Follow these steps to fix it:

### Step 1: Run the Migration
The tasks table needs to be created in the database.

```bash
cd server
php artisan migrate
```

**Expected Output:**
```
INFO  Running migrations.
2024_01_02_000001_create_tasks_table ........................... DONE
```

### Step 2: Restart Laravel Server
After adding new routes or controllers, you must restart the server.

```bash
# Stop the current server (Ctrl+C)
# Then start it again:
php artisan serve
```

**Expected Output:**
```
INFO  Server running on [http://127.0.0.1:8000].
```

### Step 3: Test the API Endpoint
Open your browser or use curl to test:

```bash
# Test if the endpoint exists
curl "http://localhost:8000/api/tasks?user_id=test&user_role=admin"
```

**Expected Response:**
```json
{
  "status": "success",
  "data": []
}
```

### Step 4: Check Route List
Verify the routes are registered:

```bash
php artisan route:list --path=api/tasks
```

**Expected Output:**
```
GET|HEAD   api/tasks .................... TaskController@index
POST       api/tasks .................... TaskController@store
GET|HEAD   api/tasks/{id} ............... TaskController@show
PUT|PATCH  api/tasks/{id} ............... TaskController@update
DELETE     api/tasks/{id} ............... TaskController@destroy
PATCH      api/tasks/{id}/status ........ TaskController@updateStatus
```

### Step 5: Clear Laravel Cache (if needed)
Sometimes Laravel caches routes:

```bash
php artisan route:clear
php artisan cache:clear
php artisan config:clear
```

### Step 6: Verify Database Connection
Make sure your database is connected:

```bash
curl http://localhost:8000/api/db-test
```

**Expected Response:**
```json
{
  "status": "success",
  "database": "Connected",
  "result": [{"test": 1}]
}
```

## Common Issues

### Issue 1: Port Already in Use
If port 8000 is busy, use a different port:

```bash
php artisan serve --port=8001
```

Then update `client/lib/services/api_config.dart`:
```dart
static const String baseUrl = 'http://localhost:8001/api';
```

### Issue 2: Migration Already Ran
If you see "Table already exists" error:

```bash
# Drop all tables and re-run migrations
php artisan migrate:fresh
```

### Issue 3: Controller Not Found
Make sure the TaskController.php file exists:
```
server/app/Http/Controllers/TaskController.php
```

### Issue 4: CORS Error (from Flutter)
If you get CORS errors, you may need to configure CORS in Laravel.

## Quick Checklist

- [ ] Laravel server is running (`php artisan serve`)
- [ ] Migration has been executed (`php artisan migrate`)
- [ ] Routes are registered (check `server/routes/api.php`)
- [ ] TaskController exists (`server/app/Http/Controllers/TaskController.php`)
- [ ] Database is connected (test with `/api/db-test`)
- [ ] Correct API URL in Flutter (`client/lib/services/api_config.dart`)

## Still Not Working?

Check the Laravel logs:
```bash
tail -f storage/logs/laravel.log
```

Or run Laravel in debug mode to see detailed errors in the browser.
