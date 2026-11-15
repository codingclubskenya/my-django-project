# Phase 3b report: password reset, Registrar/Principal seed users, probe

Backend `e503a88` (+ `.env.example` commit), frontend `2d8382b`.

## 1. Password reset fixed
- **Cause:** dj-rest-auth's default reset link reverses a Django URL name (`password_reset_confirm`) that this project does not have, so every request for a real account was a 500.
- **Fix:** `FrontendPasswordResetSerializer` (`REST_AUTH['PASSWORD_RESET_SERIALIZER']`) builds `{FRONTEND_URL}/reset-password?uid=...&token=...`. `FRONTEND_URL` comes from env (default `http://localhost:5173`), never from the request Host header. Same 200 response for known and unknown emails; nothing is sent for an unknown one.
- **Tests** (`accounts/test_password_reset.py`, 4): email goes to the user and contains the frontend URL with uid and token; confirm sets the password and the token works once; bad token or mismatched passwords rejected, password unchanged; unknown email returns the identical response and sends no mail. `accounts core`: 296 passed.
- **Frontend:** `/reset-password` already existed. `ForgotPassword.jsx` now calls `/api/auth/password/reset/` and no longer shows a development token; `ResetPassword.jsx` reads `uid` + `token` and posts to `/api/auth/password/reset/confirm/` (a bare `?token=` still uses the old endpoint). `vite build` passes, not click-tested.
- **Needs you:** set `FRONTEND_URL` on production (added to `.env.example`; I did not touch `.env.production.example` or deploy files). Real email also needs `EMAIL_BACKEND` and SMTP settings.
- **Left as is:** the older `password-reset/request/` and `confirm/` endpoints still exist. In DEBUG the request endpoint returns the reset token in the response and answers differently for unknown emails (dev only, but it is an enumeration/leak path); their emailed link is a relative path. Say if you want them removed.

## 2. Seed users and probe
- `seed_dev_users` adds `registrar@` (Registrar group) and `principal@` (Principal group) for both schools, role STAFF, same password. It now also seeds a `ParentProfile` for `parent@` (national ID, alternate phone) so a leak is visible, and the link relationship uses `GUARDIAN`. Dev DB re-seeded.
- `api_probe.py` knows the two roles and has `--roles a,b`. Run for `registrar,principal` (reads + writes, scratch copies): **no 500s, no Rival rows visible, no Rival mutations.**
  - Parents: Registrar 200/201/PATCH 200; Principal reads 200, POST/PATCH 403, `template/` and `bulk_import/` 403. Rival parent id 404 for both.
  - Staff: Registrar and Principal read `staff-profiles` 200 (Registrar own row only, Principal slim), all staff writes, `bulk_import` and groups writes 403.
  - Students: `users/students/` 200 (own school), `users/parents/` 200.
  - Import reports (checked on a scratch copy with one log of each type in both schools): Registrar sees only `parents` and `students`; Principal sees all four types; Rival logs never appear; staff user sees `staff`; teacher/parent/student 403.
  - Flagged as "unexpected 2xx" (expected by design): Registrar/Principal writes on `parent-learner-links`; Registrar on `parents/`. **Pre-existing, not new:** both can `POST academics/streams/bulk_import/` (200, same FK-action hit admin/teacher/staff already had), which Phase 5 should gate to ADMIN/Principal.
- `parent_privacy_probe.py` now also asserts Registrar sees national IDs, Principal gets the slim record and cannot write: 83 requests across 9 demo users, 0 failures.

## 3. Phase 2 frontend
Already done in `f57a4cf` (Phase 3 follow-up): `Staff.jsx` uses `ImportDialog`, the server 7-column template and a staff groups dialog, with ADMIN/HR-only controls. Nothing further needed.

## Needs your attention
- Set `FRONTEND_URL` and SMTP on production.
- Decide on removing the old reset endpoints.
- Principal can still write parent links (open decision from Phase 3).
- Streams `bulk_import` is open to Registrar/Principal/teacher/staff (Phase 5 gate).
- Click-through of the UI is still outstanding. Root submodule pointers not bumped.
