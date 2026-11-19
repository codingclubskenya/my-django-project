# Learning Pack — System Audit (Phase 1)

- **Date:** 2026-11-12 · **Status:** Baseline audit, no code changed
- **Companion docs:** SECURITY-AUDIT.md, ARCHITECTURE.md, IMPLEMENTATION-ROADMAP.md, TESTING-REPORT.md

## 1. What exists

The parent repo `my-django-project` (branch `master`) pins three submodules plus some loose folders:

| Path | What it is | Branch / state |
|---|---|---|
| `backend/` → `fattym/epk` | Django 6.0.7 + DRF 3.17.1 API, ~35 apps | `qa/hardening-fixes`. **Uncommitted work in 23 files plus 7 untracked migrations** (academics 0005–0008, accounts 0008–0010). |
| `distributor/` → `fattym/disributor` | Next.js 16 / React 19 public storefront, parent shop, distributor portal, **3D supermarket** (R3F/three 0.186) | `main`, 10 modified files |
| `frontend/` → `fattym/frontend-apk-web` | `codingclubskenya/` staff React 19 + Vite app (75 pages/components, 54 routes); `parents/` Flutter app (17 feature folders); `classroomio/` | `codingclubskenya` on `master`, 1 modified file |
| `frontend/classroomio/` | Clone of upstream **ClassroomIO** LMS (SvelteKit monorepo, **AGPL-3.0**). Not referenced by any Learning Pack code. | upstream origin |
| `deploy/`, `nginx/` | systemd units (gunicorn, celery, celery-beat), deploy/update scripts, nginx site | — |
| Root `*.md` | AGENTS.md (original brief), IMPROVEMENT_PLAN.md, IMPLEMENTATION_GUIDE.md, ACADEMIC_STRUCTURE_AUDIT.md | untracked |

> **Before any implementation:** commit or stash the in-progress backend work on `qa/hardening-fixes`. Fixes should go on a new branch so they don't get tangled with it.

## 2. Health baseline (measured)

| Check | Result |
|---|---|
| `manage.py check` (dev settings) | ✅ 0 issues |
| `manage.py check` with **`core.settings_production`** (repo copy) | ❌ **Crashes:** `storefront`, `carts`, `booklists` missing from `INSTALLED_APPS` while `core/urls.py` routes to them. Production must be running a drifted copy of the file (reported: live file is 296 lines vs 225 in repo). |
| `makemigrations --check` | ❌ 2 model changes without migrations: `payroll.LeaveRequest.approved_by`, `procurement.Asset.tag` |
| Unapplied migrations (local SQLite) | none |
| Test suite | **82 passed, 4 failed** (gradebook ×1, website ×3; see TESTING-REPORT.md). 98 test functions exist in total. 23 of the 35 apps with models have **zero** tests, including fees, exams, transport, recruitment and courses. |
| OpenAPI generation | ✅ 434 unique paths. 2 views have no serializer (`website.PublicWebsiteView`, `transport.DriverStudentsView`). dj-rest-auth registration views are broken (no `username` field). |
| `backend/venv/bin/activate` | Broken in this shell (`python` not on PATH after activate). Calling `venv/bin/python3` directly works. AGENTS.md §C instructions need updating. |
| Database | Dev: SQLite. Prod: PostgreSQL 16 *(reported)*. |

## 3. Feature status vs the brief

Legend: ✅ complete & usable · 🟡 partial · ❌ missing · ⚠️ exists but broken/unsafe

### A. School management
| Feature | Status | Evidence / gap |
|---|---|---|
| School registration & onboarding | 🟡 | `tenants.School/SchoolSettings` + admin. No self-service onboarding wizard, no readiness checklist. `SchoolSettings.currency` defaults to USD. |
| Academic years / terms | 🟡 | `academics.Term` is tenant-scoped, but the academic year is a **string** in `Term`, `Stream` and `SchoolSettings`. A separate global `booklists.AcademicYear` also exists. No unified tenant-scoped AcademicYear. |
| Grades / streams / pathways | 🟡 | `Grade`, `Stream`, `Pathway`, `EducationLevel`, curriculum versions (0007, uncommitted). No Track/SubjectCombination (see ACADEMIC_STRUCTURE_AUDIT.md). |
| CBC learning areas | ✅/🟡 | `LearningArea→Strand→SubStrand→LearningOutcome→RubricDescriptor` plus curriculum overrides. Data seeding is still manual. |
| Student admission + bulk Excel import | 🟡⚠️ | `UserViewSet.bulk_import` takes JSON rows (Excel is parsed client-side with `xlsx`). There's no server-side preview/dry-run, duplicate detection is basic, and it sets the **default password `Pass@1234`** (SEC H3). |
| Promotion & transfers | 🟡 | `Enrollment.reassign_student` exists. No promotion run and no enrolment history. |
| Parent/guardian registration | 🟡 | `ParentLearner` many-to-many, auto-created by import. No verified invitation flow. |
| Staff registration | 🟡 | `accounts.StaffProfile` **and** a duplicate `payroll.StaffProfile`. |
| School-specific roles & permissions | ❌ | Fixed `User.role` enum (ADMIN, TEACHER, STUDENT, PARENT, STAFF, DRIVER, DISTRIBUTOR). django-guardian is installed but unused. No custom roles per school. |
| Secure login | ⚠️ | JWT plus a student-login endpoint. Privilege escalation is possible (SEC C4). |
| Timetables / attendance / reporting | 🟡 | Timetable endpoints are in academics. The attendance app has records, summaries and notifications. `reports` has 14 endpoints. Attendance has 0 tests. |

