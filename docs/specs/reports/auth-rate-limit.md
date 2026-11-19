# Auth rate limiting: built (2026-11-19)

Spec `docs/specs/auth-rate-limiting.md`, plan `reports/auth-rate-limit-plan.md`, administrator guide `docs/security/auth-rate-limiting.md`. Branch `feat/school-data-management` (backend + frontend). **Not deployed.**

## One change from the plan: django-axes is replaced
The plan kept axes with its database handler and said the 20-way parallel test would decide. It was clear before building that axes cannot pass it: it checks "is this account locked" first and records the failure afterwards, so 20 simultaneous requests all pass the check. The fix is to *reserve* the attempt before the password check, under a row lock. That needed an own engine (`accounts/lockout.py`, table `accounts_authlockout`), which also lets student PIN login, change-password and `/admin/login/` share it, and I could not verify axes' DRF behaviour (its source is outside what I may read here). So axes is no longer configured: its backend, middleware and settings are removed from production settings. The `axes` package stays in `requirements.txt` (no dependency change without your say-so; it can be dropped later) and its old tables stay in the database untouched.

## What was built
| Piece | Where |
|---|---|
| One account key for email (any case), phone (any Kenyan format), student admission no.; unknown or ambiguous identifiers get a keyed-hash key so they lock like real ones | `accounts/identity.py` |
| Atomic lock: 5 attempts reserved under `select_for_update`, 15-minute cool-off, reset on success, old failures forgotten, per-IP failed-login counter (cache, fail-open), `security.auth` log + `AuditLog` on lockout/unlock | `accounts/lockout.py`, `accounts/models.py` (`AuthLockout`, migration `0026`) |
| Login by email **or phone** (`identifier` or `email` field), student login, change-password (own counter, needs `current_password`), unlock endpoint `POST users/<id>/unlock/` | `accounts/views.py` |
| Same lock in front of Django's `authenticate()` for `/admin/login/` (no axes) | `accounts/backends.py` |
| One 429 body for locked, throttled and IP-limited (`code: auth_rate_limited`, `Retry-After`) | `accounts/lockout.py` (`AuthRateLimited`), throttles |
| Password reset on both endpoints: scoped 30/h per IP, per-address 3/h silent, no account lookup in the request, email sent by a Celery task (uniform response and timing); confirm endpoints throttled | `accounts/tasks.py`, `views.py`, `serializers.py`, `urls.py` |
| dj-rest-auth `password/change/` removed (404); `change-password/` is the one route | `accounts/urls.py` |
| Admin: Auth lockouts list + Unlock action, User action "Unlock selected accounts" | `accounts/admin.py` |
| `check_duplicates` lists phones shared by several login users (warning); `purge_auth_lockouts` | `management/commands/` |
| Production requires `REDIS_CACHE_URL` (fails at startup), must differ from the Celery broker DB number; cache ignores Redis outages | `core/settings_production.py` |
| Celery worker systemd unit; `deploy-release.sh` preflights the unit and `REDIS_CACHE_URL`, restarts via `systemctl`, pings | `deploy/epk-celery.service`, `deploy/deploy-release.sh` |
| Login accepts "email or phone", 429 messages with minutes on login, student login, forgot, reset and change-password | `frontend/.../Login.jsx`, `AuthContext.jsx`, `utils/authErrors.js`, pages |

## Found on the way
- **Reset emails never reached accounts stored with capitals** (e.g. `Name@school.com`): allauth's reset form lower-cases the input and matches case-sensitively. The reset email is now built by the worker from the account found case-insensitively, so those users can reset.
- The legacy `password-reset/request/` used to return the reset token in the response whenever `DEBUG` was on (dev only, `DEBUG=False` in production). It no longer does; with Celery the email is sent by the worker (console backend in dev).
- **The audit log recorded the first `X-Forwarded-For` entry, which the client writes** (so it could be forged, and behind Cloudflare it would have been a Cloudflare address). Audit, lockout and throttles now use one function (`core/client_ip.py`): the trusted last hop, validated as an IP. Test: `ClientIpTests` (forged first hops, forged `CF-Connecting-IP`, rotating forged hops against the IP failure limit, garbage in the header).
- M-Pesa callback (`shop/views.py`) already takes the last `X-Forwarded-For` entry, which is correct with the nginx change; before it, an IP allow-list there (if `MPESA_CALLBACK_ALLOWED_IPS` is set) would have seen Cloudflare addresses. Not changed.
- Student login previously called `check_password` directly, so axes never saw it; it is now covered.

