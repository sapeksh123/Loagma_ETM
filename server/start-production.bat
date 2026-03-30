@echo off
setlocal

if "%REVERB_SERVER_PORT%"=="" set REVERB_SERVER_PORT=8080
if "%PORT%"=="" set PORT=8000

echo [BOOT] Caching Laravel config/routes/views...
php artisan config:cache || goto :error
php artisan route:cache || goto :error
php artisan view:cache || goto :error

echo [BOOT] Running migrations...
php artisan migrate --force || goto :error

echo [BOOT] Starting queue worker in a new window...
start "QUEUE" cmd /c "php artisan queue:work --sleep=1 --tries=3 --timeout=120"

echo [BOOT] Starting Reverb in a new window...
start "REVERB" cmd /c "php artisan reverb:start --host=0.0.0.0 --port=%REVERB_SERVER_PORT%"

echo [BOOT] Starting API server on port %PORT%...
php artisan serve --host=0.0.0.0 --port=%PORT% || goto :error

goto :eof

:error
echo.
echo [ERROR] Startup failed. Check logs above.
exit /b 1