### B. Parent portal & booklists
| Feature | Status | Evidence / gap |
|---|---|---|
| Multi-child parents | ✅ | `ParentLearner`, Flutter `activeLearner` switching |
| Booklists | 🟡 | **Two overlapping models:** `booklists.Booklist/BooklistItem` (school-published lists) and `requirements.RequiredItem/RequiredItemOption`. They need consolidating. |
| **Parent uploads booklist (PDF/Excel/Word/image)** | ❌ | No upload model or endpoint. |
| **AI/OCR extraction + catalogue matching** | ❌ | Not built. Distributor UI has `upload-my-list` and `find-my-school-list` pages; check what backend they call before building. |
| Review/correct → cart → order | 🟡 | Cart (`carts`) and orders (`shop`) exist. Guest carts can't write (SEC M9). |
| Order tracking / payments / notifications | ⚠️ | Tracking page exists. **Payment confirmation is client-driven and forgeable** (SEC C1–C3). Notifications depend on Celery, which is reported not running in prod. |

### C. Course Studio (Classroom-style)
| Feature | Status | Evidence |
|---|---|---|
| Courses, topics, lessons, materials, enrolment | 🟡 | `courses` app: 14 models, 41 endpoints. `CourseStudio.jsx`, `CourseFlow.jsx`. **0 tests.** |
| Assignments & submissions | 🟡 | `courses.Assignment/Submission` **and** `academics.Assignment` **and** the `homework` app: three overlapping concepts. |
| Quizzes | 🟡 | `Quiz/QuizQuestion/QuizAttempt` |
| Announcements / stream | 🟡 | `courses.Post/PostComment` plus `messaging.Announcement` plus `notices`: overlapping |
| Progress & analytics | 🟡 | `LessonProgress`. No analytics endpoints. |

### D. Examination management
| Feature | Status | Gap |
|---|---|---|
| Exams, grades, report cards | 🟡 | `exams.Exam/ExamGrade/ReportCard`, `gradebook` (CBC report card), CBC report card view |
| Question bank / question types / paper builder | ❌ | No Question, QuestionBank or Paper models (quiz questions live only in `courses`) |
| Auto-marking / teacher marking queue | ❌ | — |
| Exam schedules | 🟡 | `Exam` has dates. No timetable or invigilation. |
| Results analysis | 🟡 | reports app. No publication/approval workflow (PRD §7.3). |
| CBC competency assessment | ✅/🟡 | `assessment` + `gradebook` (two models of competency scores; reconcile) |

### E. AI & H5P
| Feature | Status | Evidence |
|---|---|---|
| AI client | 🟡 | `ai/client.py`: Anthropic SDK or OpenAI-compatible URL. Default model id is retired. No key configured, so it falls back to keyword stubs. |
| Parent chatbot, report narratives, resume screen, interview Qs, moderation, at-risk flags | 🟡 | Endpoints exist. They mostly return stubs without a key. Permissions are too broad (SEC H5). |
| Lesson prep / question generation / revision / recommendations / marking assist | ❌ (`AITeacherAssist.jsx` is a UI shell) | — |
| AI suggestion audit log | 🟡 | `audit` tests reference an `ai_suggestion` action |
| H5P | ❌ | Nothing. |

### F. Finance
| Feature | Status | Gap |
|---|---|---|
| Fee structures, invoices, payments | 🟡 | `fees` (3 models, 9 endpoints, **0 tests**). Payments are editable/deletable (SEC M2). |
| Receipts, ledger, credits/adjustments, reversals | ❌ | — |
| M-Pesa | ⚠️ | Through the **ChamaGO** aggregator (`shop/services/mpesa.py`), shop orders only. No STK status query. Webhook is unauthenticated. `MPESA_*` Daraja settings are unused. |
| Bank reconciliation, expenditure, financial reports, settings | ❌ | — |
| Shop "charge to fee balance" | 🟡 | `OrderViewSet.pay_fee_balance` |

### G. Transport
| Feature | Status | Gap |
|---|---|---|
| Routes, stops, buses, student assignment, driver login, live location | 🟡 | `transport` (4 models, 12 endpoints, 0 tests), `BusMap.jsx`, `DriverMap.jsx`, Leaflet |
| Driver/attendant profiles, trips & trip attendance, maintenance, fuel/expenses, billing, parent notifications | ❌ | — |

