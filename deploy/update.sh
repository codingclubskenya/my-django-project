#!/bin/bash
set -e

# Quick update script - run this for minor code updates
# Usage: ./deploy/update.sh [domain]
#
# This script auto-detects its location relative to the project root.
# It works even without sudo privileges for service restarts.

# Auto-detect project directory based on script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"
FRONTEND_SRC_DIR=""
FRONTEND_OUT_DIR=""
DOMAIN=${1:-codingclubskenya.com}

# Try to detect frontend source directory
for possible in \
  "${PROJECT_DIR}/frontend/codingclubskenya" \
  "${PROJECT_DIR}/frontend_app" \
  "$(dirname "${PROJECT_DIR}")/frontend/codingclubskenya" \
  "$(dirname "${PROJECT_DIR}")/frontend_app"; do
  if [ -d "${possible}" ]; then
    FRONTEND_SRC_DIR="${possible}"
    break
  fi
done

# Try to detect frontend output directory
for possible in \
  "$(dirname "${PROJECT_DIR}")/frontend-apk-web" \
  "${PROJECT_DIR}/../frontend-apk-web" \
  "${PROJECT_DIR}/dist"; do
  if [ -d "${possible}" ] || mkdir -p "${possible}" 2>/dev/null; then
    FRONTEND_OUT_DIR="${possible}"
    break
  fi
done

# Fallback
if [ -z "$FRONTEND_SRC_DIR" ]; then
  FRONTEND_SRC_DIR="${PROJECT_DIR}/frontend/codingclubskenya"
fi
if [ -z "$FRONTEND_OUT_DIR" ]; then
  FRONTEND_OUT_DIR="${PROJECT_DIR}/../frontend-apk-web"
  mkdir -p "${FRONTEND_OUT_DIR}"
fi

# Determine if we can use sudo
if [ "${EUID}" -eq 0 ]; then
  SUDO=""
elif sudo -n true 2>/dev/null; then
  SUDO="sudo"
else
  SUDO=""
  echo "WARNING: sudo not available. Service restarts will be skipped."
fi

echo "Updating School Management System..."
echo "Project dir: ${PROJECT_DIR}"
echo "Frontend src: ${FRONTEND_SRC_DIR}"
echo "Frontend out: ${FRONTEND_OUT_DIR}"
echo "Domain: ${DOMAIN}"

# Activate virtual environment
cd "${PROJECT_DIR}/backend"
source "${PROJECT_DIR}/venv/bin/activate"

# Pull latest code
git pull origin master

# Install any new dependencies
pip install -r requirements.txt

# Run migrations
python manage.py migrate --settings=core.settings_production

# Collect static files
python manage.py collectstatic --noinput --settings=core.settings_production

# Build frontend
cd "${FRONTEND_SRC_DIR}"
npm ci 2>/dev/null || npm install

# Update API URL for production (no /api suffix - API calls already include it)
cat > .env.production << EOF
VITE_API_URL=https://${DOMAIN}
EOF

npm run build

# Copy built frontend files
mkdir -p "${FRONTEND_OUT_DIR}"
cp -r dist/* "${FRONTEND_OUT_DIR}/"

# Restart services (with fallback if sudo is not available)
SERVICES_STARTED=false
if [ -n "$SUDO" ]; then
  $SUDO systemctl restart gunicorn 2>/dev/null && SERVICES_STARTED=true && echo "gunicorn restarted"
  $SUDO systemctl restart celery 2>/dev/null && echo "celery restarted"
  $SUDO systemctl restart celery-beat 2>/dev/null && echo "celery-beat restarted"
  $SUDO systemctl reload nginx 2>/dev/null && echo "nginx reloaded"
fi

if [ "$SERVICES_STARTED" = false ]; then
  echo "WARNING: Could not restart services. Please restart them manually:"
  echo "  sudo systemctl restart gunicorn celery celery-beat"
  echo "  sudo systemctl reload nginx"
fi

echo "Update complete!"