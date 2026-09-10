#!/bin/bash
set -e

# ==============================================================================
# Quick update script - run this for minor code updates
# Usage: ./deploy/update.sh [domain]
#
# Auto-detects project directory based on script location.
# Works for both sudo and non-sudo environments.
# ==============================================================================

# Auto-detect project directory based on script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"
VENV_DIR="${PROJECT_DIR}/venv"
FRONTEND_SRC_DIR="${PROJECT_DIR}/frontend_app"
FRONTEND_OUT_DIR="${PROJECT_DIR}/../frontend-apk-web"
DOMAIN=${1:-codingclubskenya.com}

# Ensure frontend directories exist
mkdir -p "${FRONTEND_OUT_DIR}"

# Determine if we can use sudo for service restarts
if [ "${EUID}" -eq 0 ]; then
  SUDO=""
elif sudo -n true 2>/dev/null; then
  SUDO="sudo"
else
  SUDO=""
  echo "WARNING: sudo not available. Service restarts will be skipped."
fi

echo "========================================"
echo "Updating School Management System"
echo "========================================"
echo "Project: ${PROJECT_DIR}"
echo "Domain:  ${DOMAIN}"
echo "Sudo:    ${SUDO:-none}"
echo ""

# ---- 1. Update backend code ----
echo "[1/6] Pulling latest code..."
cd "${PROJECT_DIR}/backend"
git pull origin master

# ---- 2. Install/update Python dependencies ----
echo "[2/6] Installing dependencies..."
source "${VENV_DIR}/bin/activate"
pip install -r requirements.txt

# ---- 3. Django migrations ----
echo "[3/6] Running migrations..."
python manage.py migrate --settings=core.settings_production
python manage.py collectstatic --noinput --settings=core.settings_production

# ---- 4. Build frontend ----
echo "[4/6] Building frontend..."
cd "${FRONTEND_SRC_DIR}"
VITE_API_URL="https://${DOMAIN}" npm ci 2>/dev/null || VITE_API_URL="https://${DOMAIN}" npm install
VITE_API_URL="https://${DOMAIN}" npm run build

# ---- 5. Deploy frontend ----
echo "[5/6] Deploying frontend..."
mkdir -p "${FRONTEND_OUT_DIR}"
cp -r dist/* "${FRONTEND_OUT_DIR}/"

# ---- 6. Restart services ----
echo "[6/6] Restarting services..."
SERVICES_RESTARTED=false

if [ -n "${SUDO}" ]; then
  $SUDO systemctl restart gunicorn 2>/dev/null && SERVICES_RESTARTED=true && echo "  gunicorn: restarted"
  $SUDO systemctl restart celery 2>/dev/null && echo "  celery: restarted"
  $SUDO systemctl restart celery-beat 2>/dev/null && echo "  celery-beat: restarted"
  $SUDO systemctl reload nginx 2>/dev/null && echo "  nginx: reloaded"
else
  echo "  No sudo access - restarting gunicorn directly..."
  pkill -f "gunicorn.*core.wsgi" 2>/dev/null || true
  sleep 1
  cd "${PROJECT_DIR}/backend"
  source "${VENV_DIR}/bin/activate"
  gunicorn --config "${PROJECT_DIR}/gunicorn.conf.py" core.wsgi:application &
  SERVICES_RESTARTED=true
  echo "  gunicorn: started (PID in background)"
  echo "  NOTE: Use startup.sh for full service management"
fi

if [ "${SERVICES_RESTARTED}" = true ]; then
  echo ""
  echo "========================================"
  echo "Update complete!"
  echo "========================================"
  echo "Site:   https://${DOMAIN}/schoolsystem/"
  echo "Admin:  https://${DOMAIN}/admin/"
  echo "API:    https://${DOMAIN}/api/docs/"
else
  echo ""
  echo "WARNING: Services may still be running. Manual restart may be needed."
fi