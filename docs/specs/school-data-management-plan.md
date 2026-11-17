# Plan: School Data Management (classes, students, parents, staff)

Spec: `school-data-management.md`. Plan mode: no code written yet. Revision 3 (your decisions applied, section 5). Revision 2 was re-checked with graphify (graph rebuilt, 5622 nodes) and by reading the located lines.
Paths are under `backend/` unless noted.

## 0. Changes from revision 1
1. **Academic year:** `academics.SchoolAcademicYear` already exists (school-scoped, unique per school and name, `academics/models.py:599`, route `school-academic-years`). Revision 1 pointed at `booklists.AcademicYear` (global, wrong one). No new model. `Stream.academic_year` stays a string and is validated against `SchoolAcademicYear`. Converting the string to a FK is the separate pending change D10 in `project plan/DATABASE-CHANGES.md`, which needs your approval.
2. **Student history and transfer:** `academics.StudentClassEnrollment` (per-year history, status, `ended_on`) and `EnrollmentViewSet.reassign_student` (`academics/views.py`, ADMIN-only) already exist. Transfer will extend them. Revision 1's "new transfer endpoint" is dropped. Current gaps: `reassign_student` writes no history row, no audit and no capacity check. `users/bulk_import` also writes no history row.
3. **Supervisor:** `StreamViewSet.bulk_import` (`academics/views.py:179`) already selects the supervisor from `StaffProfile` by employee number (active, linked to a user) and writes `ClassTeacher(is_primary=True)`. That logic becomes a shared helper. It is incomplete in three ways:
   - It never checks the Teaching Staff group or the TEACHER role.
   - `update_or_create(stream, teacher)` leaves the previous primary in place, so a stream can have several primaries.
   - `StreamSerializer.get_supervisor` (`academics/serializers.py:63`) and `StreamViewSet.summary` take `.first()` of `class_teachers`, not the `is_primary` one, so the shown supervisor can be wrong.
   `ClassTeacher` also grants scope elsewhere (`attendance/views.py:198`, `messaging/views.py:88,641`), so removing a former supervisor revokes their attendance and messaging access. This is the decision in section 5.
4. **BulkImportLog reuse, with fixes:** it is written only by the streams import, inside `try/except: pass` (errors are swallowed). `BulkImportLogViewSet` is readable by `IsAdminOrStaffOrTeacher`, so teachers can read error rows (admission and employee numbers). Plan: restrict to the roles that run the import, add `skipped_count` (additive migration), write the log in the same transaction, no swallowing.
5. **users/bulk_import (`accounts/views.py:187`) is not safe to reuse as is:**
   - Not atomic. The User is created before the profile, so a later failure can leave an orphan User.
   - ADMIN-only, so Registrar is excluded.
   - No size or row limit, no dry-run.
   - Parent matching uses email, then phone only. The national ID branch is a literal `pass`, because parents have no profile.
   - Class matching uses `Stream.name` only (first match across all grades), so "East" resolves to the wrong grade. The `CLASS`+`STREAM` pair is only tried when the first lookup misses.
   - Admission-number uniqueness is code-only.
   - `nemis_number` is `unique=True, null=True` but the import writes `''`, which likely collides on the second blank row (verify with a test before relying on it).
   - It returns temporary passwords in the response (shown once). Keep that behaviour.
6. **StaffProfile:** `StaffProfileViewSet` is `IsHRRole` but `get_queryset` returns only the caller's own profile unless the user is ADMIN or platform admin, so HR-group users see nothing useful. `bulk_import` is ADMIN-only and uses `objects.create`, which skips the serializer's choices check, so `group` and `gender` accept free text. `accounts.TeacherProfile` (global-unique `employee_id`, `national_id`) is a third staff-like table. Leave it and `payroll.StaffProfile` alone (merging them is D1, needs approval). Staff imported without a `user` can't supervise, so the import links by email to an existing TEACHER user in the same school.
7. **Parents:** `ParentLearnerViewSet` is ADMIN-write and shows non-admins only `parent=user` rows, so Registrar and Principal are not covered. `UserViewSet.parents` returns the full `UserSerializer` (including `phone`) to TEACHER via `_directory`, which violates the rule that parent phone is for ADMIN and Registrar only. It needs a slim serializer. `StudentProfile` already has `guardian_name`, `guardian_relation` and extra phones, so no more guardian fields are added to students. `ParentLearner` stays the source of truth.
8. **Frontend:** `Classes.jsx` already calls `staff-profiles`, `class-teachers`, `enrollments/reassign_student` and `streams/bulk_import`. `Teachers.jsx` also calls `class-teachers`, so supervisor changes need a regression check there. `Parents.jsx` uses only `auth/users` and `parent-learner-links`. `Students.jsx` posts JSON rows (parsed in the browser) to `users/bulk_import`.

