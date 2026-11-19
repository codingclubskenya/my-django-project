# Auth rate limiting: plan (2026-11-19)

Spec: `docs/specs/auth-rate-limiting.md`. Read-only investigation of `feat/school-data-management`; **no code changed**. Waiting for your OK on section 7.

## 0. Verdict in five lines
1. django-axes is **production-only** and locks on **(username + IP)**, so rotating IPs or alternating identifiers sidesteps the account lock. Cool-off is 1 hour (spec: 15 min) and the counter is never reset on success.
2. **Student login** (admission number + PIN) has no account-level limit at all: only 10/min per (IP + id). A short PIN can be sprayed from many IPs.
3. Nothing in dev/test/default settings enforces lockout, so none of the spec's tests can run today.
4. **No OTP exists**, and **no phone login exists**: login is email + password (SimpleJWT) or admission no. + PIN.
5. Cache is process-local unless `REDIS_CACHE_URL` is set; with 3 gunicorn workers every DRF throttle limit is effectively x3 and resets on restart. I could not confirm the production value (ssh timed out, see 6).

## 1. What exists
| Area | Today | Where |
|---|---|---|
| django-axes 8.3.1 | `AxesBackend` + `AxesMiddleware` added **only** in `settings_production.py`. `AXES_FAILURE_LIMIT=5`, `AXES_COOLOFF_TIME=1` (hours), `AXES_LOCKOUT_PARAMETERS=[['username','ip_address']]`, `AXES_USERNAME_FORM_FIELD='email'`. No `AXES_RESET_ON_SUCCESS`, no username callable, no custom lockout response, default DB handler. | `core/settings_production.py:50-59,121-126` |
| Login throttles | `LoginIdentifierThrottle` (scope `login`, 10/min per **IP + sha256(email or student_id)**) and `LoginIPThrottle` (`login_ip`, 600/hour per IP, counts successes too). Applied to `/api/auth/login/` and `/api/auth/student-login/`. | `accounts/throttles.py`, `accounts/views.py:40-52` |
| Global DRF throttles | anon 1200/h, user 3000/h, scoped: `login` 10/min, `login_ip` 600/h, `password_reset` 5/h, `dj_rest_auth` 30/min. `NUM_PROXIES=1` in production. All env-overridable. | `core/settings.py:180-200`, `settings_production.py:119` |
| Login views | `/api/auth/login/` = `CustomTokenObtainPairView` (email+password, first in URLconf so it shadows dj-rest-auth's `login/`). `/api/auth/student-login/` = `StudentLoginView` (admission no. [+ `school_code`] + PIN, loops up to 20 profiles calling `check_password`, returns 401 `Invalid credentials`). | `accounts/views.py` |
| Password reset | Two live paths: dj-rest-auth `password/reset/` + `password/reset/confirm/` (used by the SPA, uid+token, scope `dj_rest_auth` 30/min; serializer already returns the same response for unknown emails) and the custom `password-reset/request/` + `confirm/` (scope `password_reset` 5/h; same message for unknown; in `DEBUG` it returns the token). Sync `send_mail(fail_silently=True)` only when the account exists. | `accounts/views.py:556-612`, `accounts/serializers.py:443-527` |
| Password change | `/api/auth/change-password/` (own view, checks `current_password`, **no scoped throttle**, only the 3000/h user rate) and dj-rest-auth `password/change/` (reachable; `OLD_PASSWORD_FIELD_ENABLED` is not set, so it does not ask for the old password and does not clear `must_change_password`). | `accounts/views.py:614`, `core/urls.py:41` |
| Admin login | `/admin/login/` uses Django's form; axes should see it only if it can find the username (see gap 5). | `core/urls.py:35` |
| OTP | None. Only code paths are temporary passwords and reset tokens (`PasswordReset`, 1 h expiry). | grep |
| Phone | Stored and normalised (`core/phone.py`, `User.save`), but **not usable as a login identifier**. | `accounts/models.py`, `core/phone.py` |
| Audit | `AuditLog(school, user, action, object_repr, field, before/after, ip_address, user_agent)`; actions limited to create/update/delete/view/ai_suggestion. Axes' own `AccessAttempt` / `AccessLog` exist in production only. | `audit/models.py` |
| Tests | `LoginThrottleTests` (per-IP+account throttle, 25 students one IP) and password-reset tests. Nothing for lockout, reset-on-success, concurrency. | `accounts/test_security.py:174` |

## 2. Gaps vs spec
| # | Spec | Gap | Severity |
|---|---|---|---|
| 1 | A: lock the **account** after 5 failures, 15 min | Axes keys on (username, IP): 5 tries per IP per account. N IPs = 5N tries. Cool-off is 60 min and set in hours. | High |
| 2 | A: reset counter on success | `AXES_RESET_ON_SUCCESS` unset (default False). Failures linger until cool-off. | Medium |
| 3 | A/E: email and phone share one lock; no bypass by switching | Phone login does not exist; email is case-sensitive in the auth lookup (`Admin@x.com` and `admin@x.com` count separately in axes; the throttle lowercases, auth does not); student id and email are separate identities for the same user. | High |
| 4 | A: attempts by account **and** IP | Axes records IP but a lock needs both; the DRF throttle counts all requests, not failures, per IP. | Medium |
| 5 | A/E: cover `/admin/login/` | Admin form posts `username`; axes is configured with form field `email` and no username callable. Likely **untracked**; needs a test to confirm. | High (to verify) |
| 6 | A: dev/test parity | Axes absent from base/dev/test settings. | Medium |
| 7 | B: OTP rules | No OTP. Design only (section 5). | n/a |
| 8 | C: reset rate limit, no enumeration | Two reset surfaces with different limits (30/min vs 5/h). Timing differs: existing account does DB writes + SMTP, unknown does nothing. 5/h per IP is too tight for a school NAT at term start, and too loose per target (no per-email limit). The custom reset leaks the token when `DEBUG` (fine, `DEBUG=False` in production). | Medium |
| 9 | D: change-password throttled | `current_password` can be guessed at the user rate (3000/h). dj-rest-auth `password/change/` is a second, unthrottled-by-scope path. | Medium |
| 10 | D/E: login protection, shared storage | Student PIN has no account lock; `LoginIdentifierThrottle` is per IP+id, so a many-IP spray works. Student ids are unique per school only, so the lock key must be the resolved user, not the string. | High |
| 11 | D/E: Redis in production, multi-worker | `REDIS_CACHE_URL` optional; LocMem fallback. | High if unset (unverified) |
| 12 | E: atomic counters | Axes DB handler concurrency is unproven; throttles are cache-based (atomic only on Redis). | Medium (test it) |
| 13 | E: log suspicious activity without secrets; admin visibility | No structured security log; no unlock action; axes admin pages exist only in production. | Medium |
| 14 | F: tests | None of the 10 can run today (no axes in test settings). | High |

## 3. Design A: login lockout
**3.1 One account key.** New `accounts/identity.py`: `normalise_identifier(raw)` returns `('email', lower-stripped)` or `('phone', E.164 via core/phone)` and `resolve_account_key(raw, school_code=None)`:
- email or phone matching exactly one user: `user:<id>`; every identifier for that person, any case, maps to the same key.
- student id (+ optional school code): the set of candidate user ids (typically 1); failures are charged to each candidate.
- no match: `anon:<sha256 of the normalised identifier>`. Unknown identifiers are counted and locked exactly like real ones, so a lock reveals nothing.
Wired in as `AXES_USERNAME_CALLABLE` (handles credentials keys `email`, `username`, `phone`, `student_id`, and the admin form's `username`).

**3.2 Axes config (moved into base `settings.py`, so dev, test and prod behave the same):**
`AXES_FAILURE_LIMIT=5`, `AXES_COOLOFF_TIME=timedelta(minutes=15)`, `AXES_LOCKOUT_PARAMETERS=['username']` (lock on the account key only), `AXES_RESET_ON_SUCCESS=True`, `AXES_USERNAME_CALLABLE`, `AXES_LOCKOUT_CALLABLE` (JSON, below), `AXES_ENABLE_ACCESS_FAILURE_LOG=True`, `AXES_SENSITIVE_PARAMETERS`/`AXES_PASSWORD_FORM_FIELD` so passwords are never stored, handler stays the **database** handler (account lock survives a Redis outage, and `AccessAttempt` rows give admin visibility). There is no setting that makes a lock permanent; the cool-off is the only way out and a successful login after it resets the count.
Student login calls `authenticate()` through axes (today it calls `check_password` directly and bypasses it); each failure is recorded against the resolved candidate key(s).

**3.3 Per-IP limits, generous for school NATs.** The lock above is account-only. IP limits stay DRF throttles, but count **failures**, not requests: a small helper `accounts/ratelimit.py` using `cache.add` + `cache.incr` (atomic on Redis): `AUTH_FAIL_IP_LIMIT=150` failures / 15 min per IP (a class of 200 with a few typos is fine; a spray is not), plus the existing `login_ip` 600/h kept as a ceiling. The per-(IP+identifier) 10/min throttle is kept as burst protection.

**3.4 Consistent responses.** Locked, throttled and (optionally) IP-limited all return the **same** `429 {"detail": "Too many attempts. Try again later.", "code": "auth_rate_limited"}` with `Retry-After`. During a lock even a correct password gets that 429 (no oracle). Wrong password and unknown account stay the same 401 body as now. Lock state is visible only to an administrator.

**3.5 Admin login.** The same callable and handler cover `/admin/login/` (form field `username`). Test first to prove the current gap, then fix. Admin login keeps the same 5 / 15 limits.

**3.6 Admin visibility and unlock.**
- Axes admin (`AccessAttempt`, `AccessLog`) visible in every environment, read-only.
- Django admin `User` action **"Unlock selected accounts"** and an API `POST /api/auth/users/<id>/unlock/` for school ADMIN (same tenant scoping and permissions as `reset-password`; platform admin for any school). Both call axes' `reset()` for the account key and write an `AuditLog` row (`action='update'`, `field='auth_lockout'`, `before/after`, actor IP/UA).
- On each lockout: `AuditLog` row (user = target if it resolves, `ip_address`, `after={'until': ..., 'attempts': 5}`) and a `security.auth` logger line (`event=lockout key=user:42 ip=... ua=...`; never passwords, PINs, OTPs or the raw identifier, only the key). Sentry already installed; the logger name can be alerted on.

**3.7 Password reset (spec C).** Merge to one policy on both endpoints: per-IP 30/h (shared network), per-normalised-email 3/h (silent: still 200, nothing sent), same status/body always, and the email goes out in a Celery task so timing no longer depends on existence. Confirm endpoints: per-IP 30/h, token entropy unchanged. Fixes the 5/h-per-IP school-NAT problem.

**3.8 Password change (spec D).** `current_password` failures: 5 / 15 min **per user**, cool-off, reset on success, same 429 shape, shares the login counter? **No**, separate counter (a locked-out attacker with a stolen session must not lock the real user out of login). dj-rest-auth `password/change/` is removed from the URLconf (the SPA only uses `change-password/`); needs your OK because it removes a public route.

**3.9 Redis and multi-worker.** In production `REDIS_CACHE_URL` becomes **required** (startup error like the existing `SECRET_KEY` check), on its own Redis DB index (not Celery's), `IGNORE_EXCEPTIONS=True` so an outage fails open on IP throttles only (logged); the account lock stays in Postgres and keeps working. DRF throttles and the failure helper then share counters across all workers and servers.

**3.10 Concurrency.** Test 9 runs 20 parallel wrong attempts on Postgres (`TransactionTestCase` + threads) and asserts at most 5 reach the password check. If the axes DB handler lets extras through, fallback is a small custom handler that takes a row lock (`select_for_update`) on the `AccessAttempt` row, or a Redis `INCR` guard in front of it. I will not assume; the test decides.

**3.11 Frontend.** Login, student login, forgot/reset and change-password pages show "Too many attempts, try again in N minutes" from `Retry-After`. Small change in `Login.jsx` / `api.js` / `ChangePassword.jsx`.

## 4. Known trade-off
An account-level lock lets someone who knows an email lock that person out for 15 minutes by failing 5 times. Mitigations: it is never permanent, resets on success, an admin can unlock, and per-IP failure limits catch a single source. This is inherent to the spec's rule; the alternative (keying on account + IP) is exactly the gap being fixed. Tell me if you want a "trusted device" exception later.

## 5. Design B: OTP (for when it is added; nothing built now)
- `OtpChallenge(id, user, purpose, code_hash, created_at, expires_at, attempts, max_attempts=5, consumed_at, ip, resend_not_before)`. Store a **hash** (HMAC with a server key) of the 6-digit code, never the code; compare with `hmac.compare_digest`.
- Verify: lock the row (`select_for_update`), increment `attempts` atomically, reject when `attempts>=5`, expired or consumed; on the 5th failure set `invalidated_at` and require a new request. Success consumes the challenge (single use). Failures never reveal which part was wrong.
- Resend cooldown 60 s via `resend_not_before` (DB, atomic) + `otp_resend` throttle; generation limit 5/hour per account **and** per IP (account key from section 3.1, so email/phone are one account), silent 200 for unknown identifiers, same response shape.
- Verification endpoint throttled per challenge and per IP; codes expire in 5-10 min; delivery via a Celery task; log challenge id and outcome only.
- Shares the identity resolver, the `auth_rate_limited` response and the audit/log helpers from section 3.

## 6. Unverified / not done
- Whether production has `REDIS_CACHE_URL`, redis running and worker count: ssh to the server timed out during this task. One read-only command checks it (key presence only, no values); I will run it when the host is reachable.
- Axes' internals (exact `get_client_username` behaviour with SimpleJWT credentials, whether the DB handler is race-free) could not be read here (the installed package is outside what I may read), so those two points are settled by tests, not by reading.
- The admin-login gap (gap 5) is inferred from the config, not yet reproduced.

## 7. Decisions I need from you
1. **Phone login:** build it now as part of this (identifier = email or phone, same endpoint, frontend field accepts both), or keep this task to lock/limit logic with the resolver ready for phone? The spec's tests 2 and 4 need it, so I recommend building it.
2. **Remove dj-rest-auth `password/change/`** from the URLs (section 3.8): OK?
3. **Move axes config to base settings** (dev and test run it too, with locmem cache): OK? It is what makes the 10 tests possible.
4. **Make `REDIS_CACHE_URL` required in production** (startup refuses without it): OK? Confirm Redis is available on the server first.
5. **Send reset emails via Celery** (needs the worker up, which it is today): OK?

## 8. Settings to document (admin guide at `docs/security/auth-rate-limiting.md` after coding)
| Setting (env) | Default | Meaning / safe range |
|---|---|---|
| `AXES_FAILURE_LIMIT` | 5 | failures before an account lock; do not go above 10 |
| `AXES_COOLOFF_TIME` (`AUTH_LOCKOUT_MINUTES`) | 15 | minutes; never 0/None (None would be permanent, startup check rejects it) |
| `AXES_RESET_ON_SUCCESS` | True | clears the count on a good login |
| `AUTH_FAIL_IP_LIMIT` / `AUTH_FAIL_IP_WINDOW` | 150 / 15 min | failed logins per IP; raise for very large shared networks |
| `API_LOGIN_RATE` | 10/min | per (IP + account) burst throttle |
| `API_LOGIN_IP_RATE` | 600/hour | per IP ceiling |
| `API_PASSWORD_RESET_RATE` | 30/hour | per IP, both reset endpoints |
| `PASSWORD_RESET_PER_EMAIL` | 3/hour | silent per-target limit |
| `CHANGE_PASSWORD_FAILURES` | 5 per 15 min | wrong current password per user |
| `OTP_MAX_ATTEMPTS`, `OTP_RESEND_COOLDOWN`, `OTP_PER_HOUR` | 5, 60 s, 5 | when OTP is added |
| `REDIS_CACHE_URL` | required in prod | shared counters across workers/servers |
| `NUM_PROXIES` | 1 | must match the proxy chain or IP limits can be spoofed |

## 9. Test plan (maps to spec F)
1. five wrong logins, 6th is 429 with `Retry-After` (15 min); 2. email, different-case email and phone share one lock; 3. other IPs (`REMOTE_ADDR`/`X-Forwarded-For` via `NUM_PROXIES`) still locked; 4. alternating identifiers still locked; 5. success resets the counter (4 fails, success, 4 fails: not locked); 6-7. OTP expiry and resend cooldown (against the design in section 5, added with OTP); 8. both reset endpoints throttled and identical for known/unknown, per-email limit holds; 9. 20 parallel attempts on Postgres reach the password check at most 5 times; 10. after the cool-off (frozen clock) the user logs in. Extras: student login lock, `/admin/login/` lock, unlock action + audit row, no password/PIN in logs, locked unknown identifier looks identical to locked real one, a school NAT of 30 users still logs in.
