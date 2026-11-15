# Phase 1 report: foundations

Branch `feat/school-data-management` (backend). Production untouched. Dev DB only.

## Commits (backend)
- `bb697e9` pytest.ini: `testpaths = .`, `python_files` adds `*_tests.py`, `norecursedirs` excludes venvs, node_modules, graphify-out and `backend` (a tracked stray copy `backend/backend/clubs`, left in place; deleting needs your OK). Pytest collects 453 tests, equal to `manage.py test`; all passed. Earlier "full suite" counts (409/422) had missed apps outside the old hand-listed `testpaths`.
- `c43718d` Phase 1. Full suite: 491 passed (453 + 38 new), 177 s.

## What changed
- **Groups:** `accounts.0015` creates Principal and Registrar (data migration, `get_or_create`).
- **Permission helpers** (`accounts/permissions.py`, unused until later phases): `in_school_group`, `can_manage_staff_records`, `can_manage_learner_records`, `can_manage_classes`, `IsStaffRecordsManager`, `IsLearnerRecordsManager`, `IsClassManager`, `IMPORT_TYPES_BY_GROUP`, `readable_import_types`, `IsImportLogReader`.
- **Import reports (`BulkImportLogViewSet`) restricted.** Teachers could read them before, including row errors naming admission/employee numbers. Now: ADMIN all types of own school; Principal streams/students/parents/staff; Registrar students/parents; HR staff; teacher/parent/student/other staff 403. Streams import no longer swallows a failed log write. Added `skipped_count` (`academics.0012`).
- **`core/imports.py`:** CSV/XLSX only with content checks, 5 MB, 2000 rows, 60 columns, 2000 chars/cell, xlsx `data_only` plus zip-bomb cap. Preview by default (stores nothing without `confirm=true`). Per-row savepoints; outer rollback on dry run or unexpected error (`ImportAborted`, 500). `BulkImportLog` + `AuditLog` on confirm. `escape_cell` neutralises cells starting `=`, `+`, `-`, `@`, tab, CR in templates and exports.
- **Bug found in testing and fixed:** an oversized CSV field raised an unhandled `csv.Error`; now `ImportRejected`.
- **`User.middle_name`** (`accounts.0016`, default `''`) in `UserSerializer`, `UserCreateSerializer`, `UserDirectorySerializer` and the existing student import.
- **Blank NEMIS/assessment numbers stored as NULL** (serializer and student import); `accounts.0017` converts existing blanks (reverse is a no-op).
- **Tests:** `core/test_imports.py`, 38 tests.

## Verification
- Probe (`scripts/api_probe.py`, scratch DB copies only): no 500s; no Rival rows visible to Demo; no Rival mutations; the same 25 FK action-endpoint hits and 4 shared-row false positives as before. Teacher and parent get 403 on import reports. `staff@demo.com` (Finance + HR groups) gets 200 and sees only `staff`-type reports (none exist).
- Dev DB backed up to `/tmp/claude-1000/-home-joe-Documents-Code-my-django-project/1f185aa0-0a74-420b-8b17-166fe4e79d5f/scratchpad/db.sqlite3.before-phase1` (Phase 0: `.before-phase0`), then migrated cleanly. The one blank NEMIS/assessment row became NULL. Groups now: Finance, HR, Health, Principal, Registrar.
- `graphify update .` run after the commit.
- `DATABASE-CHANGES.md` has the Phase 1 entry.

## Uncommitted / not done
- **Frontend `ImportDialog.jsx`** (`frontend/codingclubskenya/src/components/`): preview/confirm/report dialog, untracked in the frontend submodule (you said commit in backend only). Not wired into any page. Syntax-checked with esbuild only; there is no frontend lint/test config and no browser test.
- **`docs/specs/*`** untracked at repo root.
- **Root submodule pointers** not bumped (only on your request).
- Backend untracked junk left alone: `pytest.ini.orig`, `requirements_fixed*.txt`, `graphify-out/`.

## Needed from you
1. Say if I should commit `ImportDialog.jsx` in the frontend submodule.
2. Say if `backend/backend/` (stray duplicate clubs copy) may be deleted.
3. Production deploy later: back up, `migrate` (0015-0017, academics 0012), then add users to Principal/Registrar in Django admin. Phase 0 order (`check_stream_years` → `ensure_school_years --apply` → `migrate`) is in `DATABASE-CHANGES.md`.

## Open items carried forward
- Staff template in `Staff.jsx` has 10 columns vs spec's 7 core columns: settled in Phase 2.
- STAFF/TEACHER writes outside `accounts.test_write_access.GUARDED` not reviewed.
- `UserViewSet.parents` directory still returns parent phone to teachers: Phase 3 slim serializer.
- Duplicate audits needed before later unique constraints (admission number per school, staff national ID per school, parent national ID).
