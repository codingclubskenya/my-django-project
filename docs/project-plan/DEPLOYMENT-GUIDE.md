# Learning Pack — Deployment Guide

- **Status:** Baseline. Describes current deployment and required fixes. Production items marked *(reported)* come from the Oct 2026 SSH inspection and must be re-verified.

## Current production *(reported)*
- Contabo VPS, 4 GB RAM, Ubuntu. nginx terminates TLS (Let's Encrypt).
- Django via gunicorn systemd unit (`deploy/gunicorn.service`) on a unix socket, settings `core.settings_production`, env from `.env` (mode 600).
- PostgreSQL 16, Redis 7. Celery units exist in `deploy/` but **are not running**.
- Next.js distributor runs with `next start` on :3001. The staff React build is served at `/schoolsystem/`.
- MySQL + phpMyAdmin also run on the box (`/pma/` exposed).

## Pre-deploy blockers
1. ✅ *(fixed in R1)* `core/settings_production.py` now inherits `settings.py` and boots. **Still compare it with the live file on the server** (the live one has Redis cache/session config): set `REDIS_CACHE_URL` and port any other live-only setting.
2. ✅ *(fixed in R1)* Migrations committed and generated. Check `showmigrations` on prod first.
3. Fix gunicorn `--umask 000` → `007`, with the socket group set to `www-data`.
4. Install and enable `celery.service` and `celery-beat.service` (concurrency 2, `MemoryMax`).
5. Remove phpMyAdmin from the public nginx config, or restrict it by IP/VPN.

## Release R1 — critical security fixes (runbook)

Branches: backend `fix/critical-security`, distributor `fix/verified-payments`, frontend `fix/temporary-passwords`. **Ship all three together.** The guest checkout API changed (public token, no client confirmation), so an old storefront against the new backend breaks guest payments.

**0. Before release**
1. Get Safaricom Daraja credentials: sandbox first (developer.safaricom.co.ke), then production shortcode, passkey, consumer key/secret. Paybill vs till decides `MPESA_TRANSACTION_TYPE` / `MPESA_PARTY_B`.
2. Generate `MPESA_CALLBACK_SECRET` (`python -c "import secrets;print(secrets.token_urlsafe(32))"`). Set all `MPESA_*` vars in the server `.env` (see `.env.production.example`).
3. On a staging copy of the prod DB, run the duplicate-receipt pre-check SQL (DATABASE-CHANGES.md). If any rows come back, resolve them with finance first.
4. Run a **sandbox end-to-end test**: STK push to the sandbox test number → callback reaches `https://<host>/api/v1/shop/payments/mpesa/callback/<secret>/` → order shows paid. The callback must be reachable over public HTTPS.
5. Build the storefront on the server (Node ≥ 20.9) and the staff app (`npm run build`).

**1. Deploy** (low-traffic window)
1. `pg_dump -Fc` backup and record the filename.
2. Pull the three branches (or merge them to the release branches) and `pip install -r requirements.txt`.
3. `python manage.py migrate --plan` and review it, then `migrate`. Expected: payroll 0002, procurement 0002, accounts 0012, shop 0013, plus any of `da2896a`'s migrations not yet on prod.
4. Reload gunicorn, restart Next.js, publish the staff build.
5. Smoke test:
   - Login as a parent; place an order; pay with sandbox/prod (small amount); the page updates to paid by itself.
   - Login as admin; bulk-import one test student; download credentials; log in as that student → forced to change password.

**2. Data clean-up (same day)**
1. `python manage.py audit_superusers` and review the list. Then `python manage.py audit_superusers --demote --keep <each real platform operator email>`.
2. `python manage.py reset_default_passwords --dry-run` and review counts per school. Then `python manage.py reset_default_passwords --output /root/password-resets`.
3. Send each school admin their CSV over a secure channel (not email in plain text; e.g. a password-protected zip with the password by phone), then delete the CSVs.
4. Tell schools: affected users get a "set a new password" screen at next login. Admins can issue a new temporary password from the API (`reset-password`) if one is lost.

**Rollback:** redeploy the previous tags. Migrations are additive, so the old code ignores the new columns. Rotated passwords stay rotated, which is intended. If the storefront must roll back, the backend must too (guest API change).

## Release R2 — stage 2 (stacked on R1)

Backend `fix/stage2-tenancy-files` includes R1. It can ship with R1 as one release, or right after it. Migrations are state-only on PostgreSQL. Also deploy storefront `d683c78` and staff `ac53cc4` (upload accept lists).
After deploy, check: a school admin can still edit school details; HR (STAFF) can still use recruitment; uploading a `.doc` or an `.svg` gets a clear 400 message.

## Release R3 — private files, fee ledger (stacked on R1+R2)

Backend `fix/private-media` (includes R1, R2). Parent repo `security/nginx-private-media` (nginx files). Staff app `8e3874e`.
1. **nginx first or together:** copy the updated site config, run `sudo nginx -t`, then reload. Without the new config the private prefixes are still public; with it but without step 2, private downloads return empty responses.
2. Backend `.env`: `PRIVATE_MEDIA_ACCEL_PREFIX=/protected-media/` and `NUM_PROXIES=1`. The nginx `alias` in the `/protected-media/` block must equal the real `MEDIA_ROOT`.
3. `migrate` (fees 0003 is additive). Run the legacy pre-check SQL in DATABASE-CHANGES.md.
4. Smoke test: HR user opens a CV from the applications screen (new tab works, 10-minute link); a parent cannot open the same URL; `curl -I https://<host>/media/recruitment/...` returns 404; record a payment, reverse it, check the invoice returns to PENDING.
5. Old links: any bookmarked `/media/<private path>` URL stops working by design. Existing files keep their current paths.
6. Release APK signing: see SECURITY-AUDIT H7 before building a distributable APK.

## Release procedure (target)
1. CI green: ruff, pytest, frontend builds, dependency audit.
2. Back up: `pg_dump -Fc` to off-site storage (R2). Record the dump name in the release note.
3. `git pull` the tagged release. `pip install -r requirements.txt`.
4. `python manage.py migrate --plan` and review it, then `migrate`.
5. `collectstatic --noinput`. Build the frontends.
6. `systemctl reload gunicorn`. Restart celery. Restart Next.js.
7. Smoke test: login per role, `/api/v1/health` (to add), one order flow in sandbox.
8. **Rollback:** redeploy the previous tag. Restore the DB from the pre-release dump only if a migration was destructive. Every migration must state whether it can be reversed (DATABASE-CHANGES.md).

## Backups & monitoring (to implement)
- Nightly `pg_dump` with 14 daily and 8 weekly copies kept, pushed to R2. Run a monthly restore drill on a scratch DB.
- Sentry (DSN via env) for Django, Next.js and Flutter.
- Uptime check on `/api/v1/health`. Rotate logs with logrotate. Alert on disk > 80% and memory.

## Secrets
- Never commit secrets. Required env vars: `SECRET_KEY`, `DB_*`, `REDIS_URL`, `CHAMAGO_API_KEY` (+ webhook secret), `MPESA_*` if using Daraja, `AI_ASSIST_API_KEY`, `R2_*`, `SENTRY_DSN`, `EMAIL_*`.
