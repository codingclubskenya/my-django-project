# Academic Structure, Curriculum & Class Management — Audit Report

**Date:** 2026-11-11  
**Scope:** Kenyan CBE module (education levels, grades, curriculum, subjects, pathways/tracks/combinations, classes/streams, learner progression) and integration with `/classes`, `/students`, `/parents`, `/staff`.

## 1. Existing architecture (reused, not duplicated)

### Tenancy, auth, RBAC
- Multi-tenant: `tenants.School` is tenant root; most academic/account records carry `school` FK. APIs generally scope by `request.user.school` via mixins/custom querysets.
- Auth: JWT (`rest_framework_simplejwt`), `accounts.CustomTokenObtainPairView` / student login. Roles on `accounts.User`: `ADMIN, TEACHER, STUDENT, PARENT, STAFF, DRIVER, DISTRIBUTOR`.
- Permissions: `IsAdminOrReadOnly`, `IsAdminOrStaffOrTeacher` in `accounts.permissions`; school scoping enforced in viewsets (must be verified per new endpoint).

### Existing domain models (key)
| Area | Models (app) | Notes |
|---|---|---|
| Grades/levels | `academics.Grade` (`stage`: pre_primary/primary/junior_secondary/senior_secondary, `order`) | Acts as grade master; **no separate EducationLevel model** yet. |
| Pathways | `academics.Pathway` | Exists; **no Track, no SubjectCombination**. |
| Classes/streams | `academics.Stream` (`name, code, grade, pathway, school, academic_year, capacity, status`) | Unique `(school, grade, name)`; recently enhanced with code/year/capacity/status. |
| Subjects/learning areas | `academics.LearningArea` (`name, code, grade, pathway, school`) + `Strand/SubStrand/LearningOutcome/RubricDescriptor` | Grade-linked; **no master subject catalogue independent of grade, no grade-subject assignment table** (CurriculumSubject added in 0007). |
| Curriculum (new, partial) | `academics.CurriculumVersion, CurriculumSubject, StreamSubjectOverride(+Audit), LearnerSubjectSelection, LearnerPathwaySelection` (migration 0007) | Grade-level versioned config, inheritance/override/effective-subject API, learner selections; **not yet mapped to full 14-form spec** (no education-level entity, no tracks/combinations, no subject master, no promotion). |
| Curriculum docs | `curriculum.SchemeOfWork/SchemeWeek/ReferenceDocument` | Planning docs tied to learning areas/terms/streams. |
| Academic time | `academics.Term` (`name,start/end,academic_year,is_current,school`), `academics.Stream.academic_year` (char), `booklists.AcademicYear` (`name,start/end,is_current`, global-ish) | **No unified tenant-scoped AcademicYear model in academics**; year represented as strings in many places. |
| Enrollment/allocation | `academics.Enrollment` (`student, stream, school, enrollment_date, is_active`) unique `(student, stream)` | Current allocation; **no enrollment history/promotion records**. |
| Staffing | `academics.TeacherAssignment`, `academics.ClassTeacher`, `accounts.StaffProfile` (employee directory), `accounts.TeacherProfile`, `accounts.User` | Supervisors/teachers linkable; assignment history basic (`is_active`, term). |
| Students/parents | `accounts.User(STUDENT/PARENT)`, `accounts.StudentProfile`, `accounts.ParentLearner` | Bulk import creates/matches parents & links learners. |

### Existing frontend pages/routes (relevant)
- `/classes` → `Classes.jsx`: stream/class CRUD UI (grade/name/code/year/capacity/status/pathway), supervisor selection, stream drill-down, bulk import, basic transfer.
- `/learning-areas` → `LearningAreas.jsx`: recently rebuilt for CBC curriculum config (versions/subjects, overrides, learner selection, strands).
- `/enrollments` → `Enrollments.jsx`: simple enrollment form/list.
- `/teacher-assignments` → `TeacherAssignments.jsx`: ResourceManager CRUD for `TeacherAssignment`.
- `/students`, `/parents`, `/staff` enhanced for import/linking/staff directory.
- Navigation in `Layout.jsx` grouped (Academics includes Classes, Learning Areas, Teacher Assignments, Enrollments, Staff, Teachers, Students, etc.).

### Existing APIs (academics, key)
`/api/academics/grades|pathways|streams|learning-areas|strands|sub-strands|learning-outcomes|rubric-descriptors|teacher-assignments|class-teachers|enrollments|terms|timetable*|assignments|learner-groups|curriculum-versions|curriculum-subjects|stream-subject-overrides|learner-subject-selections|learner-pathway-selections/` plus stream actions `bulk_import`, `summary`, `effective-subjects`, enrollment `reassign_student`.

