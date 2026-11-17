# Phase 5 report: classes

Branch `feat/school-data-management` (backend + frontend). Production untouched; dev DB not migrated for `academics.0013`. **Not committed yet** (waiting for your go-ahead).

## What changed
- **Supervisor rules** (`academics/supervisors.py`): `assign_supervisor(stream, user, acting_user)`. Eligible: active TEACHER user of the same school with an active, same-school `StaffProfile`. One transaction: old primary row deleted, new primary written, `AuditLog` entry with before/after; same teacher again is a no-op; `None` clears. Used by `streams/<id>/supervisor/` (POST `staff_profile_id` or `teacher_id`, DELETE clears; ADMIN and Principal only), by `class-teachers` writes that set `is_primary` (Principal can now write there; editing a primary row's teacher/stream is refused, use the supervisor endpoint), and by the streams `bulk_import` (so an ineligible supervisor now fails the row).
- **Migration `academics.0013`:** demotes duplicate primaries (keeps the most recent), then partial unique constraint. `StreamSerializer.supervisor` and `streams/summary/` now show the **primary** row (before: `.first()`).
- **Class detail** `streams/<id>/overview/`: header, supervisor, boys/girls/other, capacity, available capacity, learners. Teachers only for classes they teach or supervise; 404 across schools.
- **Filters** on `streams/`: `academic_year`, `grade`, `level` (grade stage), `stream` (name contains), `status`.
- **Guards:** a class with active learners cannot be archived (`status=inactive`); a class with active learners or enrollment history cannot be deleted (400 with a reason).
- **My Classes** `streams/my-classes/`: the caller's own active `TeacherAssignment` rows (subject classes) plus classes they supervise, with boys/girls/total.
- **Gender counts:** `summary` and `overview` give boys/girls/other.
- **Subjects on Add Class:** `streams/subject-options/?grade=` (school's active subjects grouped by category/type); `streams/<id>/subjects/` and `POST streams/` with `subject_ids` set the class's subjects as audited `StreamSubjectOverride` rows (`add` for non-inherited picks, `remove` for inherited ones left out, existing override updated not duplicated, one `StreamSubjectOverrideAudit` row per change, atomic with class creation, academic year required, ADMIN/Principal only).
- **Class-list printout** `streams/<id>/class-list/?fmt=xlsx|csv`, `list_type=basic|custom`, `columns=admission_number,name,gender,nemis_number`, `blank=N` extra empty columns. Header block (school, phone/email, title, class teacher, counts); every text cell formula-escaped (`tabular_response` gained `title_rows`). Same access rules as the JSON class list.
- **Frontend (`Classes.jsx`):** My Classes now shows only the user's own classes with counts and a download button; Manage Classes shows real boys/girls per grade (was total/2) and per-stream supervisor assignment through the new endpoint (error text from the server, "No supervisor" option) and a Class list download; the subject matrix comes from the API (was a hard-coded list that was never saved) and is saved with the class. The dead per-grade supervisor dropdown and no-op Manage/Class List buttons were removed.

## Verification
- 23 new tests in `academics/test_phase5.py` (eligibility cases, replace and audit, no-op, clear, access, constraint, migration demotion via `MigrationExecutor`, summary shows primary, class-teachers endpoint, streams import, filters, guards, overview, my-classes, subject options/set/idempotence/audit/atomic create, XLSX header block and escaping, custom columns, CSV, scope).
- **Full suite on Postgres 16 (throwaway container): 701 tests, OK.**
- Frontend: `npm run build` passes. `Teachers.jsx` only reads `class-teachers`, so it is unaffected. No browser click-through yet.

## Needs your attention
- **Migration data step:** on production, any stream with two primary rows loses primary status on the older ones (they stay as non-primary rows). Check with a query before deploying if you want to see them first.
- **Behaviour change:** `class-teachers` primary writes and the supervisor endpoint need ADMIN or the Principal group; a plain STAFF-role user can no longer set a supervisor via `class-teachers`.
- **Teacher access to non-primary rows:** only the primary supervisor appears as "supervisor" now; a teacher with only a non-primary `ClassTeacher` row still has class scope but is shown as no supervisor.
- **Existing gap, left alone:** `StreamViewSet` still lets any TEACHER create/update classes (as before); subject setting and supervisor changes are restricted, class create/update is not.
- Not done: PDF class list (exams release), dev DB migrate, probe script, browser check, commits, submodule pointer bump.

---

# Phase 5 follow-up: class write access

- **Rule:** create/update/archive of classes (streams), streams import, subjects and supervisor changes use `can_manage_classes` = ADMIN, Principal group, Registrar group, platform admin. **Delete: school ADMIN or platform admin only.** Teachers (and every other role) are read-only: they still get My Classes, class lists of their own classes and the class overview. New permission class `IsClassManagerOrReadOnly`; `can_manage_classes` now includes Registrar.
- **Frontend:** the Manage Classes and Add New Class tabs and both "New Class" buttons only show for users who can manage classes (`canManageClasses` in `utils/permissions.js`).
- **Tests:** `ClassWriteAccessTests` (4 tests: create/update/archive per role incl. superuser, delete admin-only, teachers read, cross-school 404); `accounts/test_write_access.py` has `academics/streams/` (ADMIN by role; groups covered in `test_phase5.py`). Three older tests that encoded "teachers may create/edit classes" now assert the new rule: `StreamRBACTests` (renamed `test_teacher_cannot_create_stream`), `test_stream_delete_admin_only`, and the `registrar.classes` cell of the permission matrix in `core/test_imports.py`.
- **Postgres 16, full suite: 705 tests, OK.**
