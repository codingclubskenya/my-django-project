# Exams and printouts plan (later release, draft)

Status: proposal only. Not in the school-data-management scope. Basis: `reports/benchmark-gap.md`. Our own UI and wording; the benchmark only informs which capabilities exist.

## 1. Goal
Let a school run a term exam end to end: set up grading and paper weights, create an exam for a grade, enter marks, review, release to parents, withdraw if wrong, and print the standard school documents. Works for CBE and 8-4-4 schools.

## 2. Today (summary)
`exams.Exam` is one row per stream + learning area (one paper, no term/year, no status). `ExamGrade` stores marks with a fixed 8-step letter grade. `ReportCard` is a stored per-term total. `gradebook` and `assessment` handle CBC competencies and formative tasks. No release state, no grading scheme model, no paper weights, no PDF/print output, no parent results delivery.

## 3. Design

### 3.1 Exam lifecycle
New `ExamSitting` (one per school + grade + term + year + name + type), separate from the existing per-subject `Exam` rows, which become its subject papers (link by FK, migrate old rows into a legacy sitting).

States: `draft` (no marks) → `marks_entered` → `pending_release` → `released` → back to `pending_release` via withdraw.
- Marks upload moves `draft` to `marks_entered`; Registrar/Principal "Submit for release" moves to `pending_release`; "Release" makes results visible to parents/students and enables sending.
- Withdraw requires a reason, writes `AuditLog`, hides results again. Delete is soft (bin), blocked once released.
- Transitions are server-side only; every transition scoped to school; `AuditLog` entry with before/after.
- Permissions: Teacher enters marks for own subject classes only; Registrar/Principal submit, release, withdraw.

Exam types: written test, consolidated exam, national mock, supplementary, year average.

### 3.2 Grading systems
`GradingScheme` (school, name, kind: `CBE` | `EIGHT_FOUR_FOUR`, is_default) with `GradeBand` rows (min, max, label, points, comment). Seed two system defaults (CBE four-level bands with sub-levels; 8-4-4 A to E with points); schools may copy and edit. An exam sitting picks one scheme; letter grades are computed at read time or cached per result, never typed. Replaces the fixed `ExamGrade.GRADE_CHOICES`.

### 3.3 Subject paper ratios
`SubjectPaper` (school, learning area, name, out_of, weight). Subject score = sum(mark/out_of * weight) / sum(weights) * 100, rounded once at the end. Per sitting, "enabled papers" decide which subjects and papers are sat. Edge rules: absent vs zero distinguished; missing paper blocks release with a clear list.

### 3.4 Marks entry and review
Per subject class grid (teacher) and CSV/XLSX import via `core/imports.py` (dry-run, limits, formula escaping). Review screens: completeness by subject, subject means, class and stream ranking, grade distribution.

### 3.5 Send results to parents
Decided: in-app plus email now, no SMS now. Sending goes through a `ResultNotifier` interface (`send(guardian, learner, sitting, message) -> DeliveryResult`) with two implementations, `InAppNotifier` (existing `messaging.Notification`) and `EmailNotifier`, selected by a per-school channel list. An SMS provider (e.g. Africa's Talking) is added later as a third implementation behind the same interface, with credits/opt-out designed then; nothing SMS-specific is built now. A `ResultDelivery` row records learner, guardian, channel, status, timestamp so resend stays idempotent. Only guardians linked via `ParentLearner` receive it, school-scoped, one message per learner per release, resend is idempotent and logged. Parents see released results in `ParentReportCards`.

### 3.6 Printouts centre
One "Printouts" page; each item takes class/stream/term/year filters and returns a PDF (server-rendered, private file, signed link via `core/private_files.py`).

| Printout | Source | Notes |
|---|---|---|
| Class list | enrollments | Basic or custom columns; XLSX in school-data Phase 5, PDF here |
| Score sheet | sitting marks | Per subject class, blank or filled |
| Analysis report | sitting | Means, distribution, subject ranking |
| Report forms | sitting + attendance + remarks | CBE and 8-4-4 layouts; class teacher and principal remarks |
| Merit list | sitting | Ties handled by rule, shown on page |
| Transcripts | all released sittings | Per learner, multi-year |
| Attendance report | attendance | Reuse existing summaries |
| Leaving certificate | learner + enrollment history | Registrar/Principal only, numbered, audit logged |
| House/dorm list | needs house data | Skip until houses exist |

PDF stack: WeasyPrint (decided). XLSX via `openpyxl` (already installed) comes first for tabular printouts (class list, score sheet, merit list, analysis); PDF is used where layout matters (report forms, transcripts, leaving certificate). Not installed yet; add `weasyprint` to `requirements.txt` only when this release starts.

System packages WeasyPrint needs on Ubuntu 24.04 (dev and prod; prod install needs your explicit go-ahead and a backup first):
`sudo apt install libpango-1.0-0 libpangoft2-1.0-0 libharfbuzz-subset0 fonts-dejavu-core` (Pango pulls in Cairo/GDK-Pixbuf as needed; add `shared-mime-info` and `libffi-dev` if the wheel build asks). Verify with `python -c "import weasyprint; weasyprint.HTML(string='<p>x</p>').write_pdf('/dev/null')"` using `venv_new/bin/python`. Confirm the exact package list against the WeasyPrint docs for the pinned version before installing.

### 3.7 Security and tenancy
All querysets school-scoped; parents see only their linked children and only `released` sittings; leaving certificates and transcripts restricted by role and audited; exports escape formula-leading cells; PDFs served through signed private links.

## 4. Phases
1. Models and migrations: `ExamSitting`, `GradingScheme`/`GradeBand`, `SubjectPaper`; data migration for legacy rows. Tests: calculation, tenancy, migration.
2. Lifecycle API and audit; marks entry and import. Tests: every transition, permissions, withdraw.
3. Frontend: Exams tabs (Assessments, Manage, Create, Grading, Paper ratios), review screens.
4. Release and send to parents; parent view.
5. Printouts centre (class list, score sheet, report forms, merit list first; transcripts and leaving certificate last).
6. Hardening, docs, local click-through with seed accounts.

## 5. Open decisions
- (Resolved) In-app + email now behind `ResultNotifier`; SMS later. PDF: WeasyPrint.
- Keep legacy `Exam`/`ExamGrade` API during migration, or cut over at once?
- Rounding and tie-break rules for merit lists (needs school input).
- Do formative (CBE) results share the sitting model, or stay in `assessment`?
