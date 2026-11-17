# Benchmark gap analysis

Source: `docs/specs/benchmark-school-system.md`. Graph: 6371 nodes (≥3000). Code checked via graphify queries plus targeted `rg`.

## 1. Classes
| Benchmark feature | Ours | Gap |
|---|---|---|
| Grade → stream → subject class | `Grade`, `Stream` (capacity), `TeacherAssignment` (teacher + stream + learning area + term, role), `ClassTeacher` (primary flag) | Model exists. |
| My Classes (teacher's subject classes) | `TeacherAssignment` data, `TeacherAssignments.jsx`, `Classes.jsx` | No teacher-facing "My Classes" view with class-list action. |
| Manage Classes: boys/girls/total | `Stream.capacity`, `User.gender` | No gender counts. |
| Class supervisor dropdown | `ClassTeacher.is_primary`; plan Phase 5 `assign_supervisor` | Planned. |
| Class list printout (Basic/Custom, print/download) | none; `openpyxl` present, no PDF lib | Missing. |
| Add Class with subject multi-select by group | `CurriculumSubject` (grade level), `StreamSubjectOverride` (audited), `LearnerSubjectSelection`, `SubjectCombination`, `LearningArea.subject_type` | Backend richer than benchmark; no "subjects on Add Class" UI. |
| Graduated classes | `StudentPromotion`, `SchoolAcademicYear` | No listing. |
| BOM/PA, Staff, Teachers directories | `StaffProfile`/groups (plan Phase 2) | BOM/PA group not seeded. |

## 2. Exams
| Benchmark feature | Ours | Gap |
|---|---|---|
| Exam per grade/term/year with type | `Exam` is per stream + learning area, one paper, no term/year; 4 types | Missing sitting model; types differ. |
| Status lifecycle (not uploaded → pending → released → withdraw) | none (`assessment` has "published task" only) | Missing. |
| Grading systems (CBE, 8-4-4) | fixed `ExamGrade.GRADE_CHOICES` (A+..F) | Missing scheme/bands. |
| Subject paper ratios | none | Missing. |
| Enable subject papers per exam | none | Missing. |
| Upload results | `ExamGradeViewSet.bulk_enter`; `BulkAssessment.jsx`; `core/imports.py` | Partial. |
| Analyze results | `Exam.result_summary`, `toppers` | Partial. |
| Continuous assessment / school-based | `assessment` (`AssessmentTask`, results, competency), `Assessments.jsx`, `gradebook` | Covered for CBE formative. |
| Send results to parents | `ParentReportCards.jsx`, `messaging`; no release gate or send action | Missing. |
| Deleted exams bin | none | Missing. |
| Report card | `ReportCard`, `CBCReportCardView` (JSON), `Gradebook` ReportsTab | No PDF/print layout. |

## 3. Other pages
| Benchmark | Ours | Gap |
|---|---|---|
| Printouts centre | none | Missing (see exams plan). |
| Timetable dashboard | `Timetable*` models and page, `Attendance*` | No compliance/workload dashboard. |
| Attendance per subject class | `AttendanceRecord`, `Attendance.jsx` | Covered. |
| Messages | `messaging` (conversations, announcements) | Covered; no opt-out control seen. |
| Student search by NEMIS/UPI | `Students.jsx` | Not verified. |
| SMS credits | not found in code (only email/SMS comments in accounts) | Out of scope. |
| House list | no house model | Missing. |
| Billing/Finance/Opportunities/Calendar | `fees`, `Events.jsx` | Not compared. |

## 4. Proposals
### (a) Additions to school-data plan (small)
- Phase 4: students endpoint returns gender counts per class; class-list data endpoint (admission no, name, gender) used by Phase 5 printout.
- Phase 5: "My Classes" teacher view over `TeacherAssignment`; boys/girls/total on class detail; subjects selector on Add Class writing `CurriculumSubject`/overrides through existing audited paths; class-list printout (Basic and Custom columns; XLSX via `openpyxl` first, PDF only if a lib is approved).
- Phase 2: seed a BOM/PA `StaffGroup` (sixth default) with directory view. Check Phase 2 progress first; it may already be committed.
- Phase 6: add the above to scenarios and regression list.
Risks: class list exposes learner data, so school-scope and teacher-own-classes only; gender counts must be school-scoped.

### (b) New release
`docs/specs/exams-printouts-plan.md`.

## 5. Not done
No code changed. Plan Phase 4–6 text not edited (proposals only, awaiting approval). Notes file moved to `docs/specs/`.
