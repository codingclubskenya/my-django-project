# Release 2 deploy log (2026-11-18)

## Backend
- Deployed by `deploy-release.sh` (run by the owner). Server code is at `a33580f` (Phase 6b backend HEAD), service `gunicorn` active.
- Pre-deploy backup (step 1 of the script): `/home/devops/backups/school_mgmt-20261118-083929.dump` (1,063,557 bytes) + `media-20261118-083929.tgz`. Rehearsal dump from earlier the same morning: `school_mgmt-20261118-081130.dump`.
- **Done line: NOT RECORDED.** The log file `~/deploy-release-<time>.log` could not be found on the server (searched `~`, `~/backups`, `/tmp`, the app `logs/`, and files modified in the last hour; the script itself only prints, it does not write a log). Paste the file's `Done:` line here if it exists elsewhere.
- Restart times (read-only, 08:49 CET): backup file written 08:39:33; `gunicorn` active since 08:40:21; Celery worker (`celery -A core worker`, master pid 1208621 plus 4 children) started 08:40:30-08:40:34. The worker is newer than the backup and the gunicorn restart, so it runs the new code.
- Migrations, verified afterwards with `showmigrations` under `core.settings_production` (read-only): all applied, `academics` 0009 to 0014 and `accounts` 0015 to 0025 (including `0025_phone_canonical` and `0014_stream_name_ci_unique`).

## Frontend
- Staged earlier with `STAGE_ONLY=1` (`releases/frontend-20261118-082939`, ref `feat/school-data-management` @ `1734e7e`, 2,096,398 B vs 2,100,101 B live), then swapped with `USE_RELEASE=... deploy-static.sh frontend feat/school-data-management`. Live `dist` now points at that release; previous release `frontend-20261116-171844` is the rollback target (command printed by the script). nginx needed no reload.
- Live JS bundle: `assets/index-Do2FRUGw.js`.

## Smoke checks (curl, anonymous, 2026-11-18 about 08:45 CET)
| URL | Result |
|---|---|
| `https://erp.codingclubskenya.com/` | 200 (serves the new bundle) |
| `.../classes`, `.../students`, `.../parents` | 200 each (SPA routes) |
| `https://codingclubskenya.com/api/healthz/` | 200 `{"status": "ok"}` |
| `https://codingclubskenya.com/api/v1/auth/users/` | 401 `Authentication credentials were not provided.` |
| `https://api.codingclubskenya.com/api/healthz/`, `/api/v1/auth/users/` | 200, 401 |

Note: `erp.codingclubskenya.com` serves the SPA for every path, including `/api/...`, so `/api/healthz/` and `/api/v1/auth/users/` there return 200 HTML and prove nothing. The API lives on `codingclubskenya.com` (the build's `VITE_API_URL`) and `api.codingclubskenya.com`; the health and 401 checks above are from those hosts.

## Still to do (from `DATABASE-CHANGES.md` step 8)
- Add users to the Registrar / Principal / HR groups in Django admin.
