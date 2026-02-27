# Quick Backend Test

## Run these commands in PowerShell/CMD:

### 1. Navigate to server directory
```cmd
cd server
```

### 2. Run migration
```cmd
php artisan migrate
```

### 3. Check if routes exist
```cmd
php artisan route:list | findstr tasks
```

You should see output like:
```
GET|HEAD   api/tasks
POST       api/tasks
GET|HEAD   api/tasks/{id}
...
```

### 4. Clear cache
```cmd
php artisan route:clear
php artisan cache:clear
php artisan config:clear
```

### 5. Start server (or restart if already running)
```cmd
php artisan serve
```

### 6. Test in browser
Open: `http://localhost:8000/api/tasks?user_id=test&user_role=admin`

Expected result:
```json
{"status":"success","data":[]}
```

If you see this, the backend is working!

### 7. Hot restart Flutter app
In your Flutter terminal, press `R` (capital R) to hot restart.

## If still getting 404:

Check if TaskController.php exists:
```cmd
dir app\Http\Controllers\TaskController.php
```

Check if migration file exists:
```cmd
dir database\migrations\*create_tasks_table*
```

Check Laravel logs:
```cmd
type storage\logs\laravel.log
```
