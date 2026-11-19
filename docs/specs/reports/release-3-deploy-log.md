# Release 3 deploy log: authentication rate limiting (2026-11-19)

## Backend (deployed by `~/deploy-scripts/deploy-release.sh`, run by the owner)
- Server code at `b31c743` (`feat/school-data-management`, backend). `gunicorn` active since 13:04:11 CET (master 1918559, started by the deploy), healthz 200.
- Pre-deploy backup written by step 1 of the script: `/home/devops/backups/school_mgmt-20261119-130324.dump`. Earlier today: `school_mgmt-20261119-123006.dump` (taken for the rehearsal).
- **Done line: NOT RECORDED.** No `~/deploy-release-<time>.log` exists on the server (searched `~` to depth 3 for files from the last 3 hours; the script only prints). Paste the `Done:` line here if it exists elsewhere.
- Migration verified read-only: `accounts.0025_phone_canonical` and `accounts.0026_authlockout` applied.
- Celery: the script's cut-over worked. `epk-celery.service` active and enabled since 13:04:18 (MainPID 1918642 plus 4 children, `NRestarts=0`), `celery inspect ping` answers (1 node), both `accounts.send_*` reset tasks registered, no worker outside the unit, `/tmp/celery.pid` absent.

## Frontend
- Staged with `STAGE_ONLY=1` (`releases/frontend-20261119-130220`, ref `feat/school-data-management` @ `745e978`), then swapped with `USE_RELEASE=... deploy-static.sh frontend feat/school-data-management`. Live `dist` points at that release; the previous release `frontend-20261119-100609` is the rollback target (command printed by the script). nginx needed no reload.
- Live JS bundle: `assets/index-CYs5nBfz.js` (login field "Email or phone number", wait-time message, `identifier` sign-in). Only API URL baked in: `https://codingclubskenya.com`.

## One-off server steps (done by the owner; steps 1 and 4 and the read-only checks by Claude)
- `.env`: `REDIS_CACHE_URL=redis://localhost:6379/1` (broker stays `/0`), backup `~/backups/env-20261119-1243.bak`. `~/deploy-scripts/deploy-release.sh` replaced from the release (old copy `deploy-release.sh.bak-2026-11-19`).
- `epk-celery.service` installed and enabled, sudoers rule for restarting it (validated with `visudo -cf`), Cloudflare real-IP nginx snippet live and verified (access log shows the real client IP).
- Incident the same day: stopping a stale hand-started gunicorn (PIDs 2533281 to 2533284) removed the shared `epk.sock`; API 502 for about 45 s (12:46:29 to 12:47:15), recovered by SIGKILL of the live master so systemd restarted it. Details and the rule: `reports/auth-rate-limit.md`.

## Post-release checks (2026-11-19, about 13:05 to 13:12 CET)
| Check | Result |
|---|---|
| healthz | api, apex `/api/`, erp: 200 |
| `systemctl is-active epk-celery`, celery ping | active, pong (1 node online) |
| stray hand-started worker | none (every worker process is in `epk-celery.service`) |
| Wrong sign-ins from the owner's laptop (public IP 197.248.84.107), throwaway identifier | attempts 1 to 5: 401 "No active account found..."; attempt 6: **429** `{"detail":"Too many attempts. Try again later.","code":"auth_rate_limited"}`, `Retry-After: 897`, `Access-Control-Expose-Headers: Retry-After` |
| Auth lockouts record | one locked `anon:` row, 5 failures, **last IP 197.248.84.107** (the real client IP, not a Cloudflare address); no locked row with any other IP; audit row written for the lockout |
| Unlock | `lockout.unlock` on that row: failures 0, `locked_until` none (the unlock audit row has no IP because it was run from a shell) |
| `security.auth` log | `event=lockout` and `event=denied` lines carry the account key and the real IP; they are in the journal (`journalctl -u gunicorn | grep event=`), not in a file (see follow-ups) |
| anonymous create-login / admin password page / removed `password/change/` | 401 / 302 / 404 |
| Purge cron | added `15 3 * * * ... purge_auth_lockouts --hours 24 >> logs/purge_auth_lockouts.log`; one manual run: "Deleted 0 idle lockout row(s)"; crontab before: `~/crontab.bak-2026-11-19` |

`crontab -l` now:
```
30 2 * * * $HOME/deploy-scripts/backup.sh >> $HOME/backups/backup.log 2>&1
15 3 * * * cd /home/devops/home/personal/personalweb/epk && DJANGO_SETTINGS_MODULE=core.settings_production venv/bin/python manage.py purge_auth_lockouts --hours 24 >> logs/purge_auth_lockouts.log 2>&1
```

## Not checked on production (no real user involved)
- A real password-reset email through the worker to a real mailbox (rehearsed on the prod copy, not sent from production).
- A successful phone sign-in by a real user, and `/admin/login/` lockout (both covered by tests and the rehearsal).

## Follow-ups
- Add a `security.auth` logger to `LOGGING` in `settings_production.py` (file under `logs/` plus console) so lockout events are kept with a timestamp and logger name; today they only reach the journal.
- `epk.service` is still enabled but inactive next to `gunicorn.service`; disable it (it shares the bind path and was involved in the incident above).
- Parents/students imported with placeholder emails (no dot in the domain, unusable password) cannot sign in by email, phone or reset.
