# Backend Setup Checklist

Use this checklist to ensure your Laravel backend is properly set up for the Task Management feature.

## ✅ Checklist

### 1. Files Exist
- [ ] `server/app/Http/Controllers/TaskController.php` exists
- [ ] `server/database/migrations/2024_01_02_000001_create_tasks_table.php` exists
- [ ] `server/routes/api.php` contains TaskController routes

### 2. Database
- [ ] Migration has been run: `php artisan migrate`
- [ ] Tasks table exists in database
- [ ] Database connection works: Test at `http://localhost:8000/api/db-test`

### 3. Routes
- [ ] Routes are registered: `php artisan route:list --path=api/tasks`
- [ ] Cache is cleared: `php artisan route:clear`

### 4. Server
- [ ] Laravel server is running: `php artisan serve`
- [ ] Server is accessible: `http://localhost:8000/api/health`
- [ ] Tasks endpoint works: `http://localhost:8000/api/tasks?user_id=test&user_role=admin`

### 5. Flutter App
- [ ] API config points to correct URL: `client/lib/services/api_config.dart`
- [ ] App has been restarted (hot restart with `R`)

## Quick Commands

Run all these in the `server` directory:

```cmd
# 1. Run migration
php artisan migrate

# 2. Clear caches
php artisan route:clear
php artisan cache:clear
php artisan config:clear

# 3. Verify routes
php artisan route:list --path=api/tasks

# 4. Start server
php artisan serve
```

## Test URLs

Open these in your browser:

1. Health check: `http://localhost:8000/api/health`
   - Should return: `{"status":"OK","message":"API Working"}`

2. Database test: `http://localhost:8000/api/db-test`
   - Should return: `{"status":"success","database":"Connected"}`

3. Tasks endpoint: `http://localhost:8000/api/tasks?user_id=test&user_role=admin`
   - Should return: `{"status":"success","data":[]}`

If all three work, your backend is ready! ✅

## Troubleshooting

### If routes don't show up:
```cmd
php artisan route:clear
php artisan optimize:clear
# Restart server
```

### If migration fails:
```cmd
# Check if table already exists
php artisan migrate:status

# If needed, rollback and re-run
php artisan migrate:rollback
php artisan migrate
```

### If 404 persists:
1. Check `routes/api.php` has TaskController imported
2. Check TaskController.php exists
3. Restart server completely
4. Clear browser cache
5. Restart Flutter app

## Success Indicators

✅ Server shows: `INFO  Server running on [http://127.0.0.1:8000]`
✅ Routes list shows 6 task routes
✅ Browser shows JSON (not HTML error)
✅ Flutter app loads tasks (even if empty list)
✅ Can create tasks without 404 error