### Revision 3: changes from your decisions
1. **`ParentProfile`** (one-to-one to `User`, role PARENT) holds `national_id_no`, `alt_phone`, `address`, `occupation`, `gender`. Relationship moves to `ParentLearner.relationship` with choices FATHER, MOTHER, GUARDIAN, OTHER (a data migration maps the existing free text, e.g. "Parent", "Mother", to these values; unmapped values become OTHER and are listed in the migration output). `User.address` stays as is and is not copied.
2. **Supervisor history** is `AuditLog` only, no new table.
3. **One primary per stream:** partial `UniqueConstraint(fields=['stream'], condition=Q(is_primary=True))` on `ClassTeacher`. A data migration runs first: for each stream with more than one primary, keep the most recent (highest `id`, since the model has no timestamp) and set the others to `is_primary=False` (not deleted, so their attendance and messaging access is kept). It prints the demoted rows. Same-migration order: data step, then constraint.
4. **Eligibility:** active `User(role=TEACHER)` that has a `StaffProfile` (`employee_profile`, same school, `employment_status='Active'`). The Teaching Staff group is no longer required.
5. **Supervisor change** deletes the old primary `ClassTeacher` row and writes an `AuditLog` entry (before/after). This revokes their attendance and messaging scope through that class, as intended.
6. **`middle_name`** is a new field on `User` (blank, max 100). It is added to the user serializers and, for imports, `MIDDLE_NAME`. Parent import splits `PARENT_NAME` as before; only `ParentProfile` has no separate middle-name field.
7. **D10 (own step, Phase 0):** `Stream.academic_year` becomes a FK to `SchoolAcademicYear`. See Phase 0.
8. **`nemis_number` / `assessment_number`:** confirmed. Both are `unique=True, null=True`. `users/bulk_import` writes `''` for blanks (`accounts/views.py:265-266`), and the local dev database already has one `''` in each column, so a second blank student collides. Fix: store `None` for blanks in the import and the serializers (`or None`), and a data migration `''` to `NULL` for both columns. Same for `StaffProfile.national_id_no` (already `or None` in the import) and any other `unique, null=True` text field written from imports.

## 1. Gap analysis

### Terminology map (spec → existing)
| Spec | Existing | Where |
|---|---|---|
| Class | `Stream` (grade, name, code, capacity, status, `academic_year` string) | `academics/models.py:63` |
| Grade/Level | `Grade` (+ `EducationLevel`); may be `school=NULL` (shared) | `academics/models.py:24` |
| Class supervisor | `ClassTeacher` (`is_primary`) | `academics/models.py:194` |
| Current allocation | `Enrollment` | `academics/models.py:208` |
| Allocation history | `StudentClassEnrollment`, `StudentPromotion` | `academics/models.py:616,646` |
| Student | `User(role=STUDENT)` + `StudentProfile` | `accounts/models.py:80` |
| Parent | `User(role=PARENT)` + `ParentLearner` | `accounts/models.py:68` |
| Staff | `accounts.StaffProfile` | `accounts/models.py:185` |
| Academic year | `SchoolAcademicYear` | `academics/models.py:599` |
| Import report | `BulkImportLog` | `academics/models.py:676` |
| Audit | `audit.AuditLog` | `audit/models.py` |

