#!/bin/bash
set -e

# ==============================================================================
# Startup script for School Management System
# Run this as the devops user (no sudo required) to start the app directly
# For systemd management, use the systemd service files in deploy/
# ==============================================================================

PROJECT_DIR="/home/devops/personalweb/epk"
VENV_DIR="${PROJECT_DIR}/venv"
LOG_DIR="${PROJECT_DIR}/logs"
FRONTEND_DIST="${PROJECT_DIR}/frontend_app/dist"

mkdir -p "${LOG_DIR}"

echo "========================================"
echo "Starting School Management System"
echo "========================================"

# Activate virtual environment
source "${VENV_DIR}/bin/activate"

# Start Redis (if not running)
if ! pgrep -x redis-server > /dev/null 2>&1; then
    echo "[1/4] Starting Redis..."
    redis-server --daemonize yes --port 6379
    sleep 1
else
    echo "[1/4] Redis already running"
fi

# Start Gunicorn (Django WSGI server)
if ! pgrep -f "gunicorn.*core.wsgi" > /dev/null 2>&1; then
    echo "[2/4] Starting Gunicorn..."
    gunicorn --config "${PROJECT_DIR}/gunicorn.conf.py" core.wsgi:application &
    sleep 2
    echo "    Gunicorn started on 127.0.0.1:8000"
else
    echo "[2/4] Gunicorn already running"
fi

# Start Celery worker
if ! pgrep -f "celery.*core worker" > /dev/null 2>&1; then
    echo "[3/4] Starting Celery worker..."
    celery -A core worker -l info --logfile "${LOG_DIR}/celery.log" &
    sleep 1
    echo "    Celery worker started"
else
    echo "[3/4] Celery worker already running"
fi

# Start Celery beat
if ! pgrep -f "celery.*core beat" > /dev/null 2>&1; then
    echo "[4/4] Starting Celery beat..."
    celery -A core beat -l info --logfile "${LOG_DIR}/celery-beat.log" &
    sleep 1
    echo "    Celery beat started"
else
    echo "[4/4] Celery beat already running"
fi

echo ""
echo "========================================"
echo "All services started!"
echo "========================================"
echo ""
echo "Gunicorn:  http://127.0.0.1:8000 (API at /api/)"
echo "Logs:      ${LOG_DIR}/"
echo ""
echo "To stop services, run: ./deploy/startup.sh --stop"

# Handle --stop flag
if [ "${1}" = "--stop" ]; then
    echo ""
    echo "Stopping services..."
    pkill -f "gunicorn.*core.wsgi" 2>/dev/null && echo "  Gunicorn stopped" || echo "  Gunicorn not running"
    pkill -f "celery.*core worker" 2>/dev/null && echo "  Celery worker stopped" || echo "  Celery worker not running"
    pkill -f "celery.*core beat" 2>/dev/null && echo "  Celery beat stopped" || echo "  Celery beat not running"
    pkill -x redis-server 2>/dev/null && echo "  Redis stopped" || echo "  Redis not running"
    echo "All services stopped."
fi