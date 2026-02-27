# QUICK FIX GUIDE - 404 Error

## The Problem
Your Flutter app is trying to connect to the Laravel API, but getting a 404 error. This means the Laravel server either:
1. Is not running
2. Hasn't loaded the new routes
3. The migration hasn't been run

## THE SOLUTION (Follow in order)

### Step 1: Open a NEW terminal/command prompt
Don't close your Flutter app. Open a separate terminal.

### Step 2: Navigate to server folder
```cmd
cd D:\ADRS-ALL\Loagma_ETM\server
```

### Step 3: Run the migration
```cmd
php artisan migrate
```

**Expected output:**
```
INFO  Running migrations.
2024_01_02_000001_create_tasks_table ........................... DONE
```

If you see "Nothing to migrate", that's also OK - it means the table already exists.

### Step 4: Verify the routes are registered
```cmd
php artisan route:list --path=api/tasks
```

**Expected output:**
```
GET|HEAD   api/tasks .................... TaskController@index
POST       api/tasks .................... TaskController@store
...
```

If you see "No routes found", there's a problem with the routes file.

### Step 5: Clear all Laravel caches
```cmd
php artisan route:clear
php artisan cache:clear
php artisan config:clear
php artisan optimize:clear
```

### Step 6: Check if server is running
Look for a terminal window that says:
```
INFO  Server running on [http://127.0.0.1:8000].
```

If you DON'T see this, the server is not running!

### Step 7: Start/Restart the server
If server is running, press `Ctrl+C` to stop it first.

Then start it:
```cmd
php artisan serve
```

**You should see:**
```
INFO  Server running on [http://127.0.0.1:8000].
Press Ctrl+C to stop the server
```

### Step 8: Test the API in your browser
Open your web browser and go to:
```
http://localhost:8000/api/tasks?user_id=test&user_role=admin
```

**You should see:**
```json
{"status":"success","data":[]}
```

If you see this JSON response, the backend is working! ✅

### Step 9: Restart Flutter app
In your Flutter terminal, press:
- `R` (capital R) for hot restart
- Or stop and run `flutter run` again

### Step 10: Try creating a task again
The error should be gone!

---

## Still Not Working?

### Check 1: Is TaskController.php there?
```cmd
dir app\Http\Controllers\TaskController.php
```

If "File Not Found", the controller is missing!

### Check 2: Are routes in api.php?
```cmd
type routes\api.php | findstr TaskController
```

You should see:
```
use App\Http\Controllers\TaskController;
Route::get('/tasks', [TaskController::class, 'index']);
...
```

### Check 3: Check Laravel logs
```cmd
type storage\logs\laravel.log
```

Look for any error messages at the bottom.

### Check 4: Test database connection
```
http://localhost:8000/api/db-test
```

Should return:
```json
{"status":"success","database":"Connected"}
```

---

## Common Mistakes

❌ **Mistake 1:** Server not running
✅ **Fix:** Run `php artisan serve`

❌ **Mistake 2:** Old routes cached
✅ **Fix:** Run `php artisan route:clear`

❌ **Mistake 3:** Migration not run
✅ **Fix:** Run `php artisan migrate`

❌ **Mistake 4:** Wrong port in Flutter
✅ **Fix:** Check `client/lib/services/api_config.dart` - should be port 8000

---

## Quick Test Commands

Test if backend is alive:
```cmd
curl http://localhost:8000/api/health
```

Test if tasks endpoint exists:
```cmd
curl "http://localhost:8000/api/tasks?user_id=test&user_role=admin"
```

Both should return JSON, not HTML error pages.