### Per spec section
**§2 Classes**
- Exists: Stream CRUD, `summary` (counts, capacity, supervisor), `ClassTeacher` CRUD, streams `bulk_import` with supervisor, `Classes.jsx` (1077 lines).
- Missing: single-primary guarantee, eligibility (active, Teaching Staff, linked TEACHER user), supervisor history, archive/delete guard, class detail with students, capacity check at allocation.

**§3 Students**
- Exists: `users/bulk_import`, `reassign_student`, `StudentClassEnrollment`, `Students.jsx` (332 lines). `StudentProfile` already holds admission date, gender, previous school and many identity fields.
- Missing: everything in section 0 items 2 and 5, plus template download, preview, report, `User.middle_name`, student status (check existing `is_active`), and `None` instead of `''` for blank `nemis_number`/`assessment_number`.

**§4 Parents**
- Missing: `ParentProfile` (`national_id_no`, `alt_phone`, `address`, `occupation`, `gender`), one-to-one with `User`. `User.middle_name`. Relationship choices on `ParentLearner`. Dedupe service, search, children list, slim serializers.

**§5 Staff**
- Exists: model with the 7 core fields, `StaffProfileViewSet`, `bulk_import`, `Staff.jsx`.
- Missing: server-side file parsing and template, configurable groups (`StaffGroup`), DB uniqueness for national ID per school, HR visibility fix, deactivation guard, slim serializer.

**§6/§7/§9** as in revision 1, with these updates:
- New tables stay minimal: `ParentProfile`, `StaffGroup`, plus additive `BulkImportLog.skipped_count`, `User.middle_name`, and `ParentLearner.relationship` choices.
- Constraints: `StudentProfile (school, admission_number)` (blank stored as NULL), `StaffProfile (school, national_id_no)` partial, `ClassTeacher (stream)` where `is_primary` (after the demotion data step). The first two need a duplicate audit first, or the migration fails.
- Supervisor history: `AuditLog`.
- Roles: Principal and Registrar groups via `accounts/migrations/0015_...` (same pattern as 0013/0014). `scope_to_own_learners` and `is_health_group_or_admin` in `accounts/permissions.py` are the templates.
- `core/shared_rows.py` blocks writes to `school=NULL` rows, so classes may reference shared grades but cannot edit them.

## 2. Shared security rules (every phase)
- `TenantFKValidationMixin` on all new and touched serializers. Every lookup scoped to `request.user.school`, including class, parent and staff matching in imports. `SchoolScopedViewSetMixin` on viewsets.
- Parent national ID and phone, staff national ID: ADMIN plus Registrar (parents) or HR (staff) only. Teachers get slim serializers chosen in `get_serializer_class`, including the `users/parents` directory.
- Imports, in one shared module `core/imports.py`:
  - Max 5 MB and 2000 rows, checked before parsing. Accept multipart CSV/xlsx (parsed server-side with `openpyxl`, already in `requirements.txt`, read-only) and the existing JSON rows contract (same row limit).
  - Preview is `dry_run`: validates, returns per-row results, writes nothing. Confirm re-submits and re-validates inside one `transaction.atomic()`. Valid rows are imported, invalid ones are reported as failed. An unexpected exception rolls back the whole import. Nothing is staged on the server.
  - Report and counts (created, failed, skipped) go to `BulkImportLog`, plus one `AuditLog` entry.
- Exports and templates: one helper escapes cells starting with `=`, `+`, `-`, `@`.
- Re-run `scripts/api_probe.py` at the end of each phase. Update `accounts/test_write_access.py` for new routes.

## 3. Phases (one session each; frontend last)

### Phase 0: D10 academic year FK (own step, before Phase 1)
- Scope: `Stream.academic_year` only. Other models keep their `academic_year` strings (`academic_year` appears in about 23 non-test places across apps; those that read `stream.academic_year` are listed by `rg` first and updated in the same step).
- Migrations, in order, so each is reversible and nothing is dropped until the data is verified:
  1. `makemigrations`: add nullable FK `Stream.academic_year_fk` to `SchoolAcademicYear` (`PROTECT`).
  2. Data migration (hand-written, like 0013/0014): for each stream, match `(school, academic_year string)` to `SchoolAcademicYear.name` (trimmed, case-insensitive). Blank strings map to NULL. **If any non-blank string has no match, the migration raises and aborts, listing every unmatched `(school, stream, value)`**; nothing is changed (single transaction). You then create the missing years, or correct the strings, and re-run. A read-only management command `check_stream_years` prints the same list before deploying, so the abort is not a surprise on production.
  3. `makemigrations`: remove the string field and rename `academic_year_fk` to `academic_year`. Only after step 2 has run clean and the code reads the FK.
