# Phase 6 report: integration, hardening, release rehearsal (2026-11-17)

## 1. The four open items from phase-5.md (all fixed, with tests)
| Item | Change | Tests |
|---|---|---|
| Registrar reads learners | `UserViewSet.get_queryset`: Registrar/Principal (`can_manage_learner_records`) see their own school's STUDENT and PARENT users plus themselves, slim serializer (no address or date of birth). Other staff still see only themselves. | `accounts/test_phase6.py` `RegistrarReadTests` |
| Registrar registers one learner | `POST auth/users/` allowed for ADMIN and Registrar; the Registrar may only send `role=STUDENT` (anything else 403). Optional `stream` places the learner through `place_student` (capacity check, history row, same school, one transaction). Web form: "Register learner" with a class picker, shown to ADMIN and Registrar. | `RegisterLearnerTests` (10) |
| No direct `Enrollment` edits | `EnrollmentViewSet` is read-only for everyone; classes change only via register, import, transfer, promote. `Enrollments.jsx` is now a read-only list. | `test_learner_scope`, `test_write_access`, `test_cross_tenant_fk` updated; `api_probe` no longer expects Registrar writes on `enrollments/` itself |
| Modal error stays | `Classes.jsx` clears the move-modal error whenever the form changes. | browser only |

Found and fixed while doing the browser pass (all pre-existing):
- `UserCreateSerializer` passed the many-to-many `subject_specializations` into `User(...)`: every web-form create was a 500. Fixed (set after save); test added.
- The user form sent empty dates as `""` (400) and showed only "Save failed". Blank dates are now omitted and the first field error is shown.
- `student-class-enrollments/` was not learner-scoped: a parent read every learner's class history in the school (11 rows in dev). Now parents see linked learners, students themselves. Test added.
- Literal `&amp;` in the "Form & Stream Overview" heading.

## 2. Remaining Phase 6 items
- Scenarios 1–6 end to end through the API: `accounts/test_scenarios.py` (create class and supervisor; template, preview and confirm import; parent reused for a second child; staff import with duplicate, bad group and missing gender flagged; change supervisor; transfer keeps parent links; deactivation blocked until another supervisor is set).
- Audit coverage: supervisor change, transfer, promote and import confirm each add an `AuditLog` row (test).
- Export escaping: class-list CSV neutralises `=`, `+`, `-`, `@` cells (test).
- Docs: `school-data-management-implementation.md` (permissions table, rules), `DATABASE-CHANGES.md` Release 2 section (full migration table, production order, rollback), plan Phase 6 status.
- Benchmark additions are all in: My Classes, gender counts, subjects on Add Class, class-list XLSX, BOM/PA group.

## 3. Verification
- **Full suite on Postgres 16:** 746 tests, OK (before this phase's code: 724).
- **api_probe (reads and writes, 10,350 requests, all 7 roles):** no 500s, no Rival-school rows visible to Demo roles, no Rival rows changed. "Unexpected 2xx" list (311) is the existing set of teacher/staff writes outside this project (messaging, homework, attendance, shop carts, ...). For this project's routes the only line is `staff POST academics/class-teachers/` (201, own-school payload): STAFF is allowed to write non-primary class-teacher rows by the existing rule; primary supervisor changes still need `can_manage_classes`. FK cross-tenant "2xx" lines (37) are previews/no-ops (`streams/bulk_import` with a Rival grade reports row errors; `sync-from-curriculum`, `timetable/generate` return 200 with nothing written); no Rival row changed. (A first probe run was discarded: the dev server reloaded while I edited code and returned no response.)
- **Browser pass (Chrome, localhost only, seed accounts; the browser's saved admin login was overwritten before saving):**

| Scenario | Admin | Registrar | Principal | Teacher | Parent |
|---|---|---|---|---|---|
| 1 Create class / supervisor picker | picker shows the current supervisor (5b) | create via API test; picker (5b) | Manage Classes: assigned Second Teacher to Grade 7 East, "2 of 5 assigned" | no create/manage tabs | no access |
| 2 Import students | covered by 5b and tests | Import button shown; register form: registered "Pia Phase Six" into Grade 7 North (after the two fixes above) | no Register/Import buttons | none | none |
| 3 Parents page | lists parents with linked children, Jane Otieno linked to 2 children | (API/tests) | read | 403 | `auth/parents/` 403 |
| 4 Staff import | tests (preview/confirm, flagged rows) | n/a | n/a | n/a | `staff-profiles/` 403 |
| 5 Change supervisor | 5b | 5b | done in UI | read-only | none |
| 6 Transfer / consistency | 5b + test | 5b | no Transfer/Promote | none | history now scoped to own child |
| My Classes / class list | `/enrollments` read-only list | | empty (supervises none) | 2 own classes with roles and subjects; XLSX of own class 200, other class 403 | empty |
Console: no errors on the pages visited. Not clicked through in the UI this round (covered by 5b or API tests): staff import upload, transfer/promote modals as admin.

## 4. Release 2 rehearsal (no contact with production)
- Source: newest local dump `~/prod-backups/school_mgmt-20261116-173238.dump` (taken 2026-11-16 17:32, about a day old). I did not fetch today's from the server (that needs ssh and you said not to touch production).
- Restored into a throwaway `postgres:16` container (`school_rehearsal`), then ran with `core.settings_production` (random secret, local DB, no production values), in the order of `DATABASE-CHANGES.md`:

| Step | Result |
|---|---|
| `check --deploy --fail-level ERROR` | exit 0 (427 warnings, all drf-spectacular schema notes, none security) |
| `check_duplicates` | OK, no duplicates |
| `check_stream_years` | OK (0 classes in prod) |
| `ensure_school_years` dry run, then `--apply` | 0 to create |
| `check_stream_years` again | OK |
| `repair_sites_history` | consistent, nothing to do |
| `migrate` | 16 migrations applied cleanly: `academics` 0009-0013, `accounts` 0015-0024, plus `shop.0015_alter_product_image` (unrelated, from master) |
| `makemigrations --check` | no changes |
| `check --deploy` after | exit 0 |
- After: both constraints exist (`uniq_student_admission_per_school`, `uniq_primary_supervisor_per_stream`), groups Finance/Health/HR/Principal/Registrar, staff groups include BOM/PA, 5 users unchanged.
- **Limit:** prod has 0 classes and 0 learner profiles, so migrations 0010, 0013 and 0024 had no data to convert. They are exercised by their migration tests on Postgres. Re-run `check_duplicates` and `check_stream_years` against a fresh dump on deploy day.
- No failures. Not done on purpose: nothing was run on the server; the web frontend must be deployed together with the backend (old frontend calls routes whose permissions changed).

## 5. Known leftovers
- `staff POST class-teachers/` by Finance/HR staff (non-primary rows) is allowed by the existing STAFF rule; tighten if unwanted.
- `Enrollments.jsx` shows learner and class ids, not names (it was like that before).
- Seed first name "Demo" makes supervisor text read "Demo Teacher2".
