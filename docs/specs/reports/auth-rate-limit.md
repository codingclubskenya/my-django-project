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

## Browser pass (local dev servers, seed accounts; 2026-11-19)
| Path | Result |
|---|---|
| Login page | Field reads "Email or phone number" |
| Wrong password | Shows the server's message, form keeps its values. **Bug found and fixed:** the axios 401 interceptor treated a failed sign-in as an expired token, tried a refresh and reloaded the page (message lost). Sign-in endpoints now skip it |
| Lockout | Throwaway identifier, 5 wrong attempts then the 6th: "Too many attempts. Please wait N minutes". **Bug found and fixed:** the minutes were missing because CORS hid `Retry-After` from the SPA (`CORS_EXPOSE_HEADERS`, test added); a re-attempt later showed "13 minutes", counting down |
| Email sign-in | admin: dashboard |
| Phone sign-in | teacher by `0722 000 111` (spaces on purpose): teacher dashboard |
| Student tab | wrong PIN: "Invalid credentials"; right PIN: student dashboard |
| Temporary password | login redirects to the change-password page; wrong current password shows "Current password is incorrect"; right one lands on the dashboard (the request takes about 4 s on the dev machine: the password is hashed twice, once for the limit check and once in the serializer; fine, but noted) |
| Forgot password | unknown address: the normal "If an account exists..." confirmation. **Found:** with no Redis the request hung about 19 s retrying the broker and result store; now `ignore_result` + short broker timeouts give about 2 s, and `CELERY_TASK_ALWAYS_EAGER=1` runs tasks inline in dev |
Not done in the browser: `/admin/login/` (covered by tests; the page is Django's own form).
The local dev database also needed `migrate` for `accounts.0026` first: an unmigrated database gives a 500 on login (the table is missing). The deploy script migrates before restarting.

## Rehearsal on a fresh prod dump (2026-11-19)
Fresh dump taken with the server's own `~/deploy-scripts/backup.sh` (`school_mgmt-20261119-123006.dump`, 1.08 MB), copied to a throwaway directory, restored into a throwaway `postgres:16` next to a throwaway `redis:7`, run with `core.settings_production`. Checked that the run really used the restored Postgres (my first pass used the local SQLite because a dev `.env` supplies `DB_ENGINE`: always set `DB_ENGINE` explicitly). Containers, dump and logs deleted afterwards.
| Step | Result |
|---|---|
| Restore | OK; 6 users, accounts at `0025_phone_canonical` |
| `check_duplicates` | all OK, including the new "login phone" report (0 shared) |
| `check --deploy --fail-level ERROR` | passes (production settings with `REDIS_CACHE_URL=.../1` and broker `.../0`) |
| `repair_sites_history`, `migrate` | `accounts.0026_authlockout` applied, nothing else; `makemigrations --check`: no changes |
| Lockout on real Postgres + real Redis | 5 x 401, then 429 with `Retry-After` 898; stored IP is the trusted last `X-Forwarded-For` hop (a forged first hop ignored) |
| Identity on prod data | for every account email in any letter case gives one key; phone gives the same key as email for both users who have a phone; no shared phones |
| Password reset on prod data | known address (stored case and upper-case typed): 200 and exactly one email; unknown: same 200 and no email; the emailed link completes through `password/reset/confirm/` and the new password signs in (also with the email typed in upper case) and resets the counter |
| `purge_auth_lockouts` | ran, deleted the idle row |
| Celery worker with the unit's command (`python -m celery -A core worker`) | starts, `inspect ping` answers (the deploy script's check), both reset tasks registered, a queued reset was executed by the worker (one email for the known address, none for the unknown one), SIGTERM gave a warm shutdown |
| Auth, reset, security, accounts, staff, students tests on Postgres | 162 OK |
Things the prod copy shows (not changed): 2 of the 6 accounts have a placeholder email without a dot in the domain (so `Enter a valid email address.` for a reset request) and an unusable password, so they can sign in neither by email, phone nor reset; one placeholder address has capitals. If those are parent accounts, parents imported without a real email have no way in today: worth a decision separate from this release.

## Server steps (exact commands; you run them, nothing here was run for you)
Facts I checked read-only on 2026-11-19: Redis active and answering, `db0` holds the Celery broker (3 keys), no password; `.env` has no `REDIS_CACHE_URL`, has `CELERY_BROKER_URL` ending `/0`, no `NUM_PROXIES` (production default is 1, correct); live unit is `gunicorn.service` (active); **`epk.service` is also enabled but inactive** (see "Cleanup"); `devops` needs a sudo password; nginx 1.24.0 with the realip module; vhost files `codingclubskenya-{api,deheus-api,deheus,learningpack,main,pma}.conf` (contents need sudo to read); the daily backup cron exists; `~/deploy-scripts/{deploy-release,deploy-static,backup}.sh` are copies of the repo's scripts (this release changes `deploy-release.sh`). I also ran `git fetch origin` in the server's `epk` checkout so `origin/feat/school-data-management` (b31c743) is available for `git show`; it changes no files.