- Code: serializers expose `academic_year` as the year's name for reads (keeps the API shape; frontend sends the name, the serializer resolves it within the school, 400 if unknown); `Stream` filters `?academic_year=` keep working by name. `unique_together` and other queries that used the string are updated.
- Tests: mapping (exact, whitespace/case), blank to NULL, abort lists unmatched and changes nothing, serializer rejects another school's year, filters, reverse migration.
- This is a production schema change: needs your go-ahead to apply, and `showmigrations` on prod checked first (per `DATABASE-CHANGES.md`).
- Record it in `project plan/DATABASE-CHANGES.md` (D10 moves from pending to this branch).

### Phase 1: Foundations
- `0015` Principal and Registrar groups; permission classes; `core/imports.py` (parse, limits, dry-run, escape helper); `BulkImportLog.skipped_count`; log viewset restricted by role. `User.middle_name` and the `nemis_number`/`assessment_number` `''` to NULL data migration (with the serializer `or None` fix) also go here, because every later import depends on them.
- Tests: group migration; limits (5 MB, 2001 rows); formula escaping; atomic rollback; teacher cannot read import logs; cross-school.
- Frontend: shared `ImportDialog` (upload, preview, confirm, report).

### Phase 2: Staff
- `StaffGroup` (seed the five defaults). `bulk_import` on the framework with the 7-column template (`EMPLOYEE NUMBER` and `EMPLOYEE_NUMBER` both accepted); group and gender validated against choices and `StaffGroup`; link to an existing TEACHER user by email. Fix HR visibility in `get_queryset`. Partial unique national ID. Deactivation guard (checks `ClassTeacher` via the linked user). Slim teacher serializer.
- Tests: exactly 7 core columns; duplicates (in file and DB); invalid group; HR sees all, teacher sees slim; deactivation guard.
- Scenarios: 4.

### Phase 3: Parents
- `ParentProfile` (`national_id_no`, `alt_phone`, `address`, `occupation`, `gender`; unique per school on `national_id_no` where not null). `ParentLearner.relationship` choices FATHER/MOTHER/GUARDIAN/OTHER plus the mapping data migration. `match_or_create_parent(school, national_id, phone, email)` (order: national ID, phone, email; phone normalised; a match found only by phone or email but with a different national ID is flagged as a conflict in preview, never merged silently); parents API with search and children; slim `users/parents`; Registrar/Principal access to `ParentLearner`.
- Tests: dedupe; one parent, several children; contact edit visible via student endpoints; teacher does not get phone/national ID; no cross-school match; relationship mapping migration; national ID conflict flagged.
- Scenarios: 3 (first part).

### Phase 4: Students
- Rewrite `users/bulk_import` in place (same URL, JSON contract still works). Fix class matching (grade+stream+year, school-scoped), parent matching via the phase 3 service, atomic per import, `StudentClassEnrollment` history rows, `BulkImportLog`. Admission-number constraint after audit. Extend `reassign_student`: capacity check, history (`transferred`), `AuditLog`; allow Registrar.
- Added from the benchmark review (`reports/benchmark-gap.md`): (a) data migration seeding a sixth default `StaffGroup`, BOM/PA (board and parent-association officials), idempotent per school, mirroring the Phase 2 seeding migration; (b) class-list data endpoint (admission number, name, gender, school header fields) and boys/girls/total counts per stream. Both school-scoped; teachers get the list only for classes they are assigned to (`TeacherAssignment`/`ClassTeacher`), Registrar/Principal for all classes in the school; no cross-school access.
- Tests: full import then verify enrollment and parent link; reused parent; duplicate admission numbers; unknown class; blank `nemis_number` on two rows; rollback leaves no orphan User; transfer keeps parent links; BOM/PA seed idempotent and per school; class list scoped to school and to a teacher's own classes; gender counts correct and school-scoped.
- Scenarios: 2, 3 (reuse), 6 (transfer).

