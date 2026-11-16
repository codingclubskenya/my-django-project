# Release 1 deploy log (2026-11-16)

## Step 1: laptop (done)
- backend `fix/private-media`: `git rm deploy/deploy.sh`; added deploy-release.sh + deploy-static.sh; Celery restart added (SIGTERM warm stop of /tmp/celery.pid, then `celery -A core worker --detach --pidfile=/tmp/celery.pid --logfile=/tmp/celery.log`, then pid + `inspect ping` check). Live worker args (read-only ps): `python3 -m celery -A core worker --pidfile=/tmp/celery.pid --logfile=/tmp/celery.log` (no -B, concurrency or queue flags).
- Merged into `feat/school-data-management`.
- Pushed: backend fix/private-media + feat/school-data-management, frontend release-1, distributor release-1.

## Step 2: nginx (done, verified)
- Patched api/learningpack/main .conf (mtime 2026-11-16 08:45); grep counts of new blocks: api 2, learningpack 1, main 1.
- Backup dir /root/nginx-backup-20261116: NOT verified by me (root-only, sudo needs password).
- Canary media/recruitment/canary-1794815185.txt (real file on disk): api 404, erp 404, learningpack 404. Control /media/shop/products/2026/books_DrBmnvY.jpg via api: 200. Canary and the (previously nonexistent) recruitment dir removed.
- Earlier pre-patch curls (404s on nonexistent files) were not valid evidence.

## Step 3: server prep (done)
- epk was on qa/hardening-fixes @ 7f2d760 with many modified tracked files (incl. core/settings.py, core/settings_production.py). `git stash push -m prod-schema-workaround-2026-11-15` -> stash@{0}. Status after: only untracked `core/schema_generator.py`, `deploy/redis/`.
- Scripts copied to ~devops/deploy-scripts/ (sha256 match with fix/private-media: release c4b08d8f..., static 86cf053b...).
- .env key counts: PRIVATE_MEDIA_ACCEL_PREFIX 2, FRONTEND_URL 2, DJANGO_SETTINGS_MODULE 2 (duplicate lines).
- origin/fix/private-media = c7dd924; HEAD is 0 ahead / 36 behind (fast-forward). requirements.txt unchanged; 31 migration files differ.

## Step 4 attempt 1: FAILED at pip (user rolled checkout back to qa/hardening-fixes 7f2d760; nothing installed, no migrations)
- Cause: requirements.txt had nonexistent pins (ruff==3.9.4, pytest-django==4.10.1, pytest-cov==6.0.2).
- Fix on fix/private-media: dev tools moved to requirements-dev.txt (ruff 0.17.5, pytest-django 4.14.0, pytest-cov 6.3.0); prod pins aligned to tested venv_new (axes 6.5.2->8.3.1, django-redis 5.2.0->7.0.0, guardian 3.3.0->3.5.0, anthropic 0.49.0->1.15.0, sentry-sdk 2.19.0->2.72.0, requests, PyJWT, allauth, redis, psycopg2) and gunicorn 26.2.0 / python-dotenv 1.2.3 = prod's current. Django stays 6.0.7 (prod has 6.1.1: pip will downgrade it).
- Verified in fresh py3.12 venv: pip install -r requirements.txt ok, pip check ok, `manage.py check --settings=core.settings_production` (dummy env, with and without SENTRY_DSN) passes.
- deploy-release.sh: dry-run resolve of target requirements before checkout, pip retry x3, auto-restore of previous checkout on failure before repair_sites_history.
- Prod venv lacked only: anthropic, sentry-sdk, requests, django-environ (allauth/axes/guardian/django-redis were present, older/newer versions).

## Step 4 attempt 2 prep: Django 6.1.1 + tests + rehearsal (2026-11-16)
- Pins: Django==6.1.1 (prod's). DRF 3.17.1 crashes on Django 6.1 (`cannot import name 'cc_delim_re'`), so djangorestframework==3.18.1 (prod's). Fresh py3.12 venv from requirements-dev.txt: pip check clean.
- Tests (core.settings_test, full suite, no --parallel):
  - fix/private-media: 463 tests. SQLite (default test DB): 3 errors, all `accounts.test_repair_sites_history` (`DROP TABLE ... CASCADE` is Postgres-only). Same 3 errors on old venv_new/Django 6.0.7, so pre-existing and not 6.1-related. On Postgres 16: 463 OK.
  - feat/school-data-management (merged): 636 tests. SQLite: same 3 errors. Postgres: 636 OK.
- Rehearsal on a fresh restore of school_mgmt-20261116-085105.dump (PG 16 private instance, 136 migrations, 5 users, no django_site), new venv, core.settings_production: repair_sites_history ok (sites 0001+0002 recorded) -> migrate 28 applied, exit 0, 40 s (166 migration rows) -> check --deploy --fail-level ERROR exit 0 (421 warnings: 383 W001 + 38 W002 drf_spectacular) -> 0 unapplied, makemigrations --check clean, users 5, 1 Site row.
- deploy-release.sh unchanged (sha256 32cbfb0c...), so ~/deploy-scripts is current.
- Pushed fix/private-media and feat/school-data-management.

