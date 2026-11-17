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

---

# Phase 5 verification: dev DB, probe, browser pass (2026-11-17)

Committed and pushed first: backend `5955681`, frontend `420448f`, root `4e00ba8` (Postgres 16 full suite: 705 OK before the commit).

## Dev DB
- Backed up SQLite to `<scratchpad>/db.sqlite3.before-phase5`. `check_duplicates`: OK (no duplicates). `migrate` applied `academics.0013`, `accounts.0023`, `accounts.0024` (and the unrelated pending `shop.0015_alter_product_image`). `seed_dev_users` re-run clean (Demo School id 1, Rival School id 2).

## api_probe (reads + writes, all 7 roles incl. registrar and principal, scratch DB copies)
- **10,121 requests, 0 responses of 5xx, 0 Rival rows visible to a Demo role, 0 Rival rows changed in the DB copy by a Demo role.**
- **Unexpected 2xx for non-admin roles: 344** (same families as before; the probe's GUARDED list does not know the Registrar/Principal groups). Relevant to this work:
  - registrar and principal: create/patch streams, `streams/bulk_import`, `class-teachers` write, `parents` write (registrar) are **expected** under the new rule (probe has no group awareness).
  - **teacher gets 403 on every stream write** (no stream line in the list for teacher): the new read-only rule holds. `staff` (HR+Finance groups in the seed) writing `staff-profiles` is expected.
  - **Not expected, pre-existing, not changed by me:** `student-class-enrollments` (enrollment history) POST returns 201 for teacher, staff, registrar and principal; `class-teachers` POST 201 for plain STAFF role (non-primary rows only; primary needs ADMIN/Principal/Registrar). History rows should probably be write-protected (ADMIN/Registrar) in a follow-up.
- **FK cross-tenant "accepted" 2xx: 37** = the same 25 action endpoints as Phase 3 plus the same 6 for each of the two new roles (12). They are actions that ignore the Rival id in the payload (`timetable/generate`, `sync-from-curriculum`, `regenerate_summaries`, `seed-defaults`, `sync_from_distributors`) and `streams/bulk_import` with a Rival grade *name* (creates a grade in the caller's own school). No row of another school was read or changed.

## Browser pass (Chrome, local dev only: frontend :5173, API :8000, seed accounts only)
Setup notes: the browser held a login for a non-seed student; I logged it out and used only `@demo.com` seed accounts. Dev data already had Grade 7 East, North and West, so the new class is **Grade 7 Zion** (capacity 40, year 2026, subjects English + Mathematics). `teacher2@demo.com` (a second TEACHER, no password) was added through `manage.py shell` so "change supervisor" had two eligible people; Demo School had no staff records, so scenario 4 had to come first. CSVs I authored: `<scratchpad>/browser/staff.csv`, `staff2.csv`, `students.csv` (one row deliberately has an unknown class).

| Step | Admin | Registrar | Principal | Teacher |
|---|---|---|---|---|
| 1 Create Grade 7 class with subjects (Add New Class) | PASS (duplicate East/West refused with a clear message; Zion saved, 2 subject overrides + 2 audit rows) | PASS (created "Registrar Test") | not run (tab visible) | PASS: no Manage/Add tabs, no New Class button |
| 4 Staff import (preview, confirm; BOM/PA group row; link by email) | PASS (3 rows, Demo Teacher linked to `teacher@demo.com`; then a 4th row for Second Teacher) | N/A: staff page is read-only and empty | read-only list shown | not run |
| 1b Set supervisor | PASS (ineligible Grace Mwangi refused with message; Demo Teacher saved, AuditLog written) | **FAIL (UI):** dropdown has no options (cannot read staff records); backend allows it | PASS (Demo Teacher assigned) | N/A |
| 2 Student import: template download, preview, confirm | PASS (template XLSX downloaded; preview 3 create + 1 fail "Unknown class"; confirm 3 created, credentials banner shown) | PASS (preview works; re-upload flags 3 duplicates + 1 unknown class; confirm not repeated) | PASS: correctly refused ("You do not have permission") but the Import button is still shown | not run |
| 3 `/parents` | PASS: Jane Otieno has Amina + Brian (second child reused the parent), Sam Wanjiru has Cate | PASS (list + Edit/Add child/Delete, national ID visible) | PASS read-only, no national ID column | PASS: "You do not have access to parent records." |
| 5 Change supervisor | PASS (Demo Teacher to Second Teacher; audit "A -> B") | not possible in UI (see 1b) | PASS (see 1b) | N/A |
| 6 Transfer a student | PASS via API only (BP-002 Zion to West: history `transferred`, new row active, parent link kept). The UI Transfer button uses `window.prompt` and moves **all** students of the class, so I did not drive it in the browser | not run | not run | not run |
| 6b Deactivate a supervising teacher (Staff) | PASS: refused "Cannot deactivate: supervises Grade 7 Zion. Assign another supervisor first."; after clearing the supervisor the deactivation succeeded | N/A | N/A | N/A |
| Class list XLSX download | PASS (admin: header block, `#/ADMNO/NAME/GENDER`, 3 learners, counts) | not run | not run | PASS (download from My Classes) |
| My Classes shows own classes only | N/A (admin has none) | N/A | N/A | PASS: Demo Grade 7 Demo Seed A and Grade 7 Zion only, with boys/girls/total |

## Issues found (nothing was fixed in the browser pass)
1. **Registrar/Principal supervisor dropdown depends on staff visibility.** Registrar cannot read staff records, so the supervisor list is empty although the API allows the Registrar to set supervisors. Needs either a slim staff-picker endpoint for class managers or the Registrar group added to staff read.
2. **My Classes duplicates a class**: "Demo Grade 7 Demo Seed A" appears twice for the teacher (a `class_teacher` assignment row plus the supervised-class row). `streams/my-classes/` should merge rows with no subject.
3. **Supervisor dropdown does not show the current supervisor** (always reads "Assign supervisor"; the value is `user:<id>` but options are `staff:<n>`). The "Supervisor:" text line is correct.
4. **Unlinked staff are offered as supervisors** (Grace Mwangi has no user account); picking one gives the right error but the option should be disabled.
5. **Transfer button** uses `window.prompt` for a numeric stream id and transfers the whole class; it cannot be tested through the browser tool and is poor UX.
6. **Import button visible to Principal** although the API refuses it (needs the Registrar group); hide with `canEditStudents`.
7. **Literal `&amp;`** in the heading "Form &amp; Stream Overview" and a React console error "`<sectionHeader />` is using incorrect casing" in `Classes.jsx` (pre-existing); dashboard console error "Invalid scale configuration for scale: stacked" (pre-existing).
8. **Staff deactivate error** is shown as "employment_status: Cannot deactivate..." (field name prefix).
9. **Enrollment history is writable** by teachers/staff through `student-class-enrollments` (probe, pre-existing).
10. **Seed data:** Demo School has no staff records and the seeded `principal@`/`registrar@` users are role STAFF (not TEACHER), so they can never supervise; `seed_dev_users` should create staff profiles for `teacher@demo.com`.
11. Not run: Principal and Registrar create/transfer for every step, the Teacher on `/students` and `/staff`, a second import confirm as Registrar, the PDF/other printouts.

---

# Phase 5b: fixes for the browser-pass findings

Commits: backend `f8eb8cf`, frontend `11e6954`, root `f5ace09`. **Full Postgres 16 suite: 724 tests, OK.**

## What changed
1. **Transfer / promote.** `enrollments/reassign_student` now needs an explicit non-empty `student_ids` list, a `stream_id` and a `reason` (the single `student_id` form is gone, so a request without a learner list is a 400). All or nothing: capacity is checked for the whole list, each old history row closes as `transferred`, the new row stores the reason, each move is audited. New `enrollments/promote_class` (`from_stream_id`, `to_stream_id`, `reason`, `confirm_count` must equal the learner count right now) for whole-class moves, history status `promoted`. Both ADMIN + Registrar only. UI: no more `window.prompt`; a per-learner "Transfer" button opens a modal (target class with places taken shown and full classes disabled, reason, confirmation box); "Promote class" opens a modal saying "all N learners". The roster in `Gradebook.jsx` no longer moves a learner on a dropdown change (it was an unconfirmed one-click move); it shows the class as text.
2. **`student-class-enrollments` is read-only for everyone** (403 on create/update/delete, including ADMIN); history is written only by transfer, promote and the student import. `test_write_access.py` lists the route with no writer.
3. **`streams/eligible-supervisors/`** (ADMIN, Principal, Registrar; others 403): active TEACHER users with an active StaffProfile in the caller's school, fields `id`, `name`, `phone` only. The picker uses it, so the Registrar gets a list and staff without an account never appear.
4. **My Classes** returns one row per class with `roles` (class teacher and/or subject teacher) and `subjects`.
5. **Picker shows the current supervisor** (value `teacher:<id>`, with a fallback option if the person is no longer eligible).
6. **Controls hidden** for roles the API refuses: Import (ADMIN/Registrar only) and Register learner (ADMIN only) on Students; Transfer/Promote for ADMIN/Registrar only; class management tabs/buttons already gated.
7. **`api_probe.py`** knows registrar/principal/staff are role STAFF plus groups (`ROLE_ACCOUNT`, `GROUP_WRITES` for Registrar, Principal, Finance, HR, Health); `accounts/test_probe_expectations.py` covers it.
8. **`seed_dev_users`**: StaffProfiles for `teacher@`, `teacher2@` (new TEACHER user) and `staff@` in both schools (idempotent, keyed on the user), default staff groups ensured.

## Tests added or changed
`TransferPromoteTests` (explicit list required, reason, all-or-nothing capacity, scope/access, confirmed count, same class, empty class, history read-only), `EligibleSupervisorsTests`, three My Classes tests (merge, subject-only, class-teacher assignment plus supervisor), `test_probe_expectations` (4), `test_seed_dev_users` (4); `test_students` and `test_learner_scope` updated to the new transfer contract.

## Browser re-run (Chrome, local dev only, seed accounts only)
| Check | Role | Result |
|---|---|---|
| My Classes: one row per class, both roles and subject | Teacher | PASS: "Demo Grade 7 Demo Seed A" once (was twice); "Grade 7 Zion: Class teacher · Subject teacher, English" |
| Supervisor picker lists eligible teachers; shows current supervisor | Registrar | PASS: options "Demo Teacher", "Second Teacher" (no unlinked staff, no inactive); current one is the selected value; changing it worked |
| Supervisor picker shows current supervisor | Admin | PASS ("Second Teacher") |
| Per-learner transfer modal | Registrar | PASS: empty submit refused ("Choose the class to move to."), target list shows "0/1 places taken", reason + confirmation required, learner moved, history row and reason stored, audit written |
| Promote class | Registrar | PASS: modal says "all 4 learners", full class shown "(not enough room)" and disabled, confirm tick required, 4 learners moved (history `promoted`, reason stored) |
| Import / Register hidden | Principal | PASS: no floating buttons on `/students`; no Transfer/Promote on `/classes`; supervisor pickers still shown |
| Transfer/Promote visible | Admin | PASS |

Setup done for the run: re-ran `seed_dev_users`, reactivated the deactivated T-102 staff record, set "Registrar Test" capacity to 1, gave the teacher an English assignment on Zion (shell). Dev data changed by the run: BP-001/BP-003-era Zion learners and the four West learners were moved (Zion now has 4 plus the one in Registrar Test).

## Remaining issues (new, not fixed)
1. **Registrar sees learner ids instead of names** in the class cards ("Transfer #54") because the learner list (`users/?role=STUDENT`) is not available to the Registrar; the modal title then reads "Transfer #54". Class cards should take names from the class-list/overview data.
2. **Stale error in the modal:** after a validation error the red message stays while you fix the form; it clears only on submit.
3. Heading shows a literal `&amp;` ("Form &amp; Stream Overview") and the `<sectionHeader />` React casing console error (pre-existing).
4. Registrar cannot register a single learner (`users` create is ADMIN-only) although they can import and transfer.
5. `Enrollment` (current class) rows can still be written directly by ADMIN through `enrollments/`, bypassing history; only the history route is locked.
6. Class cards say "Supervisor: Demo Teacher2" because the seed gives every user the first name "Demo".
