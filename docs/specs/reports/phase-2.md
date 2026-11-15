# Phase 2 report: staff

Branch `feat/school-data-management` (backend `65327fb`). Production untouched; dev DB migrated.

## Also done this turn
- Frontend `ImportDialog.jsx` committed in the frontend submodule (`52f22e0`). Root branch `feat/school-data-management` created; `docs/specs/` committed (`05a19b9`, no graphify-out).
- `backend/graphify-out` was already gone when I went to delete it. `graphify update .` was run from the repo root.

## Your four additions
1. **graphify** only from the repo root (done as above).
2. **Round trip:** `escape_cell` touches strings only (tests: int, float, Decimal, date, bool, None unchanged). Import now removes exactly one leading apostrophe when it protects a formula-looking value (`'+254712345678` becomes `+254712345678`; `'Mary` is left alone). CSV, XLSX and JSON paths tested.
3. **Confirm re-parses from scratch:** tests show a file changed between preview and confirm is validated as the new file (nothing from the previewed file is kept), state changed in between is re-validated, and a confirm without a file is a 400, never a replay.
4. **`check_duplicates`:** read-only, raw SQL, per school, trimmed and case-insensitive: student admission number, staff employee number, staff national ID, parent national ID (skipped until `accounts_parentprofile` exists). Exit 1 on any. Documented in `DATABASE-CHANGES.md`: must pass on production before the Phase 2 migrations, and again before Phase 3 and 4. Dev run before migrating: all OK.

## What changed
- **Migrations:** `accounts.0018` (StaffGroup, `group` loses its fixed choices), `0019` (data: blank national IDs to NULL, trimmed; aborts and lists duplicates before writing; seeds default groups per school), `0020` (unique national ID per school where not blank). I generated them before your additions arrived; they are unapplied on production.
- **Visibility fix:** HR group users used to see only their own row. ADMIN and HR now see and edit all staff of their school with the national ID. The Principal reads all staff through a slim serializer (no national ID) and cannot write. Teachers and other staff see only their own row, slim. Parents and students get 403. National ID search works for ADMIN/HR only.
- **Import:** `staff-profiles/template/` has exactly the 7 columns (`?fmt=xlsx` for Excel). `bulk_import/` runs on `core/imports.py`: CSV/XLSX or the old JSON list, preview by default, ADMIN/HR only. Accepts `EMPLOYEE NUMBER` and `EMPLOYEE_NUMBER`. Flags duplicates in the file and in the DB, invalid group or gender, blank required fields. Links by email only to an existing TEACHER/STAFF account of the same school with no staff record; never creates accounts.
- **Groups:** new `staff-groups` API (ADMIN/HR add; defaults cannot be renamed or deleted; a group with staff cannot be deleted; renaming a custom group moves its staff).
- **Guard:** deactivating or deleting a staff member who supervises an active class is refused (400) with the class names.
- **Audit:** staff records now go to the audit log, without the national ID.
- **Bug found by my own tests:** a group created before the defaults existed could shadow a default. Fixed.

## Verification
- Full suite: 548 passed (491 + 57 new), 137 s.
- Probe: no 500s, no Rival rows visible to Demo, no Rival mutations; the same 25 FK action-endpoint hits and 4 shared-row false positives as before. `staff@demo.com` can write staff routes because it is in the HR group (expected). Teacher, parent and student cannot.
- Dev DB backed up to `/tmp/claude-1000/-home-joe-Documents-Code-my-django-project/1f185aa0-0a74-420b-8b17-166fe4e79d5f/scratchpad/db.sqlite3.before-phase2`, then migrated cleanly.
- `accounts/test_write_access.py` now includes the two new routes.

## Needs your attention
- **Principal vs your rule:** your rule was national ID readable by ADMIN + HR only, so I made the Principal slim and read-only for staff. Say if the Principal should see national IDs.
- **Existing audit bug (not fixed):** `audit/signals.py` looks up snapshot fields with a lowercase key but the existing entries use `accounts.User` etc., so those snapshots are never taken. I used a lowercase key for staff only. Fixing the others changes what is stored in the audit log.
- **Frontend not changed:** `Staff.jsx` still posts parsed JSON and has a 10-column template. The JSON import still works but now returns the new report shape (`created`, `errors` kept). Wiring `ImportDialog` and the 7-column template is the frontend step.
- **Deploy:** back up, `check_duplicates` (must be OK), `migrate`. If 0019 aborts it lists the duplicates and changes nothing.
- Root submodule pointers still not bumped.
