# School data management: implementation notes

Branch `feat/school-data-management` (backend, frontend, root docs). Plan: `school-data-management-plan.md`. Per-phase detail: `reports/phase-1.md` to `phase-6.md`. Database: `DATABASE-CHANGES.md`.

## Who can do what
| Action | ADMIN | Registrar | Principal | Teacher | Other staff / parent / student |
|---|---|---|---|---|---|
| Read learners and parents (school-scoped, slim record) | yes | yes | yes | yes (school) | self / linked only |
| Register one learner (role STUDENT only), import students, transfer, promote | yes | yes | no | no | no |
| Edit or delete a user | yes | no | no | no | no |
| Create / update / archive class, set subjects, set supervisor | yes | yes | yes | no | no |
| Delete a class | yes | no | no | no | no |
| Class list (XLSX/CSV) | any class | any class | any class | own classes | no |
| Direct writes to `enrollments/` or `student-class-enrollments/` | no one | no one | no one | no one | no one |
Staff import and records: ADMIN and HR group. Parent import and records: ADMIN and Registrar (Principal reads).

## Rules worth knowing
- A learner's class changes only through register (optional class), student import, `enrollments/reassign_student/` (explicit `student_ids`, target, reason, all-or-nothing capacity) and `enrollments/promote_class/` (whole class, confirmed learner count). Each writes `Enrollment` plus a `StudentClassEnrollment` history row and an audit row. History rows are read-only through the API and scoped for parents and students.
- One primary supervisor per class (partial unique constraint). Supervisors must be active teachers with an active staff record in the same school; changes are audited. A supervising teacher's staff record cannot be deactivated or deleted until another supervisor is set.
- Admission numbers are unique per school, case-insensitive; blanks are stored as NULL.
- Imports preview by default; `confirm=true` saves, with a report row (`BulkImportLog`) and audit row. Exports and templates neutralise cells starting with `=`, `+`, `-`, `@`.
- Parents imported with a student are matched by national id, then phone, then email (a phone or email match with a different national id is a row error, never merged silently); a second child reuses the parent. Imported parents activate through the normal password-reset flow.

## Operations
Release order and rollback: `DATABASE-CHANGES.md` (Release 2). Tests: `manage.py test` on Postgres 16 (SQLite fails 3 `repair_sites_history` tests that use Postgres-only SQL). Dev checks: `seed_dev_users`, `scripts/api_probe.py`.