All blocks run on the server as `devops`. Set once per shell:
```
APP=/home/devops/home/personal/personalweb/epk
REF=origin/feat/school-data-management     # use the tag or sha you actually release
cd $APP && git fetch origin && git rev-parse --short $REF
```

**1. `.env`: REDIS_CACHE_URL (no sudo).** Redis database 1 for the cache, 0 stays Celery's.
```
umask 077; cp -a $APP/.env ~/backups/env-$(date +%Y%m%d-%H%M).bak      # secrets: keep it 600
grep -c '^REDIS_CACHE_URL=' $APP/.env                                 # expect 0
printf '\nREDIS_CACHE_URL=redis://localhost:6379/1\n' >> $APP/.env
grep -nE '^(REDIS_CACHE_URL|CELERY_BROKER_URL)=' $APP/.env | sed -E 's#(redis://)[^@/]*@#\1***@#'   # cache ends /1, broker ends /0
redis-cli -n 1 ping                                                   # PONG
```
Rollback: restore the `.env-*.bak` copy. (Nothing reads the new line until the release; the old code ignores it.)

**2. Celery unit (sudo).** The file is in the release, not yet checked out, so read it from git, look at it, verify it, then install. Do not start it (the hand-started worker is still running; the deploy script stops that worker warmly and starts the unit).
```
git -C $APP show $REF:deploy/epk-celery.service > /tmp/epk-celery.service
cat /tmp/epk-celery.service                                           # read it: User=devops, WorkingDirectory, ExecStart, Restart=on-failure
systemd-analyze verify /tmp/epk-celery.service                        # no output = fine (a missing-executable note is not expected)
sudo install -m 0644 -o root -g root /tmp/epk-celery.service /etc/systemd/system/epk-celery.service
sudo systemctl daemon-reload
sudo systemctl enable epk-celery                                      # enabled, NOT started
systemctl is-enabled epk-celery; systemctl is-active epk-celery       # enabled / inactive
rm /tmp/epk-celery.service
```
Rollback: `sudo systemctl disable epk-celery && sudo rm /etc/systemd/system/epk-celery.service && sudo systemctl daemon-reload`.

**3. sudoers rule for restarting that unit without a password (sudo; optional, the deploy script also works if you type your password).** Validated before it goes live; a bad file in `/etc/sudoers.d` can lock out sudo, so it is checked twice.
```
printf '%s\n' 'devops ALL=(root) NOPASSWD: /usr/bin/systemctl restart epk-celery, /usr/bin/systemctl status epk-celery' > ~/epk-celery.sudoers
sudo visudo -cf ~/epk-celery.sudoers                                  # must say: parsed OK
sudo install -m 0440 -o root -g root ~/epk-celery.sudoers /etc/sudoers.d/epk-celery
sudo visudo -c                                                        # whole config: all files parsed OK
sudo -l | grep epk-celery                                             # the rule shows up
rm ~/epk-celery.sudoers
```
If `visudo -cf` does not say `parsed OK`, stop and do not run the `install` line. Rollback: `sudo rm /etc/sudoers.d/epk-celery`.

**4. The deploy script itself (no sudo).** The release changes `deploy-release.sh`, but the one you run is the copy in `~/deploy-scripts/`, which still has the old Celery logic. Replace it from the release before running it:
```
git -C $APP show $REF:deploy/deploy-release.sh > /tmp/deploy-release.new
diff ~/deploy-scripts/deploy-release.sh /tmp/deploy-release.new       # expect: CELERY_SERVICE, REDIS_CACHE_URL preflight, systemctl restart of the unit
cp -a ~/deploy-scripts/deploy-release.sh ~/deploy-scripts/deploy-release.sh.bak-$(date +%F)
install -m 0755 /tmp/deploy-release.new ~/deploy-scripts/deploy-release.sh && rm /tmp/deploy-release.new
bash -n ~/deploy-scripts/deploy-release.sh && echo syntax ok
```
Rollback: copy the `.bak-` file back.

