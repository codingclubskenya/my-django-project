#!/bin/bash
set -e

# ==============================================================================
# Update script for School Management System
# Run on server (devops@vmi3555221) from any directory:
#   bash ~/home/personal/personalweb/epk/deploy/update.sh codingclubskenya.com
# ==============================================================================

DOMAIN=${1:-codingclubskenya.com}

# Auto-detect paths based on script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"
BACKEND_DIR="${PROJECT_DIR}/backend"
FRONTEND_SRC="${PROJECT_DIR}/../frontend-apk-web/codingclubskenya"
FRONTEND_OUT="${PROJECT_DIR}/../frontend-apk-web"
VENV_DIR="${PROJECT_DIR}/venv"

# Determine if we can use sudo
if [ "${EUID}" -eq 0 ]; then
  SUDO=""
elif sudo -n true 2>/dev/null; then
  SUDO="sudo"
else
  SUDO=""
  echo "WARNING: sudo not available. Service restarts will be manual."
fi

echo "========================================"
echo "Updating School Management System"
echo "========================================"
echo "Project: ${PROJECT_DIR}"
echo "Backend: ${BACKEND_DIR}"
echo "Frontend src: ${FRONTEND_SRC}"
echo "Frontend out: ${FRONTEND_OUT}"
echo "Domain: ${DOMAIN}"
echo ""

# ---- 1. Pull backend code ----
echo "[1/6] Pulling backend changes..."
cd "${BACKEND_DIR}"
git pull origin master

# ---- 2. Install/update Python packages ----
echo "[2/6] Installing Python dependencies..."
source "${VENV_DIR}/bin/activate"
pip install -r requirements.txt

# ---- 3. Django migrations ----
echo "[3/6] Running Django migrations..."
python manage.py migrate --settings=core.settings_production
python manage.py collectstatic --noinput --settings=core.settings_production

# ---- 4. Pull and build frontend ----
echo "[4/6] Pulling frontend changes..."
cd "${FRONTEND_SRC}"
git pull origin master

echo "[5/6] Building frontend..."
VITE_API_URL="https://${DOMAIN}" npm ci 2>/dev/null || VITE_API_URL="https://${DOMAIN}" npm install
VITE_API_URL="https://${DOMAIN}" npm run build

# ---- 5. Deploy frontend build ----
echo "[6/6] Deploying frontend files..."
mkdir -p "${FRONTEND_OUT}"
cp -r dist/* "${FRONTEND_OUT}/"
echo "  Copied dist/* to ${FRONTEND_OUT}/"

# ---- 6. Restart services ----
echo ""
if [ -n "${SUDO}" ]; then
  echo "Restarting services with sudo..."
  $SUDO systemctl restart gunicorn 2>/dev/null && echo "  gunicorn: OK"
  $SUDO systemctl restart celery 2>/dev/null && echo "  celery: OK"
  $SUDO systemctl reload nginx 2>/dev/null && echo "  nginx: OK"
else
  echo "No sudo - restarting gunicorn directly..."
  pkill -f "gunicorn.*core.wsgi" 2>/dev/null || true
  sleep 1
  cd "${BACKEND_DIR}"
  source "${VENV_DIR}/bin/activate"
  gunicorn --config "${PROJECT_DIR}/gunicorn.conf.py" core.wsgi:application --daemon \
    --pid "${PROJECT_DIR}/gunicorn.pid" \
    --access-logfile "${PROJECT_DIR}/logs/gunicorn_access.log" \
    --error-logfile "${PROJECT_DIR}/logs/gunicorn_error.log"
  echo "  gunicorn: started (daemon mode)"
  echo ""
  echo "NOTE: celery and nginx need manual restart by admin:"
  echo "  sudo systemctl restart celery"
  echo "  sudo systemctl reload nginx"
fi

echo ""
echo "========================================"
echo "Update complete!"
echo "========================================"
echo "Frontend: https://${DOMAIN}/schoolsystem/"
echo "Admin:    https://${DOMAIN}/admin/"