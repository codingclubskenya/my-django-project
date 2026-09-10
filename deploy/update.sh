#!/bin/bash
set -e

# Quick update script - run this for minor code updates
# Usage: ./deploy/update.sh

PROJECT_DIR="/var/www/school_backend"
DOMAIN=${1:-yourdomain.com}

echo "Updating School Management System..."

cd "${PROJECT_DIR}/backend"
source "${PROJECT_DIR}/venv/bin/activate"

# Pull latest code
git pull origin main

# Install any new dependencies
pip install -r requirements.txt

# Run migrations
python manage.py migrate --settings=core.settings_production

# Collect static files
python manage.py collectstatic --noinput --settings=core.settings_production

# Update frontend
cd "${PROJECT_DIR}/frontend_app"
npm ci 2>/dev/null || npm install
cat > .env.production << EOF
VITE_API_URL=https://${DOMAIN}/api
EOF
npm run build
cp -r dist/* /var/www/school_frontend/

# Restart services
systemctl restart gunicorn
systemctl restart celery
systemctl restart nginx

echo "Update complete!"
