# Phase 6b report: data hygiene before Release 2 (2026-11-18)

## 1. Changes
| # | Change | Where | Tests |
|---|---|---|---|
| 1 | `normalise_ke_phone` (07xx / 01xx / 7xx / 254 / +254, spaces, dashes, dots, brackets) → `+2547XXXXXXXX` / `+2541XXXXXXXX`; invalid raises `InvalidPhone`. `normalise_or_keep` is the lenient form (legacy values that do not parse are left as they are). | `backend/core/phone.py` | `accounts/test_phase6b.py` |
| | Stored canonical on every save: `User.phone`, `ParentProfile.alt_phone`, `StaffProfile.phone` (model `save`). Rejected as 400 / row error when invalid: model-field validator (all serializers, staff import), parent serializer phone, `match_or_create_parent` (parent import, student import parent), student import's own phone. Parent matching compares canonical forms. A parent edit that would give two parents one number is a 400. | `accounts/models.py`, `parents.py`, `serializers.py`, `student_import.py` | variants, invalid, import preview/confirm, matching |
| | Data migration `accounts.0025_phone_canonical`: converts existing valid numbers; unparseable numbers are left alone. If two different PARENT users of one school would share a number it aborts with no change and lists them. `check_duplicates` reports the same pairs (`parent phone`). | | `PhoneMigrationTests` (convert, merge-abort, check_duplicates) |
| 2 | Class names unique per school + grade ignoring case: `Stream.save` trims; DB constraint `uniq_stream_name_ci_per_grade` on `Lower(name), school, grade`; API returns 400 with a clear message; stream bulk import reuses an existing class ignoring case. Names keep their typed case (not casefolded in storage; the constraint and lookups ignore case). Migration `academics.0014_stream_name_ci_unique` trims names, aborts and lists clashes. `check_duplicates` reports `stream name`. | `academics/models.py`, `serializers.py`, `views.py` | `academics/test_phase6b.py` (trim, constraint, 400, import, migration trim, migration abort) |
| 3 | Serializers default `academic_year` / `term` to the school's current ones on create (explicit values win; no current year leaves a class's year unset; another school's current year is never used): Stream, TeacherAssignment, Timetable, Assignment, StudentClassEnrollment. Add Class form pre-fills the current year. | `CurrentYearTermDefaultsMixin` in `academics/serializers.py`; `frontend/.../Classes.jsx` | `DefaultsTests` |
| 4 | `class-teachers` writes need `can_manage_classes` (ADMIN, Principal, Registrar); Finance, HR and plain STAFF get 403 on create, update and delete; reads unchanged. | `ClassManagerWriteOrReadOnly` | `ClassTeacherWriteTests`; `test_write_access` now lists the route as ADMIN-only |

Existing tests that used non-Kenyan filler numbers (`1`, `0700`, `'+254700`) or asserted the raw stored form were updated; no behaviour test was loosened.

Not covered (left as typed, no matching or uniqueness depends on them): `emergency_contact_phone`, learner profile guardian phones, school/other-module phone fields.

## 2. Verification
- **Full suite on Postgres 16 (throwaway container): 771 tests, OK** (746 before). The default dev settings are SQLite, so Postgres needs `DATABASE_URL=postgres://...`.
- **api_probe (10,350 requests, 7 roles):** no 500s. Unexpected non-admin 2xx: 310 (was 311): the `staff POST academics/class-teachers/` line is gone. FK cross-tenant "2xx": 37, same previews/no-ops as before; no Rival row changed.
- Dev DB migrated (`0014`, `0025`): `check_duplicates` OK.

## 3. Release 2 rehearsal on a FRESH prod dump
- On the server: `~/deploy-scripts/backup.sh` → `/home/devops/backups/school_mgmt-20261118-081130.dump` (1,063,557 bytes, 2077 TOC) and `media-20261118-081130.tgz`; `scp` of the dump only to `~/prod-backups/school_mgmt-20261118-081130.dump`. Nothing else was run on the server.
- Restored into a throwaway `postgres:16` (`school_rehearsal`, removed afterwards). Prod today: 5 users (1 with a phone), 0 classes, 0 learner profiles, 0 staff profiles, 0 parent profiles, 1 school.
- Ran with `core.settings_production` and code from `feat/school-data-management`:

| Step | Result |
|---|---|
| `check --deploy --fail-level ERROR` | exit 0 (427 warnings, drf-spectacular schema notes) |
| `check_duplicates` | OK (now also checks stream names and parent phones) |
| `check_stream_years` | OK, 0 classes |
| `ensure_school_years` dry run, then `--apply` | 0 to create |
| `check_stream_years` | OK |
| `repair_sites_history` | consistent |
| `migrate` | `academics` 0009-0014 and `accounts` 0015-0025 applied cleanly |
| `makemigrations --check` | no changes |
| `check_duplicates`, `check --deploy` after | OK, exit 0 |
- After: constraints `uniq_primary_supervisor_per_stream`, `uniq_stream_name_ci_per_grade`, `uniq_student_admission_per_school` exist; the one stored phone is canonical.
- **Limit:** with no classes, learners or parents in prod, the data migrations (0010, 0013, 0024, 0025, academics 0014) only ran on empty tables; their data paths are covered by the Postgres migration tests.
- **Mistake caught and redone:** my first rehearsal pass ran against the local dev SQLite file, because `core.settings_production` reads `DB_*` variables and ignores `DATABASE_URL`. It changed nothing meaningful there (0 years created; it applied the production-only `axes` and `guardian` migrations to the dev DB). The results above are from the second pass with `DB_*` pointed at the restored container (checked: `postgresql 127.0.0.1:54398`).

## 4. For the deploy
- `check_duplicates` before migrating now also lists parent users who would share a phone and class names that differ only by case.
- Deploy the web frontend together with the backend (as before).
- The phase 6 leftover about Finance/HR writing `class-teachers` is closed.
