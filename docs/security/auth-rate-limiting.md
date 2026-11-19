# Authentication rate limiting: administrator guide

How sign-in is protected, what an administrator sees, and which settings can be changed safely. Spec: `docs/specs/auth-rate-limiting.md`.

## What happens
- **Account lock.** 5 consecutive failed attempts lock the account for 15 minutes. Never permanent. A successful sign-in resets the count; failures older than 15 minutes are forgotten.
- **One account, any identifier.** Email (any letter case) and phone (07.., 01.., 254.., +254..) that belong to the same user share one counter, from any IP address. Changing identifier or IP does not reset it.
- **Phone sign-in** works only when the number belongs to exactly one active user who can sign in with a password. Otherwise the answer is the same generic error as a wrong password. Users who share a number must use email: `manage.py check_duplicates` lists them (warning only).
- **Same answer every time.** Wrong password and unknown account both return 401 `No active account found with the given credentials`. A locked account, a locked unknown identifier, an IP over its failure limit and a throttled request all return the same `429 {"detail": "Too many attempts. Try again later.", "code": "auth_rate_limited"}` with a `Retry-After` header. While locked, even the right password gets the 429.
- **School networks.** The IP limit counts failed sign-ins only (default 150 per 15 minutes), so a class of students behind one address is fine; one machine spraying many accounts is not.
- **Covered:** `/api/auth/login/` (email or phone), `/api/auth/student-login/` (admission number + PIN, lock is per student account), `/admin/login/`, `change-password` (wrong current password: own counter, so a stolen session cannot lock the real owner out of signing in), both password-reset request endpoints and both confirm endpoints. dj-rest-auth's `password/change/` is removed.
- **Password reset.** Always the same response and the same work: the lookup, link and email run in the Celery worker, so neither body nor timing reveals whether the address has an account. Each address gets at most 3 reset emails an hour (silently), each IP 30 requests an hour.
- **Where counters live.** Account locks: PostgreSQL table `accounts_authlockout` (row-locked, exact under concurrency, survives a Redis outage). IP and reset counters: the cache (Redis in production, shared by all workers; a Redis outage fails open for those, never for the account lock).

## What an administrator sees and can do
- **Django admin > Accounts > Auth lockouts:** one row per account key (`user:<id>`, `chpw:<id>`, or `anon:<hash>` for identifiers with no account), failures, `locked until`, last IP. Read-only; action **Unlock selected**.
- **Django admin > Users:** action **Unlock selected accounts**.
- **School ADMIN, API:** `POST /api/auth/users/<id>/unlock/` (own school only).
- **Audit log:** every lockout and every unlock is an `AuditLog` row (`field = auth_lockout`, with IP and user agent; unlocks record who did it).
- **Application log:** logger `security.auth` (WARNING): `event=lockout|denied|unlock|ip_limit|reset_limited` with the account key and IP. Never passwords, PINs, reset tokens or the identifier typed. Alert on `event=lockout` bursts.
- Idle counters can be tidied with `manage.py purge_auth_lockouts --hours 24` (safe any time; locked rows are kept).

## Settings (environment variables)
| Variable | Default | Meaning and safe range |
|---|---|---|
| `AUTH_LOCKOUT_FAILURES` | 5 | failures before an account lock. 3 to 10; lower annoys real users, higher helps guessing |
| `AUTH_LOCKOUT_MINUTES` | 15 | cool-off. 5 to 60. Must stay above 0: there is no permanent lock |
| `AUTH_FAIL_IP_LIMIT` | 150 | failed sign-ins per IP per window. Raise only for very large shared networks |
| `AUTH_FAIL_IP_WINDOW_MINUTES` | 15 | window for the IP failure counter |
| `PASSWORD_RESET_PER_EMAIL` | 3 | reset emails per address per hour (silent) |
| `API_LOGIN_RATE` | 10/min | burst limit per (IP + account) on login endpoints |
| `API_LOGIN_IP_RATE` | 600/hour | all login requests per IP (ceiling) |
| `API_PASSWORD_RESET_RATE` | 30/hour | reset request and confirm, per IP |
| `API_CHANGE_PASSWORD_RATE` | 30/hour | change-password requests per user |
| `REDIS_CACHE_URL` | required in production | e.g. `redis://localhost:6379/1`. Must be a different database number from `CELERY_BROKER_URL` (`/0`). Production refuses to start without it |
| `NUM_PROXIES` | 1 | proxies in front of Django (nginx = 1). Wrong value lets clients spoof their IP |

Change a value in the server `.env`, restart gunicorn. Test it first with the throwaway-container suite (`accounts.test_auth_rate_limit`).

## Not included
OTP (no OTP exists yet). Design for it (5 attempts per challenge, 60 s resend cooldown, 5 per hour per account and IP) is in `docs/specs/reports/auth-rate-limit-plan.md`, section 5.