## Step 4 (backend) result, 2026-11-16
- Deploy: migrations OK, gunicorn restarted (old health path /api/health/ gave 401 = health-records app; not rolled back). epk on 08b200e then; Celery restarted by hand (old pid 1314749 -> 26964, `inspect ping` pong). Live checks: /api/schema/ 200, /api/v1/storefront/schools/ 200, bad login 401, gunicorn error log clean.
- /api/healthz/ + script change pushed (fix/private-media 7f7652c, feat 1b75774); ships with next backend release.
- CORS: .env already had learningpack + erp origins. Live: GET/OPTIONS with Origin learningpack -> ACAO echoed, headers incl. authorization; erp OK; evil.example gets no ACAO.
- FOUND: anonymous GET /api/shop/products/ (and /api/v1/...) returns 500 (shop/views.py:93 `user.school` on AnonymousUser) instead of 401. Public list /api/shop/public/ is fine (200).

## Step 5: static sites (in progress)
- deploy-static.sh gained STAGE_ONLY / USE_RELEASE (pushed).
- distributor release-1 first stage (NEXT_PUBLIC_API_URL=/api): relative /api not proxied on learningpack vhost (returns index.html); live build had the same value. Not swapped.
- distributor .env.local backed up (.env.local.bak-20261116), NEXT_PUBLIC_API_URL=https://api.codingclubskenya.com/api (only NEXT_PUBLIC_* var). Re-stage: build OK, api host in 4 JS files, 1 file still has the localhost:8000 fallback (dead code), image_url from API are absolute api-host URLs (133/133); 100 /shop/<id> pages pre-rendered (generateStaticParams slices to 100 of 133 products; no placeholder) -> script aborted on its shop/placeholder check. Not swapped.
- frontend release-1: VITE_API_URL=https://codingclubskenya.com (tracked .env.production and server copy); apex proxies /api/ to gunicorn (200 JSON). localhost only in axios/URL library code. Same as live dist.

## Step 5 result: static sites swapped (2026-11-16)
- distributor release-1 (78f8c2a): `generateStaticParams` = every product id + `placeholder` (134 `/shop/*` dirs, 181 html, 62 js, 19M); API host in 4 JS files. Swapped; `out.prev` kept as rollback. Live checks on learningpack: `/`, `/shop/`, `/bookshop/`, `/cart/`, `/shop/135/` all 200; product image on the API host 200.
- frontend release-1 (a6a0dcc): 5 files, 2.1M. Swapped. erp `/` and `/parent-dashboard` 200 (SPA index); main JS asset 200 `application/javascript`.

## Anonymous 500 fix (backend, shipped to branches, NOT yet deployed)
- `f4f0b86`: `IsAuthenticatedAdminOrReadOnly` (anonymous gets 401) on school-scoped viewsets (academics reference data, events, shop categories/products/variants, transport driver students). `core/test_anonymous_sweep.py` hits every routed endpoint anonymously and asserts no 5xx, plus 401 checks. Full suite 468 OK on Postgres 16. Known, left alone: allauth HTML signup (500) and OPTIONS on the Swagger page.
- Merged into feat/school-data-management; ships with the next backend release together with `/api/healthz/`.

## Step 6: learningpack `/shop/<id>/` rewrite (pending, run by the user)
- Live vhost has no placeholder fallback yet. Snippet from `docs/prod-capture/nginx-proposal/learningpack-shop-rewrite.snippet` goes before `location / {` (backup, `nginx -t`, reload). Until it is applied, product ids not pre-rendered (new products) 404 on a direct URL; the 133 current ones work. Verify afterwards: `/shop/135/` 200, `/shop/999999/` placeholder 200, `/shop/` unchanged.

## Step 7: backups (done)
- `backend/deploy/backup.sh` (backend 1142162, on fix/private-media and feat): pg_dump -Fc + media tarball under `~devops/backups`, aborts on empty dump / <=100 TOC entries / unreadable tarball, prunes own files older than 14 days. Installed at `~devops/deploy-scripts/backup.sh`.
- Test run: `school_mgmt-20261116-173238.dump` 916299 bytes, 2077 TOC entries; `media-20261116-173238.tgz` 25M.
- crontab (devops): `30 2 * * * $HOME/deploy-scripts/backup.sh >> $HOME/backups/backup.log 2>&1`.
- Backups are on the same host (no offsite copy yet).

## Open items
- Apply step 6 nginx rewrite and verify.
- nginx backup dir `/root/nginx-backup-20261116` unverified (needs sudo).
- Next backend release: healthz + anonymous fix + backup.sh (repo copy).
- Anonymous-fix and healthz are not live; live `/api/shop/products/` still 500s for anonymous until then.
