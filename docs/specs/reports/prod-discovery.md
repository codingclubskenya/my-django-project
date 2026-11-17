# Production discovery (read-only), 2026-11-15

Host `contabo` (vmi3555221), up 4 weeks. Nothing was changed. No secrets printed.
Limits: `sudo` needs a password, so there was no `postgres` superuser access and no root crontab. Everything was read as user `devops`.

## 1. Deployment

Shared server: it also runs unrelated DeHus apps (`deheus-api`, `deheus-node`, `/home/devops/djangoapp`). Ours is under `/home/devops/home/personal/personalweb/`.

| Piece | Path | Remote | Branch @ commit | Notes |
|---|---|---|---|---|
| backend (epk) | `.../personalweb/epk` | github fattym/epk | **qa/hardening-fixes** @ 7f2d760 (2026-10-20) | **35 uncommitted modified files** (many `views.py`, `settings.py`, `settings_production.py`) + untracked `core/schema_generator.py`, `deploy/redis/` |
| distributor | `.../personalweb/disributor` (sic) | github fattym/disributor | main @ cd52e8e (2026-10-24) | 5 dirty entries. Static export served from `out/` |
| frontend | `.../personalweb/frontend-apk-web/codingclubskenya` | github fattym/frontend-apk-web | development @ 19e3cd3 (2026-10-20) | 7 dirty entries. Served from `dist/` |

- Python 3.12.3 (`epk/venv`), Node v20.20.2, npm 10.8.2.
- Services:
  - `gunicorn.service`: epk, 3 workers, unix socket `epk.sock`.
  - Celery worker: running as a stray process (`--pidfile=/tmp/celery.pid`), **not a systemd unit**.
  - `disributor-next.service`: **crash-looping** (`npm run start -p 3001`, exit 1, auto-restart). nginx serves the static `out/` dir instead.
  - Also `nginx`, `postgresql@16-main`, `redis-server`.
- nginx vhosts: `api.codingclubskenya.com` (epk socket), `erp.codingclubskenya.com` (React `dist/`), `learningpack.codingclubskenya.com` (distributor `out/`), plus the DeHus and phpMyAdmin hosts.
- **Auto-deploy**: `auto-deploy.timer` runs `deploy-auto.sh` **every 15 minutes**. It does:
  1. `git pull` in all three repos.
  2. `npm run build` for distributor and frontend.
  3. `manage.py migrate --settings=core.settings_production`.
  4. `collectstatic`.
  5. Restart gunicorn and disributor-next.
  6. Copy `personalweb/nginx.conf` over `/etc/nginx/nginx.conf`, then `nginx -t` and reload.

  There is no backup step, no `check_duplicates` or `check_stream_years`, and `set -e` only. The server's checked-out branches are what it pulls. Merging or pushing our branches there would migrate production within 15 minutes.
- The `epk` and `frontend-apk-web` git remote URLs embed a credential. Masked here. Consider rotating or moving to a deploy key.

## 2. Database

- Engine PostgreSQL (`DB_ENGINE=django.db.backends.postgresql`, host 127.0.0.1:5432, db `school_mgmt`, `DJANGO_SETTINGS_MODULE=core.settings_production`).
- Server: **PostgreSQL 16.15** (Ubuntu 24.04). `pg_dump` **16.15**, same major version.
- DB size: **19 MB**.

## 3. Migrations and deploy check

- Pending migrations against the **currently checked-out code** (qa/hardening-fixes): **0**. Our feature branches' migrations are not on the server, so they would all be pending after a pull.
- `check --deploy`: 20 issues, **all WARNINGS, no errors**. One is `axes.W004` (deprecated `AXES_USE_USER_AGENT`). The other 19 are drf_spectacular schema warnings (type hints and operationId collisions). No security warnings (SSL/HSTS/cookies pass).

## 4. Counts (current server code)

- `accounts.StaffProfile`: **model does not exist** on the server code. `payroll.StaffProfile`: **0** rows.
- Schools: **1**. Users: **5**, by role: ADMIN 2, DISTRIBUTOR 1, blank 2.
- `Stream`: **0 rows**, and it has **no `academic_year` field** yet (fields: name, grade, pathway, school). So `check_stream_years` has nothing to check on current data. Re-run after the migration if streams are created in between.

## 5. Env variable names

- `.env` names present: SECRET_KEY, DB_ENGINE, DB_NAME, DB_USER, DB_PASSWORD, DB_HOST, DB_PORT, ALLOWED_HOSTS, CORS_ALLOWED_ORIGINS, CELERY_BROKER_URL, CELERY_RESULT_BACKEND, DJANGO_SETTINGS_MODULE (listed twice), MPESA_CONSUMER_KEY, MPESA_CONSUMER_SECRET, MPESA_BUSINESS_SHORTCODE, MPESA_PASSKEY, MPESA_CALLBACK_URL, MPESA_ENVIRONMENT.
- **FRONTEND_URL: not set.** **PRIVATE_MEDIA_ACCEL_PREFIX: not set.** Both are needed before our branches deploy, and the nginx internal location must match the accel prefix.
- **DEBUG**: not in `.env`. `settings_production.py` hard-codes `DEBUG = False`.
- The `.env` file has a duplicate `DJANGO_SETTINGS_MODULE` line (harmless, tidy later).

## 6. Backups and disk

- Disk `/`: 96G, 14G used, **83G free** (14%).
- **No working backup exists.**
  - `/home/devops/scripts/backups/backup_db.sh` writes to `/home/devops/backups/postgresql/`.
  - The script targets `DB_NAME="school_db"`, **not `school_mgmt`**.
  - The only dumps are 5 files dated **2026-09-17**, each **20 bytes** (an empty gzip).
  - There is no cron entry for devops, and none was found in `/etc/cron*`. The root crontab could not be read.
  - The only backup timer is the OS `dpkg-db-backup`.
- Media lives in `epk/media` (not backed up either).

## Blockers before any production change
1. Take a real backup first, `pg_dump school_mgmt` with the 16.15 client. The DB is only 19 MB. Verify it is non-empty and restorable.
2. Decide how to stop or bypass `auto-deploy.timer` (15-min pull, migrate and restart) so our branches deploy only deliberately.
3. Reconcile the 35 uncommitted files in prod `epk` before any pull. Otherwise `git pull` may conflict and `set -e` aborts it midway, or the changes get lost.
4. Set `FRONTEND_URL` and `PRIVATE_MEDIA_ACCEL_PREFIX`, and add the matching nginx internal location (nginx change, needs confirmation).
5. Fix or replace the crash-looping `disributor-next` and the non-systemd Celery worker.
