#!/bin/bash
set -e

# ==============================================================================
# Deployment script for School Management System
# Run this ON THE SERVER after copying project files there.
#
# Prerequisites:
#   - Ubuntu 22.04 server with SSH access
#   - Domain name (e.g., yourdomain.com) pointing to this server's IP
#   - Git repository access (to pull latest code)
#
# Usage:
#   chmod +x deploy/deploy.sh
#   ./deploy/deploy.sh
# ==============================================================================

DOMAIN=${1:-yourdomain.com}
EMAIL=${2:-admin@yourdomain.com}
PROJECT_DIR="/var/www/school_backend"
FRONTEND_DIR="/var/www/school_frontend"
GUNICORN_LOG_DIR="/var/log/gunicorn"
VENV_DIR="${PROJECT_DIR}/venv"

echo "========================================"
echo "School Management System - Deployment"
echo "========================================"

# ---- 1. Install system packages ----
echo "[1/9] Installing system packages..."
apt-get update
apt-get install -y \
    python3-pip python3-venv python3-dev \
    libpq-dev gcc \
    redis-server \
    nginx \
    git \
    certbot python3-certbot-nginx

# ---- 2. Setup PostgreSQL ----
echo "[2/9] Setting up PostgreSQL..."
apt-get install -y postgresql postgresql-contrib

# Create database and user
sudo -u postgres psql -c "DROP DATABASE IF EXISTS school_mgmt;" || true
sudo -u postgres psql -c "DROP USER IF EXISTS school_user;" || true
sudo -u postgres psql -c "CREATE USER school_user WITH PASSWORD 'GENERATED_ON_SERVER';"
sudo -u postgres psql -c "CREATE DATABASE school_mgmt OWNER school_user;"
sudo -u postgres psql -c "ALTER USER school_user CREATEDB;"

# ---- 3. Project directory setup ----
echo "[3/9] Setting up project directory..."
mkdir -p "${PROJECT_DIR}"
chown -R $USER:$USER "${PROJECT_DIR}"

# If this is a fresh deploy, clone from git
if [ ! -d "${PROJECT_DIR}/backend" ]; then
    echo "Cloning repository..."
    git clone https://github.com/YOUR_USERNAME/school-management.git "${PROJECT_DIR}/tmp_clone"
    cp -r "${PROJECT_DIR}/tmp_clone/backend" "${PROJECT_DIR}/backend"
    cp -r "${PROJECT_DIR}/tmp_clone/frontend/codingclubskenya" "${PROJECT_DIR}/frontend_app"
    rm -rf "${PROJECT_DIR}/tmp_clone"
fi

# ---- 4. Python virtual environment ----
echo "[4/9] Setting up Python virtual environment..."
if [ ! -d "${VENV_DIR}" ]; then
    python3 -m venv "${VENV_DIR}"
fi
source "${VENV_DIR}/bin/activate"

# Upgrade pip
pip install --upgrade pip

# Install Python dependencies
pip install -r "${PROJECT_DIR}/backend/requirements.txt"
pip install -r "${PROJECT_DIR}/backend/venv_requirements.txt" 2>/dev/null || \
    pip install Django==6.0.7 djangorestframework==3.17.1 \
    djangorestframework-simplejwt==5.5.1 django-filter==26.1.0 \
    django-cors-headers==4.9.0 drf-spectacular==0.30.0 \
    celery==5.6.3 redis==8.0.1 psycopg2-binary==2.9.10

# ---- 5. Environment configuration ----
echo "[5/9] Configuring environment..."

# Generate a random secret key if not set
if [ ! -f "${PROJECT_DIR}/.env" ]; then
    cat > "${PROJECT_DIR}/.env" << EOF
SECRET_KEY=$(python3 -c 'from django.core.management.utils import get_random_secret_key; print(get_random_secret_key())')
DB_ENGINE=django.db.backends.postgresql
DB_NAME=school_mgmt
DB_USER=school_user
DB_PASSWORD=GENERATED_ON_SERVER
DB_HOST=localhost
DB_PORT=5432
ALLOWED_HOSTS=${DOMAIN},www.${DOMAIN},localhost
CORS_ALLOWED_ORIGINS=https://${DOMAIN},https://www.${DOMAIN}
CELERY_BROKER_URL=redis://localhost:6379/0
CELERY_RESULT_BACKEND=redis://localhost:6379/0
MPESA_CONSUMER_KEY=
MPESA_CONSUMER_SECRET=
MPESA_BUSINESS_SHORTCODE=
MPESA_PASSKEY=
MPESA_CALLBACK_URL=https://${DOMAIN}/api/fees/mpesa/callback/
MPESA_ENVIRONMENT=sandbox
AI_ASSIST_API_URL=
AI_ASSIST_API_KEY=
AI_ASSIST_MODEL=claude-3-5-sonnet-20240620
DJANGO_SETTINGS_MODULE=core.settings_production
EOF
    echo "Generated .env file. Update MPESA credentials as needed."
fi

chmod 600 "${PROJECT_DIR}/.env"