### H. Staff management
| Feature | Status | Gap |
|---|---|---|
| Profiles, leave, payslips | 🟡 | `accounts.StaffProfile`, `accounts.TeacherLeave` **and** `payroll.StaffProfile/LeaveType/LeaveRequest/Payslip`: duplicated |
| Departments/designations, staff documents, staff attendance, work allocation, activation/deactivation flow | ❌/🟡 | — |
| Recruitment ATS | 🟡 | 7 models, 19 endpoints, 0 tests. Public application form; validation unverified (SEC H2). |

### Other modules present (beyond the brief)
library, clubs, complaints, events, notices, health, discipline, alumni, parent_meetings, procurement (6 models, tests), website (public school sites), discovery (shoppable videos), storefront (3D shelf mapping), distributor (wallets, school orders, deliveries).

### 3D supermarket
- **Two implementations:**
  - `distributor/components/supermarket/` (in-app, ~3.4k LOC TSX: character, trolley, shelves, 2D fallback `Supermarket2D.tsx`, mobile controls)
  - `distributor/components/learning-pack-3d/` (separate Vite app, ~760 LOC, own `node_modules` and a stray `db.sqlite3`)
- Only **1** binary asset in `public/` (484 KB total), so products are procedural geometry. No GLB/KTX2 pipeline, LOD or instancing is evident (no `Instances`/`Detailed` usage).
- Backend `storefront.ShelfSection/ProductModelMapping` maps products to shelves.

### Storage, performance, automation, mobile
| Area | Status |
|---|---|
| Cloudflare R2 / signed URLs | ❌ Local `MEDIA_ROOT`, publicly served (SEC H1) |
| Redis cache | ⚠️ Configured in live prod but `django_redis` was reported missing; it's now in requirements |
| Celery | ⚠️ Units exist in `deploy/`; reported not running in prod |
| Monitoring | ❌ `sentry-sdk` in requirements, not confirmed wired |
| Backups | ❌ No script or restore test in repo |
| n8n | ❌ Not present (Phase 7 is an evaluation item) |
| Flutter APK | 🟡 17 feature folders. API base hard-coded to `https://codingclubskenya.com/api`. Release signed with debug key. No offline cache found. Not built or run in this audit. |

## 4. Duplication & architectural weaknesses

| # | Issue | Recommendation |
|---|---|---|
| D1 | Staff: `accounts.StaffProfile` vs `payroll.StaffProfile`; leave: `accounts.TeacherLeave` vs `payroll.LeaveRequest` | Keep `accounts.StaffProfile` as the master. Make payroll reference it, and migrate the data. |
| D2 | Booklists: `booklists.*` vs `requirements.*` | Choose one (likely `booklists`, which has publish/archive and academic year), migrate the other, and point parent uploads at it. |
| D3 | Assignments: `courses.Assignment`, `academics.Assignment`, `homework` | Converge on `courses`, the Classroom model. |
| D4 | Announcements: `messaging.Announcement`, `notices`, `courses.Post` | Keep class stream (`Post`) separate. Merge notices into messaging. |
| D5 | Competency scores: `assessment.CompetencyAssessment` vs `gradebook.LearningAreaScore/StudentCompetencyScore` | Document which is authoritative for report cards. |
| D6 | Payments: `shop.Payment` vs `fees.Payment`, no shared ledger | Introduce a finance ledger that both post to. |
| D7 | Two 3D supermarket codebases | Keep the in-app `components/supermarket` (wired to cart/booklists). Archive `learning-pack-3d` after porting anything useful. |
| D8 | Four copies of `SchoolScopedViewSetMixin` | One `core/tenancy.py` mixin plus a related-field validator |
| D9 | API mounted at both `/api/` and `/api/v1/` | Keep both for now, since clients use `/api/`. Deprecate `/api/` after the Flutter and web clients move. |
| D10 | Academic year as a string in 3+ places; global `booklists.AcademicYear` | Tenant-scoped `academics.AcademicYear` with FKs |
| D11 | `settings.py` vs `settings_production.py` drift, and the live prod file differs again | One settings package (`base/dev/prod`) driven by env. Commit the live prod deltas. |
| D12 | Repo clutter: `venv` + `venv_new`, `requirements_fixed*.txt`, `*.orig`, `*.backup`, `db.sqlite3` files in several places, `celerybeat-schedule` | Clean up in a dedicated PR (after confirming nothing references them). |
| D13 | `User.school` is a single FK, so there are no multi-school memberships (ARCHITECTURE.md §5 asks for memberships) | Defer. That's a product decision. |
| D14 | ClassroomIO vendored but unused, and AGPL | Decide: use it as inspiration only (recommended), or run it as a separate AGPL service. Don't copy its code into the proprietary apps. |

## 5. Things I did not verify

- Live production server state: I relied on the October report.
- UI screens: no app was run or screenshotted.
- Flutter build and runtime behaviour.
- Query performance (no profiling data); test runtime suggests heavy per-test setup.
- What the `upload-my-list` / `find-my-school-list` storefront pages currently call.
