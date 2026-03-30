#!/usr/bin/env sh
set -eu

php artisan config:cache
php artisan route:cache
php artisan view:cache
php artisan migrate --force

# Start background workers for queue and realtime events.
php artisan queue:work --sleep=1 --tries=3 --timeout=120 &
QUEUE_PID=$!

php artisan reverb:start --host=0.0.0.0 --port=${REVERB_SERVER_PORT:-8080} &
REVERB_PID=$!

# Ensure child processes are stopped when container exits.
trap 'kill ${QUEUE_PID} ${REVERB_PID} 2>/dev/null || true' INT TERM EXIT

php artisan serve --host=0.0.0.0 --port=${PORT:-8000}
