# Phase 4 report: students

Branch `feat/school-data-management` (backend + frontend). Production untouched; dev DB not migrated for 0023/0024 (tests run on fresh DBs). Nothing committed yet in the submodules.

## What changed
- **Migrations:** `accounts.0023` (seed BOM/PA staff group for schools that already have groups; new schools get it lazily, `DEFAULT_GROUPS` now six) and `0024` (admission numbers trimmed, blank to NULL, abort listing duplicates, then unique per school case-insensitively). Details in `DATABASE-CHANGES.md`.
- **Student import rewritten** (`accounts/student_import.py`, `users/bulk_import/` same URL): preview by default, `confirm=true` saves; CSV/XLSX `file` or JSON `students` list; `users/template/` for the template. A legacy JSON body with no `confirm` key still saves immediately (old contract), and the response keeps `created`, `created_rows`, `errors`. Per row: school-scoped class match on grade + stream (+ academic year; current year wins when several), parent via `match_or_create_parent` (phone/email/national ID, conflict fails the row), enrollment plus `StudentClassEnrollment` history, capacity check, one savepoint per row so a failed row leaves no orphan User, `BulkImportLog` + `AuditLog` on confirm only. Access: ADMIN and Registrar (was ADMIN only); Principal and teachers get 403.
- **Transfers** (`enrollments/reassign_student/`): ADMIN and Registrar, capacity check, old history row closed as `transferred`, new one opened, `AuditLog` entry, parent links untouched, same-class is a no-op.
- **Benchmark additions:** `streams/<id>/class-list/` (school header, teacher, boys/girls/total, learners; teachers only for classes they teach or supervise, ADMIN/Registrar/Principal for all classes of their school, 404 across schools); `streams/summary/` now has `boys`, `girls`, `other_gender`.
- **Frontend:** `Students.jsx` now uses the shared `ImportDialog` (preview, then confirm); the old client-side parser and modal are removed. `ImportDialog` offers a one-time "Download credentials" CSV when a confirmed report carries temporary passwords.

## Verification
- 25 new tests in `accounts/test_students.py` (import, preview, legacy body, sibling parent reuse, duplicates, unknown class, cross-school class, blank NEMIS x2, capacity, parent conflict, access, CSV upload, log, transfers, class list, counts, BOM/PA seed and migration, constraint). `accounts.test_staff` and `accounts.test_students`: 77 passed.
- Updated three existing tests: `check_duplicates` tests now create untrimmed duplicates via `update()` because the constraint blocks exact ones; the staff migration test pins the original five groups; `test_bulk_import_no_default_password` expects an unusable parent password.
- Frontend: `npm run build` passes; lint shows no warnings in the two touched files. No browser click-through yet.
- Full suite: 677 run, 674 pass; the only errors are the 3 pre-existing `test_repair_sites_history` tests (Postgres-only SQL on sqlite).

## Needs your attention
- **Behaviour change:** parents created by the student import no longer get a temporary password (unusable, as in Phase 3); `new_parent_credentials` is now always `[]`. They sign in via password reset, which has the known 500 from Phase 3 (`password_reset_confirm` NoReverseMatch), so fix that before relying on it.
- **Stricter parent rule:** a parent name without phone, email or national ID now fails the row (previously a synthetic email was made).
- **Legacy `class` column:** the old client sent the same text as both `class` and `grade`; the new file template uses GRADE + STREAM. A JSON row with only `class` is treated as a stream name.
- **Deploy:** back up, run `check_duplicates` (0024 aborts on any duplicate admission number, listing them), then `migrate`. Do not apply to prod without your go-ahead.
- **Pre-existing, unrelated:** `accounts.test_repair_sites_history` (3 tests) fails on the sqlite test DB because it runs `DROP TABLE ... CASCADE` (Postgres syntax). I did not touch it.
- Principal can read class lists but cannot import or transfer; say if that should change.
- Not done: class-list printout UI (Phase 5), dev DB migrate, probe script, root submodule pointer bump, commits.

---

# Phase 4 follow-up: password reset, Postgres run, commits

## Password reset for imported parents
- The `NoReverseMatch` 500 from Phase 3 was already fixed on this branch (`e503a88`, reset email links to `FRONTEND_URL`). No new fix was needed.
- New test `accounts.test_password_reset.ImportedParentActivationTests`: import a student with a parent (unusable password) as a Registrar, `POST /api/v1/auth/password/reset/` for the parent's email gives 200 and one email with the `FRONTEND_URL/reset-password?uid=...&token=...` link, confirm sets the password, `POST /api/auth/login/` then returns 200.

## Full suite on Postgres
- Throwaway `postgres:16` container (prod is 16.x), `core.settings_test`: **678 tests, OK** (includes the 3 `repair_sites_history` tests that fail on SQLite). Container removed afterwards. The earlier SQLite run: same tests, only those 3 errors.

## Decisions applied
- Parent without phone/email/national ID stays a row error. Imports and transfers stay ADMIN + Registrar (Principal gets it by being in the Registrar group).