# Copy gunicorn config
cp "${PROJECT_DIR}/backend/gunicorn.conf.py" "${PROJECT_DIR}/gunicorn.conf.py"

# ---- 6. Copy systemd service files ----
echo "[6/9] Setting up systemd services..."
cp "${PROJECT_DIR}/deploy/gunicorn.service" /etc/systemd/system/gunicorn.service
cp "${PROJECT_DIR}/deploy/celery.service" /etc/systemd/system/celery.service
cp "${PROJECT_DIR}/deploy/celery-beat.service" /etc/systemd/system/celery-beat.service

# Update paths in service files
sed -i "s|/var/www/school_backend|${PROJECT_DIR}|g" /etc/systemd/system/gunicorn.service
sed -i "s|/var/www/school_backend|${PROJECT_DIR}|g" /etc/systemd/system/celery.service
sed -i "s|/var/www/school_backend|${PROJECT_DIR}|g" /etc/systemd/system/celery-beat.service

# Update user in service files
sed -i "s|User=school|User=$USER|g" /etc/systemd/system/gunicorn.service
sed -i "s|Group=school|Group=$USER|g" /etc/systemd/system/gunicorn.service
sed -i "s|User=school|User=$USER|g" /etc/systemd/system/celery.service
sed -i "s|Group=school|Group=$USER|g" /etc/systemd/system/celery.service
sed -i "s|User=school|User=$USER|g" /etc/systemd/system/celery-beat.service
sed -i "s|Group=school|Group=$USER|g" /etc/systemd/system/celery-beat.service

systemctl daemon-reload
systemctl enable gunicorn celery celery-beat
systemctl start redis-server

# ---- 7. Django migrations & static files ----
echo "[7/9] Running Django migrations..."
cd "${PROJECT_DIR}/backend"
source "${VENV_DIR}/bin/activate"

python manage.py migrate --settings=core.settings_production
python manage.py collectstatic --noinput --settings=core.settings_production

# Create logs directory
mkdir -p "${PROJECT_DIR}/logs"

# ---- 8. Build and deploy React frontend ----
echo "[8/9] Building React frontend..."
mkdir -p "${FRONTEND_DIR}"

cd "${PROJECT_DIR}/frontend_app"
npm ci 2>/dev/null || npm install

# Update API URL for production
cat > .env.production << EOF
VITE_API_URL=https://${DOMAIN}/api
EOF

npm run build

# Copy built files to frontend directory
cp -r dist/* "${FRONTEND_DIR}/"
chown -R $USER:$USER "${FRONTEND_DIR}"

# ---- 9. Nginx configuration ----
echo "[9/9] Configuring Nginx..."
cp "${PROJECT_DIR}/deploy/nginx/school_management" /etc/nginx/sites-available/school_management

# Update domain and paths in nginx config
sed -i "s|yourdomain.com|${DOMAIN}|g" /etc/nginx/sites-available/school_management
sed -i "s|www.yourdomain.com|www.${DOMAIN}|g" /etc/nginx/sites-available/school_management
sed -i "s|/var/www/school_backend|${PROJECT_DIR}|g" /etc/nginx/sites-available/school_management
sed -i "s|/var/www/school_frontend|${FRONTEND_DIR}|g" /etc/nginx/sites-available/school_management

ln -sf /etc/nginx/sites-available/school_management /etc/nginx/sites-enabled/school_management
rm -f /etc/nginx/sites-enabled/default

# Test nginx config
nginx -t

# Start services
systemctl restart gunicorn
systemctl restart celery
systemctl restart celery-beat
systemctl restart nginx

# ---- 10. SSL with Let's Encrypt ----
echo "========================================"
echo "Setting up SSL with Let's Encrypt..."
echo "========================================"
certbot --nginx -d "${DOMAIN}" -d "www.${DOMAIN}" --email "${EMAIL}" --non-interactive --redirect || {
    echo "WARNING: Certbot failed. HTTPS may not be configured."
    echo "You can run: certbot --nginx -d ${DOMAIN} -d www.${DOMAIN}"
}

# ---- Summary ----
echo ""
echo "========================================"
echo "Deployment complete!"
echo "========================================"
echo ""
echo "Site: https://${DOMAIN}"
echo "Admin: https://${DOMAIN}/admin/"
echo "API docs: https://${DOMAIN}/api/docs/"
echo ""
echo "Next steps:"
echo "  1. Update the .env file at ${PROJECT_DIR}/.env with your M-Pesa credentials"
echo "  2. Create a superuser: source ${VENV_DIR}/bin/activate && cd ${PROJECT_DIR}/backend && python manage.py createsuperuser --settings=core.settings_production"
echo "  3. Update the PostgreSQL password: sudo -u postgres psql -c \"ALTER USER school_user WITH PASSWORD 'YOUR_NEW_PASSWORD';\""
echo ""
echo "To view logs:"
echo "  gunicorn: journalctl -u gunicorn -f"
echo "  celery:   journalctl -u celery -f"
echo "  nginx:    tail -f /var/log/nginx/error.log"
