# Phase 3 report: parents

Branch `feat/school-data-management`. Production untouched; dev DB not yet migrated for 0021/0022 (tests run on fresh DBs).

## Also done this turn
- Committed the audit fix (backend `bf68727`): snapshot keys lowercase so every audited model really gets a snapshot, allowlists per model, a central exclude list (passwords, tokens, national ID, NEMIS, DOB, address) applied to snapshots and to anything passed to `log_action`, `StudentProfile` now audited. Needs your eye: audit entries for User, Invoice, Payment etc. now contain field snapshots they never had before.

## What changed
- **Migrations:** `accounts.0021` (`ParentProfile`; relationship choices; unique national ID per school where set) and `0022` (data: free-text relationship to FATHER/MOTHER/GUARDIAN/OTHER, `Parent` and unknown to OTHER; empty profile for every existing parent). Details in `DATABASE-CHANGES.md`.
- **Matching service** `accounts/parents.py`: national ID, then phone (normalised to 254...), then email, always in the school. A phone/email match with a different national ID raises `ParentConflict` (never merged, for Phase 4 to show in the preview). Fills blank fields only. New parents get an unusable password.
- **Parents API** `/api/auth/parents/`: ADMIN and Registrar full and writable; Principal slim and read-only; everyone else 403. Search by name, email, phone, child name, admission number (national ID and alternate phone for ADMIN/Registrar only). Delete refused while children are linked.
- **Directory privacy:** teachers no longer receive a parent's phone from `users/parents/` or `users/?role=PARENT`. ADMIN, Registrar, Principal and the parent themself still do.
- **Links:** Registrar and Principal can list and write `parent-learner-links`; relationship validated against the four codes. Parents still see only their own links.
- Old student import writes a valid relationship code.

## Verification
- Full suite: 582 passed after updating one stale test (`check_duplicates` parent check now runs). 26 new tests in `accounts/test_parents.py`.
- Not done: the probe script, a dev DB migrate, frontend.

## Needs your attention
- **Frontend not changed:** nothing consumes `/parents/`, and `Students.jsx` still sends free-text relationship (the old import maps it; `parent-learner-links` writes would 400 on free text).
- **Decision:** Principal can write parent links (plan says "access"); say if that should be read-only.
- **Phone matching** scans the school's parents in Python (stored phones have mixed formats). Fine for thousands; Phase 4 may want a normalised phone column if imports get slow.
- **Deploy:** back up, `check_duplicates`, `migrate`.
- Root submodule pointers still not bumped.

---

# Phase 3 follow-up: dev migrate, probe, frontend (backend `828e3b4`, frontend `f57a4cf`)

## Dev DB
- Backed up to `<scratchpad>/db.sqlite3.before-phase3`, `check_duplicates` OK (parent check skipped: table did not exist yet), `migrate` applied `accounts.0021` and `0022` cleanly. Dev data otherwise untouched.

## Probe results
- **`scripts/api_probe.py`** (449 endpoints, 6656 requests, scratch DB copies; reads and writes, all 5 roles): the new routes behave as designed. `parents/`, `parents/template/`, `parents/bulk_import/`: admin 200/201, teacher/staff/parent/student 403. Rival parent id (`parents/46/`): admin 404, everyone else 403. Rival link id: 404. No Rival rows visible to Demo, no Rival mutations. Same 25 FK action-endpoint hits and 4 shared-row deletes as before (all pre-existing, none on parents). 166 "unexpected 2xx" are the existing unguarded endpoints, none are parent routes.
- **One 500:** admin `POST /api/v1/auth/password/reset/` (`NoReverseMatch: 'password_reset_confirm'`). Reproduced on a DB copy for any email. It is the reset-link URL name clashing between allauth and `accounts/urls.py`, not part of this work and not fixed. The other roles got 200 because the probe's first call per role differs; the bug is real for every account. Needs its own fix.
- **`scripts/parent_privacy_probe.py`** (new, read-only, run on a scratch copy where I gave the parent profiles national IDs and alternate phones so a leak would be visible): 63 requests as all 7 Demo users, **0 failures**. Confirmed: no Rival parent, profile, email or national ID in any response; the teacher gets no parent `national_id_no`, `phone` or `alt_phone` from `users/parents/`, `users/?role=PARENT` or any other checked list; a parent gets 403 on `parents/` and sees only themself in `users/parents/`; students see no parents. Not covered by the seed (no Registrar/Principal user): those roles are covered by `accounts/test_parents.py`.

## Backend additions
- `/api/auth/users/me/` now returns `groups` (names of the caller's own permission groups, empty on anyone else's record) so the frontend can show or hide controls.
- Parents import: `parents/template/` and `parents/bulk_import/` (ADMIN/Registrar only, preview then confirm, columns NAME, PHONE, EMAIL, NATIONAL_ID_NO, ALT_PHONE, ADDRESS, OCCUPATION, GENDER, CHILD ADMISSION NUMBER, RELATIONSHIP). Matches by national ID, phone, email; a conflicting national ID or unknown admission number fails the row. Logged as import type `parents`.
- Tests: 29 in `accounts/test_parents.py` (import, permissions, `me` groups added); `accounts core messaging` 292 passed.

## Frontend (answer to your question 3: Phase 2 frontend was NOT done; now done)
- `utils/permissions.js`: relationship list (FATHER/MOTHER/GUARDIAN/OTHER), role helpers from `user.groups`, authenticated file download.
- `Parents.jsx`: uses `/api/auth/parents/` with server-side debounced search; ADMIN/Registrar get edit, add, delete, "Add child" (learner picker + relationship dropdown), remove link, and an Import button (shared `ImportDialog`, server template); Principal sees the same table read-only with no national ID column; everyone else sees "no access". The sidebar hides Parents for roles that cannot open it.
- `Staff.jsx`: `ImportDialog` with the server 7-column template; group dropdowns and filter come from `/staff-groups/`; a Groups dialog (add, rename, delete custom groups, server messages shown); ADMIN/HR get add/edit/deactivate/import, everyone else read-only; deactivation-guard messages shown.
- `Students.jsx`: import default relationship is `GUARDIAN` (the only other place the old free-text `Parent` was written). No other parent-link form existed.
- `vite build` succeeds. **Not click-tested in a browser** and there is no frontend test suite or eslint config in the repo, so the UI is verified by build only.

## Needs your attention
- Fix the password-reset `NoReverseMatch` (separate change).
- Click-through with seed accounts (no Registrar/Principal/HR seed user exists: add them to `seed_dev_users` or tell me to).
- Frontend commit contains only my files; `.gitignore`, Android files and `gen-api-client.sh` in the frontend repo were already modified and left alone.
- Root submodule pointers still not bumped.
