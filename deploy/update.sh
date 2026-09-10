#!/bin/bash
set -e

# Quick update script - run this for minor code updates
# Usage: ./deploy/update.sh [domain]

PROJECT_DIR="/home/personal/personalweb/epk"
FRONTEND_SRC_DIR="${PROJECT_DIR}/frontend/codingclubskenya"
FRONTEND_OUT_DIR="/home/personal/personalweb/frontend-apk-web"
DOMAIN=${1:-codingclubskenya.com}

# Ensure we have root privileges for system commands
if [ "$EUID" -ne 0 ]; then
  SUDO="sudo"
else
  SUDO=""
fi

echo "Updating School Management System..."

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

# Update frontend
cd "${FRONTEND_SRC_DIR}"
npm ci 2>/dev/null || npm install

# Update API URL for production (no /api suffix - API calls already include it)
cat > .env.production << EOF
VITE_API_URL=https://${DOMAIN}
EOF

npm run build

# Copy built frontend files to output directory
mkdir -p "${FRONTEND_OUT_DIR}"
$SUDO cp -r dist/* "${FRONTEND_OUT_DIR}/" 2>/dev/null || cp -r dist/* "${FRONTEND_OUT_DIR}/"
$SUDO chown -R devops:devops "${FRONTEND_OUT_DIR}" 2>/dev/null || true

# Restart services
$SUDO systemctl restart gunicorn
$SUDO systemctl restart celery
$SUDO systemctl restart celery-beat
$SUDO systemctl reload nginx

echo "Update complete!"