### Phase 5: Classes
- Shared `assign_supervisor(stream, staff)` helper used by the class API and streams `bulk_import`: requires an active TEACHER user with a same-school active `StaffProfile`; deletes the old primary row and writes `AuditLog` (before/after) in one transaction. Duplicate-primary demotion data migration, then the partial unique constraint. Fix `get_supervisor` and `summary` to use the primary. Because `Stream.academic_year` is a FK after Phase 0, class filters and the `ACADEMIC_YEAR` import column resolve to `SchoolAcademicYear`. Class detail (students, counts, available capacity). Archive/delete guard when enrollments exist. Filters by year, grade, level, stream.
- Tests: ineligible supervisors rejected (inactive user, inactive staff, non-TEACHER, no `StaffProfile`, other school); change logged and old row deleted; duplicate-primary migration keeps the most recent and demotes the rest; constraint rejects a second primary; capacity numbers; delete blocked with students; teacher sees only own classes.
- Added from the benchmark review: "My Classes" teacher view (own `TeacherAssignment` rows only, with a class-list action); boys/girls/total on class detail and list; subjects picker on Add Class writing through the existing `CurriculumSubject`/`StreamSubjectOverride` audited paths (grouped by subject type); class-list printout, Basic and Custom columns, XLSX first via `openpyxl` (escape formulas with `core/imports.py` helper). PDF class list waits for the exams-printouts release (WeasyPrint).
- Regression: `Teachers.jsx` and attendance/messaging scope tests; teacher cannot open another teacher's class list.
- Scenarios: 1, 5, 6 (teacher deactivation).

### Phase 6: Integration, hardening, docs
- End-to-end test of scenarios 1–6 (include class list and BOM/PA group), audit coverage, export escaping review, full probe, `docs/specs/school-data-management-implementation.md`, frontend states and a local click-through with seed accounts only.

## 4. Scenario → phase map
| Scenario | Phases |
|---|---|
| 1 Create class | 5 |
| 2 Import students | 4 |
| 3 Verify parents | 3, 4 |
| 4 Import staff | 2 |
| 5 Change supervisor | 5 |
| 6 Data consistency | 4, 5, 6 |

## 5. Decisions (resolved)
1. `ParentProfile` added (`national_id_no`, `alt_phone`, `address`, `occupation`, `gender`); relationship on `ParentLearner` (FATHER/MOTHER/GUARDIAN/OTHER).
2. Supervisor history: `AuditLog`.
3. One primary supervisor per stream: partial unique constraint, after a data migration that keeps the most recent primary and demotes (does not delete) the others, reporting them.
4. Supervisor: active TEACHER user with an active, same-school `StaffProfile`.
5. Supervisor change deletes the old primary `ClassTeacher` row, logged in `AuditLog`.
6. `User.middle_name`.
7. D10 approved as Phase 0: `Stream.academic_year` to FK, abort listing unmatched strings.
8. `nemis_number`/`assessment_number`: NULL for blanks, plus `''` to NULL data migration.
9. Benchmark additions (Phase 2 already committed): BOM/PA `StaffGroup` seeded by a Phase 4 data migration; class lists school-scoped, teachers only their own classes; XLSX printouts first.

## 6. Risks
- Unique constraints on existing data (admission number, national ID, parent national ID) need a duplicate audit before the migration. The primary-supervisor constraint has its own data step.
- Phase 0 touches about 23 code sites and a production schema change; apply only with your go-ahead, after checking `showmigrations` on prod.
- Demoting duplicate primaries keeps those teachers' attendance/messaging access; deleting on a later supervisor change removes it. Intentional, but worth knowing.
- `User.email` is globally unique; parents without email need a synthetic one, as the current import does.
- Touches accounts and permissions: smallest change per step, re-run the probe.