## Spec tests (accounts/test_auth_rate_limit.py)
| Spec | Test |
|---|---|
| 1 five failures lock 15 min | `test_five_failures_lock_for_fifteen_minutes` (429, `Retry-After` about 900, right password refused) |
| 2 email and phone share the lock | `test_email_case_and_phone_share_one_lock` |
| 3 changing IP does not bypass | `test_changing_ip_does_not_bypass_the_account_limit` |
| 4 changing identifier does not bypass | same test plus `test_unknown_identifiers_lock_exactly_like_real_ones` |
| 5 success resets the counter | `test_success_resets_the_counter` |
| 6, 7 OTP | **not applicable: no OTP exists** (design in the plan, section 5) |
| 8 reset endpoints protected | `PasswordResetTests` (uniform on both endpoints, per-address 3/h, per-IP throttle, confirm throttled) |
| 9 concurrent requests | `ParallelAttemptTests`: 20 simultaneous attempts on PostgreSQL, exactly 5 reach the password check, 15 get 429 |
| 10 login after lockout expires | `test_user_can_log_in_after_the_lockout_expires` |
Also covered: phone login (unique, shared, inactive/passwordless excluded), student PIN lock across IPs and across schools, `/admin/login/` lock (and shared with API), change-password limits and the temporary-password first-login flow (login, 403 `password_change_required`, change, access), removed route, unlock (tenant scope, admin only, audit rows, Django admin action), no passwords or identifiers in the security log, 30 users behind one IP, an IP spraying many accounts.

## Results
- **Full suite on PostgreSQL 16 (throwaway container, removed afterwards): 819 tests, OK** (784 before; 35 new in `test_auth_rate_limit`, including 5 client-IP tests added with the Cloudflare change).
- After a final import tidy-up, the auth, password-reset, security, accounts and staff tests ran again on a fresh Postgres container: 131 tests, OK, including the 20-way parallel test (it is skipped on SQLite, which cannot row-lock).
- On SQLite three `repair_sites_history` tests error (`TRUNCATE ... CASCADE`); they did so before this work and pass on Postgres.
- Frontend: touched files parse with esbuild; not exercised in a browser this time.

## Pre-deploy checklist (you run these; nothing is deployed)
All on the server unless stated. SSH needs your approval each time; none of this was run.

**A. Before `deploy-release.sh` (one time)**
1. **Redis:** confirm it is running (`systemctl is-active redis-server`, `redis-cli ping`).
2. **`.env`** (do not paste it anywhere): add `REDIS_CACHE_URL=redis://localhost:6379/1`. Check `CELERY_BROKER_URL` is `.../0` or unset (default `/0`); the two database numbers must differ. Also confirm `NUM_PROXIES=1` or unset (default 1).
3. **Install the Celery unit** (sudo; paths assume the current layout, adjust if yours differ):
   ```
   sudo cp /home/devops/home/personal/personalweb/epk/deploy/epk-celery.service /etc/systemd/system/epk-celery.service   # after the release is checked out, or copy from your laptop
   sudo systemctl daemon-reload
   sudo systemctl enable epk-celery
   ```
   Do not start it yet: the hand-started worker is still running. `deploy-release.sh` stops that worker warmly (pidfile `/tmp/celery.pid`) and then starts the unit.
4. **sudoers:** the deploy user needs to restart the unit without a password, like it already does for gunicorn. Add (with `sudo visudo -f /etc/sudoers.d/epk-deploy`; adjust to the existing line for gunicorn): `devops ALL=(root) NOPASSWD: /bin/systemctl restart epk-celery`.
5. `mkdir -p /home/devops/home/personal/personalweb/epk/logs` (the script does it; the unit logs to `logs/celery.log`).
6. Fresh DB backup exists (the script takes one first; `backup.sh` if you want your own).
7. `manage.py check_duplicates` with production settings: read the new "login phone" lines (users sharing a number can only sign in by email).
8. Release order stays: backend (`deploy-release.sh`), then frontend (`deploy-static.sh`, STAGE_ONLY first), same window. The old frontend still works (it sends `email`; the backend accepts both fields).