**5. nginx: Cloudflare real client IP (sudo).** `real_ip` is built into your nginx (`with-http_realip_module`). First see which vhosts talk to gunicorn (I could not read them):
```
sudo grep -nE 'server_name|proxy_pass|X-Forwarded-For|real_ip|include .*snippets' /etc/nginx/sites-available/*
```
The ones to patch are the server blocks that `proxy_pass` to gunicorn for `api.codingclubskenya.com` and for the apex `codingclubskenya.com` (`/api/`, `/admin/`): most likely `codingclubskenya-api.conf` and `codingclubskenya-main.conf`, but go by what that output shows. Each of them must contain `proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;` (add it next to the other `proxy_set_header` lines if missing).
```
TS=$(date +%Y%m%d-%H%M)
sudo cp -a /etc/nginx /etc/nginx.bak-$TS                              # backup of the whole config
git -C $APP show $REF:deploy/nginx/snippets/cloudflare-realip.conf | sudo tee /etc/nginx/snippets/cloudflare-realip.conf >/dev/null
grep -c '^set_real_ip_from' /etc/nginx/snippets/cloudflare-realip.conf   # 22 (15 IPv4 + 7 IPv6)
sudoedit /etc/nginx/sites-available/codingclubskenya-api.conf         # in each gunicorn-facing server { }, after server_name add:
                                                                      #     include /etc/nginx/snippets/cloudflare-realip.conf;
sudoedit /etc/nginx/sites-available/codingclubskenya-main.conf        # same line (only if this one proxies to gunicorn)
sudo nginx -t                                                         # must end: syntax is ok / test is successful
sudo systemctl reload nginx                                           # only after nginx -t passed
```
Verify (this works before the backend release): from your laptop `curl -s -o /dev/null https://api.codingclubskenya.com/api/healthz/ && curl -s https://ifconfig.me; echo`, then on the server `sudo tail -n 3 /var/log/nginx/access.log`: the first field of the healthz line must be your public IP, not a Cloudflare address (`104.16.*`, `172.64.*`, `162.158.*`, ...). IPv6 laptops show an IPv6 address; that is fine.
Rollback if `nginx -t` fails or anything looks wrong:
```
sudo rm -f /etc/nginx/snippets/cloudflare-realip.conf
sudo cp -a /etc/nginx.bak-$TS/sites-available/. /etc/nginx/sites-available/
sudo nginx -t && sudo systemctl reload nginx
```
(If you edited nothing yet, `nginx -t` fails only on the unused snippet's absence; nothing is reloaded unless it passes.) Refresh of the ranges later: header of the snippet and `docs/security/auth-rate-limiting.md`.

**6. Release (no sudo for me; the script asks for your password at the two `systemctl restart` lines unless step 3 is in place for the Celery one).**
```
~/deploy-scripts/deploy-release.sh <REF>       # backend: preflight (REDIS_CACHE_URL, unit), backup, migrate 0026, gunicorn, health, Celery unit
STAGE_ONLY=1 ~/deploy-scripts/deploy-static.sh frontend feat/school-data-management   # then tell me, I show the summary
```
Then I swap the frontend and run the checks (healthz, `systemctl status epk-celery`, 5 wrong sign-ins for a throwaway address give 401 then 429 and the Auth lockouts "last IP" is yours, reset email arrives, anonymous create-login 401).

**7. Purge cron (after the release, no sudo).** `purge_auth_lockouts` only exists once the release is checked out.
```
crontab -l > ~/crontab.bak-$(date +%F)                                # keep the current one
( crontab -l; echo '15 3 * * * cd /home/devops/home/personal/personalweb/epk && DJANGO_SETTINGS_MODULE=core.settings_production venv/bin/python manage.py purge_auth_lockouts --hours 24 >> logs/purge_auth_lockouts.log 2>&1' ) | crontab -
crontab -l                                                            # the backup line (02:30) and this one (03:15)
cd $APP && DJANGO_SETTINGS_MODULE=core.settings_production venv/bin/python manage.py purge_auth_lockouts --hours 24   # run once by hand: "Deleted N idle lockout row(s)."
```
Rollback: `crontab ~/crontab.bak-<date>`.

**Incident 2026-11-19 (done, recorded so it is not repeated).** A 28-day-old hand-started gunicorn (PIDs 2533281 to 2533284, bound to a relative `epk.sock`, from login session 1202) was still running next to `gunicorn.service`. It served nothing, but it was stopped with a warm `SIGTERM` and **gunicorn unlinks its socket path on exit, and that path is the live service's socket**: `epk.sock` vanished and the API answered 502 from 12:46:29 until 12:47:15 (about 45 s). Recovery without sudo: `SIGKILL` of the live master so systemd's `Restart=on-failure` recreated the socket (new master 1910741, NRestarts=1, same commit `0a9bfd6`, healthz 200 on api, apex and erp). Rule: never stop a gunicorn that shares a bind path with a running one without restarting the live service straight after (`sudo systemctl restart gunicorn`), ideally in a quiet window. The stale process is gone, so this cannot recur from it.
Side effect: the restart re-read `.env`, so the currently deployed code now uses Redis database 1 for its cache (it reads `REDIS_CACHE_URL` when set); anonymous API calls still answer normally.

**Cleanup worth doing (separate from this release, your call).** `epk.service` is enabled but inactive while `gunicorn.service` serves; after a reboot both could start and fight over `epk.sock`. `systemctl cat gunicorn epk | grep -E 'ExecStart|bind'` to compare, then `sudo systemctl disable epk` for the one you do not use.

**Order in one line:** 1 `.env` -> 2 unit -> 3 sudoers -> 4 script copy -> 5 nginx (verify real IP) -> 6 release + frontend -> 7 cron.

## Limits
- The Cloudflare nginx change is prepared but **not applied on the server**: I cannot read the vhosts without sudo, so step 5 starts with a read of them.
- An account lock lets someone who knows an email lock that person out for 15 minutes (plan, section 4). Admins can unlock; it is never permanent.
- `anon:` counter rows are kept until purged: run `purge_auth_lockouts` from cron (not scheduled; Celery beat is not running in production).
- Sentry or log-based alerting on `security.auth` is not configured; the log lines are there to alert on.