## 2. Implemented / partially implemented vs spec (14 forms)
| # | Form/Workflow | Status | Gap |
|---|---|---|---|
| 1 | Education Level Registration | Partial | `Grade.stage` encodes levels; no configurable `EducationLevel` entity/CRUD/UI. |
| 2 | Grade Registration | Partial | `Grade` CRUD exists; missing codes, level FK relation UI, richer validation/views. |
| 3 | Curriculum Configuration | Partial | `CurriculumVersion` + subjects versioned by year; needs alignment to spec fields (code, dates, status draft/active/archived), education-level/grade linkage UI, history UX. |
| 4 | Subject Registration (master) | Partial | `LearningArea` is grade-scoped; no true master subject catalogue with applicability across grades/levels/types/categories/versions. |
| 5 | Grade Subject Assignment | Partial | `CurriculumSubject`/version + inheritance implemented; needs spec UI (grouped, compulsory/optional, preview) and mapping to master subjects. |
| 6 | Pathway Registration | Partial | `Pathway` CRUD exists; missing Senior-School-only scoping, codes/descriptions/grade applicability/learning-area links as per spec. |
| 7 | Track Registration | Missing | No `Track` model/API/UI. |
| 8 | Subject Combination Registration | Missing | No `SubjectCombination` model/API/UI. |
| 9 | Add Class / Register Stream | Partial | Create stream with code/year/capacity/status/pathway/supervisor selection exists; needs full spec sections, inherited curriculum preview, Senior School conditional config, unique class code scoping per year, save-and-add-another, clean UX. |
| 10 | Stream Curriculum Override | Partial | `StreamSubjectOverride` + audit + effective-subjects exist; needs spec workflow/approval fields & UX. |
| 11 | Individual Learner Subject Selection | Partial | `LearnerSubjectSelection/PathwaySelection` + sync exist; needs full form/workflow, combination validation, approval, history UI, per-student capture. |
| 12 | Subject Teacher Assignment | Partial | `TeacherAssignment` exists; needs spec UX/validation (teaching staff only, conflicts, history, date range) integrated with `/staff`. |
| 13 | Bulk Import Streams | Partial | `streams/bulk_import` + UI exist; needs spec template/columns, validation/preview/report, supervisor by employee number, auto-curriculum association guarantees. |
| 14 | Promotion & Graduation | Missing | No promotion/graduation models, workflow, history, UI. |

### Integration gaps
- `/classes` dashboard not yet the 4-section hub with required summary cards/nav/filters/actions.
- Student allocation/promotions/history not fully connected; student bulk import enhanced but not full spec workflow.
- Supervisor/teacher eligibility enforced partially in UI; backend role/staff validation and deactivation handling need hardening.
- `booklists.AcademicYear` vs academics year strings: need unified/compatible academic-year handling.

## 3. Risks/constraints
- Avoid breaking existing `LearningArea`-based references (gradebook, courses, curriculum schemes, assessments, timetable, assignments) — **backward compatibility required**.
- Migrations must be safe/additive for production-like data; prefer nullable/new tables and data backfills.
- Multi-tenant isolation and permission checks required on all new endpoints/actions.
- Do not duplicate models/routes; extend existing ones where sensible.

## 4. Implementation approach (this pass)
1. Add/extend models (additive): EducationLevel, Track, SubjectCombination, AcademicYear (academics, tenant-scoped or compatible), student class enrollment history & promotions, bulk import logs; enhance Grade/Stream/LearningArea/Pathway relations as needed with safe defaults.
2. Expose serializers/viewsets/actions/URLs with school scoping and permissions.
3. Build connected frontend hub (`/classes` as dashboard) + dedicated forms/pages for the 14 workflows (separate screens/modals/steps), reusing `ResourceManager` and existing pages where appropriate.
4. Integrate: grade→streams curriculum inheritance, stream effective subjects, teacher/supervisor from staff, student enrollment/promotion history, Senior School learner selections.
5. Migrate, check, lint/build, and run end-to-end API workflow smoke tests with test data.

## 5. Outstanding after this pass
- Full parity with every field/validation/edge case in the 14-form spec and KICD rule validation data may require iterative refinement.
- Any data seeding of official KICD structures is configuration, not hardcoded assumptions.