**A2. Cloudflare real client IP (nginx; do it before the deploy, it is independent of the release)**
The API is behind Cloudflare, so with `NUM_PROXIES=1` alone every request would look like a Cloudflare address and the per-IP limits, lock records and audit log would be wrong. Fix is in nginx (see "Client IP behind Cloudflare" in `docs/security/auth-rate-limiting.md`); Django keeps `NUM_PROXIES=1` and trusts no header itself. I could not reach the server while preparing this, so the live vhosts have **not** been inspected: step 1 does that.
1. **Inspect (read-only):** `nginx -V 2>&1 | grep -o with-http_realip_module` must print the module name (it is built in by default; if empty, stop and tell me). List the vhosts that proxy to gunicorn: `sudo nginx -T 2>/dev/null | grep -nE "server_name|proxy_pass|X-Forwarded-For|real_ip"`. Each such `server { }` (api.codingclubskenya.com, and the apex codingclubskenya.com for `/api/` and `/admin/`) must contain `proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;`; add it if not.
2. **Backup:** `sudo cp -a /etc/nginx /etc/nginx.bak-$(date +%Y%m%d-%H%M)`.
3. **Patch:** install the snippet and include it in each of those server blocks:
   ```
   sudo mkdir -p /etc/nginx/snippets
   sudo cp /home/devops/home/personal/personalweb/epk/deploy/nginx/snippets/cloudflare-realip.conf /etc/nginx/snippets/cloudflare-realip.conf
   # in each server { } that proxies to gunicorn, next to the other includes:
   #     include /etc/nginx/snippets/cloudflare-realip.conf;
   ```
   (or copy the file from your laptop; the checkout on the server only has it after the release is checked out.)
4. **Test and reload (your sudo):** `sudo nginx -t` must say "syntax is ok / test is successful", then `sudo systemctl reload nginx`. If `nginx -t` fails, restore from the backup copy; nothing is reloaded until it passes.
5. **Verify the real IP (wrong login from your laptop):** note your public IP (`curl -s https://ifconfig.me`). Send a wrong sign-in for a throwaway address (not a real account; it only creates a harmless counter row):
   `curl -s -X POST https://api.codingclubskenya.com/api/auth/login/ -H 'Content-Type: application/json' -d '{"email":"nobody-test@example.com","password":"x"}'` (expect 401).
   Then in Django admin > Accounts > Auth lockouts, the row's **last IP** must be your public IP, not a Cloudflare one (`104.16.*`, `172.64.*`, `162.158.*`, ...). After the release is live, the same address also appears in the `security.auth` log (`event=lockout|denied|ip_limit ... ip=`; those lines only appear on lockout or limit, so the Auth lockouts page is the quick check) and in new audit-log rows.
6. **Verify spoofing is ignored (optional, from your laptop, straight to the origin so it is not via Cloudflare):** `curl -s --resolve api.codingclubskenya.com:443:213.199.41.219 -X POST https://api.codingclubskenya.com/api/auth/login/ -H 'CF-Connecting-IP: 1.2.3.4' -H 'X-Forwarded-For: 5.6.7.8' -H 'Content-Type: application/json' -d '{"email":"nobody-test2@example.com","password":"x"}'` then check that row's last IP: it must be your laptop's IP, never `1.2.3.4` or `5.6.7.8`.
7. **Rollback:** restore `/etc/nginx` from the backup, `sudo nginx -t`, `sudo systemctl reload nginx`. Refresh of the ranges later: see the snippet header and the guide.

**B. During**
9. `deploy-release.sh <ref>` runs: preflight (checks `REDIS_CACHE_URL` and the unit), backup, migrate (`accounts.0026_authlockout`, additive), restart gunicorn, health, then stops the hand-started worker and restarts `epk-celery`, pings it. Reset emails queued in the minute between the gunicorn restart and the worker restart may be lost (old worker does not know the new task); users can simply ask again.

**C. After (read-only checks I can run for you)**
10. `/api/healthz/` 200; `systemctl status epk-celery` active; `journalctl -u epk-celery -n 20`.
11. Five wrong sign-ins for a throwaway address return 401 then 429 with `Retry-After`; `accounts_authlockout` has the row (Django admin > Auth lockouts).
12. Password reset for a real test mailbox arrives (worker + SMTP); an unknown address returns the same 200.
13. `/admin/login/`: a locked admin sees the normal "incorrect" form message, not an error page.
14. Rollback: restore the backup and previous checkout as the script prints; the unit can stay (it just runs the old code). If Redis is the problem, production will not start: fix `REDIS_CACHE_URL` rather than reverting.

## Limits
- The Cloudflare nginx change is prepared but **not applied or verified on the server** (ssh timed out); steps A2 above.
- An account lock lets someone who knows an email lock that person out for 15 minutes (plan, section 4). Admins can unlock; it is never permanent.
- `anon:` counter rows are kept until purged: run `purge_auth_lockouts` from cron (not scheduled; Celery beat is not running in production).
- Sentry or log-based alerting on `security.auth` is not configured; the log lines are there to alert on.
