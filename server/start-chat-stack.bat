@echo off
setlocal

echo Starting chat stack...
echo.

REM Start Laravel API server
start "Laravel API" cmd /k "cd /d %~dp0 && php artisan serve --host=127.0.0.1 --port=8000"

REM Start queue worker for queued broadcasts
start "Laravel Queue Worker" cmd /k "cd /d %~dp0 && php artisan queue:work"

REM Start Laravel Reverb websocket server
start "Laravel Reverb" cmd /k "cd /d %~dp0 && php artisan reverb:start"

echo All services launched in separate terminal windows.
echo 1) Laravel API        : http://127.0.0.1:8000
echo 2) Queue Worker       : running
echo 3) Reverb WebSocket   : running
echo.
echo To stop, close the three opened terminal windows.

endlocal
