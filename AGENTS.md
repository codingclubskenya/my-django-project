# School Management System — Full Project Brief (AI Agent Context Document)

> **Purpose of this document:** This is the complete context brief for any AI coding agent (e.g. Claude Code) picking up development on this project. It captures the confirmed architecture, all designed modules, proposed agentic/AI features, and the future roadmap. Read this in full before generating code — it reflects real decisions made during design, not assumptions to re-derive.

---

## 1. Product Summary

A multi-tenant (multi-school) SaaS school management system for the Kenyan market, built around the CBC (Competency-Based Curriculum) academic model. Two client apps share one backend: a React web app for school staff, and a Flutter mobile app for parents.

---

## 2. Core Architecture Decisions (Confirmed)

| Decision | Choice | Reasoning |
|---|---|---|
| Multi-tenancy model | Shared database, shared schema, `school_id` FK on every tenant-scoped table | Faster to build/host than schema-per-tenant; migrate a specific large tenant to isolation later only if needed |
| Backend framework | Django + Django REST Framework | Mature, batteries-included, strong admin tooling |
| Frontend-backend contract | REST (not GraphQL) | Simpler mental model, pairs well with DRF + typed client generation |
| Database | PostgreSQL | JSONField support, proper indexing, matches production from day one |
| Auth | JWT via `djangorestframework-simplejwt` | Stateless, works cleanly across web + mobile clients |
| Async tasks | Celery + Redis | Notifications, PDF generation, fee reminders, M-Pesa callback processing |
| API docs | `drf-spectacular` (OpenAPI) | Enables typed client generation for both React and Flutter |
| Web frontend | React + Vite + TanStack Query + Zustand/Redux Toolkit + Tailwind + shadcn/ui | Staff/admin-facing: attendance, grading, schemes, order desk, recruitment pipeline |
| Mobile frontend | Flutter + Riverpod + `dio` + `flutter_secure_storage` + `firebase_messaging` + `go_router` | Parent-facing only: announcements, shop, child progress, payments |
| Payments | M-Pesa (Safaricom Daraja STK Push) + optional charge-to-fee-balance | Dominant payment method in Kenya |

**Django apps:** `tenants`, `accounts`, `academics`, `attendance`, `exams`, `fees`, `library`, `messaging`, `shop`, `recruitment`

---

## 3. Designed Modules (Data Models Confirmed)

### 3.1 Accounts & Tenancy
- Custom `User` model with `role` field (admin, teacher, parent, staff) from day one — not retrofitted
- `School` model as the tenant root; every tenant-scoped model FKs to it directly or indirectly
- `Parent` ↔ `Learner` is many-to-many (multi-child households; a learner could theoretically span schools in edge cases)

### 3.2 CBC Academic Model
Reflects Kenya's 2-6-3-3-3 structure (current as of 2026: Senior Secondary, Grades 10–12, is now live).

- `EducationLevel` (PP1/PP2, Grade 1–6, Grade 7–9, Grade 10–12)
- `Pathway` (STEM, Social Sciences, Arts & Sports, Vocational — Grade 10+ only)
- `LearningArea → Strand → SubStrand → LearningOutcome` (mirrors official KICD curriculum design structure)
- `RubricDescriptor` — 4 competency levels per outcome: BE (Below Expectation), AE (Approaching Expectation), ME (Meeting Expectation), EE (Exceeding Expectation)
- `CompetencyAssessment` — learner's rubric level per outcome per term (not a percentage)
- `LearnerPortfolio` — cross-term/year rollup, never reset

### 3.3 Scheme of Work
- `ReferenceDocument` — official KICD curriculum design PDFs (public source, not scraped from paid third-party sites)
- `SchemeOfWork` + `SchemeWeek` — auto-generated draft (strands/sub-strands distributed across the term's teaching weeks), teacher-editable, exportable to Word/PDF
- **Known bottleneck:** seeding strand/sub-strand/outcome data per grade/subject/term is a data-entry job, not an engineering one

### 3.4 School Shop (E-commerce)
- `ProductCategory`, `Product`, `ProductVariant` (e.g. uniform sizes), tenant-scoped
- `Order`, `OrderItem` — tied to parent AND specific child; pickup-only fulfillment via short `pickup_code`
- `Payment` — M-Pesa STK Push or `fee_balance` (debits the existing fee ledger directly, unifying tuition + shop into one balance)
- `Announcement.featured_products` (M2M) — shoppable product cards inline in announcements

### 3.5 Recruitment (Full ATS)
- `PipelineStage` (school-customizable), `JobPosting` (public careers page, no login), `Candidate` + `Application` (deduplicated by email, no account required)
- `Interview` + `ScoreCard` (multi-interviewer, 1–5 rating + recommendation), `Offer`
- **Hire → onboard conversion:** accepted offer auto-creates an inactive `User` account with an onboarding invite — recruitment feeds `accounts` directly
- **Public endpoint risk:** rate limiting, honeypot field, strict file-type/size validation required on the no-auth application form

### 3.6 Flutter Parent App (Scaffold Started, Paused)
Files created so far: `pubspec.yaml`, `app_theme.dart`, `secure_storage.dart`, `dio_client.dart` (with JWT auto-refresh interceptor), `parent.dart` model, `auth_repository.dart`, `auth_provider.dart` (with `activeLearnerProvider` for multi-child switching). Build was explicitly paused mid-scaffold — do not assume more exists than this.

---

## 4. Agentic / AI Features (Proposed — Not Yet Built)

These are places where an LLM agent (Claude via API) adds genuine capability beyond CRUD, ranked roughly by value-to-effort ratio.

### High value, moderate effort
1. **AI-assisted scheme of work drafting.** Beyond the current outcome-distribution logic, use the API to draft `learning_experiences`, `key_inquiry_question`, and suggested `learning_resources` per `SchemeWeek`, grounded in the specific `LearningOutcome` text — teacher reviews/edits rather than writing from scratch. This is the single highest-leverage agentic feature since it directly reduces the biggest teacher pain point (lesson planning time).
2. **Report card narrative generation.** Given a learner's `CompetencyAssessment` records for a term, generate a coherent narrative summary (not just a rubric-level list) for the report card — teachers review and adjust tone/emphasis rather than writing paragraphs per learner per subject.
3. **Parent-facing AI assistant (chatbot).** Answer common questions inside the Flutter app — fee balance, next school event, uniform sizing help, "what does 'Approaching Expectation' mean" — grounded in that parent's actual data via tool use against your DRF API. Reduces admin office inbound query volume.
4. **Resume screening assist for recruitment.** Given a `JobPosting`'s requirements and a `Candidate`'s resume, generate a structured summary + fit rationale for the hiring team to review before deciding whether to advance a stage — augments human judgment, doesn't replace it (avoid fully automated rejection to sidestep bias/legal risk).

### Medium value, higher effort
5. **At-risk learner flagging.** An agent that periodically reviews attendance patterns, competency trends (repeated BE/AE ratings), and fee payment delays together, and surfaces a plain-language flag to teachers/admins ("this learner has missed 3 assessments and attendance dropped 20% this term") — pattern detection humans might not connect across separate modules.
6. **Automated timetable generation.** Given teacher availability, learning area requirements per class, and room constraints, generate a first-draft timetable for admin review — a constraint-satisfaction problem that benefits from agentic iteration (try, check conflicts, retry) rather than a single LLM call.
7. **Interview question generation for recruitment.** Given a `JobPosting` and pipeline stage, draft role-specific interview questions and a scoring rubric for interviewers to use — speeds up interview prep, keeps evaluation more consistent across interviewers.

### Exploratory / lower priority initially
8. **Voice interface in Swahili for low-literacy parents.** Given the accessibility gap flagged earlier, a voice-based query interface (speech-to-text → agent → text-to-speech) for parents who struggle with app text navigation.
9. **Automated content moderation.** Screening shop reviews, messaging content, or public job application cover letters for inappropriate content before human review — useful once volume justifies it, not needed at launch.

**Implementation note for the agent building this:** any AI feature that writes to a `CompetencyAssessment`, `Offer`, or financial record should never auto-commit — always return a draft/suggestion that requires explicit human confirmation via the existing UI, given the legal/educational stakes of this data. Log every AI-generated suggestion separately from the human-confirmed value so the two are auditable independently.

---

## 5. Future Roadmap (Beyond Current Module Set)

### Kenya-specific
- SMS fallback (Africa's Talking or similar) for critical announcements/fee reminders — not everyone has a smartphone
- NEMIS integration (Kenya's national education data system) for statutory reporting
- Swahili language support, at minimum in the Flutter app and SMS content
- Low-bandwidth mode for the Flutter app (text-first, on-demand images)

### New modules
- Transport/bus tracking with pickup points and optional live location
- Health records (allergies, medications, nurse visit logs)
- Disciplinary records with restricted access separate from academic data
- Staff payroll/HR/leave management (recruitment currently stops at onboarding)
- Parent-teacher meeting scheduling (reuse the `Interview` scheduling pattern from recruitment)
- Alumni tracking

### Security & compliance
- Kenya Data Protection Act (2019) compliance: explicit data retention policy, parental consent flows, documented lawful basis for processing children's data
- Field-level/object-level permissions, not just endpoint-level (django-guardian or custom)
- Audit logging across sensitive actions (record views/edits, hiring decisions, fee balance changes)
- Tested backup and disaster recovery procedures

### Technical/DevOps
- Sentry (or equivalent) error tracking from day one, given multi-tenant blast-radius concerns
- CI/CD with automated tests before merge
- API versioning (`/api/v1/`) since React and Flutter clients won't always update in lockstep
- Rate limiting across all public-facing endpoints (shop, careers page, public school pages)

### UX/Product
- Unified notification center (currently announcements, orders, and future interview invites are separate concepts)
- Analytics dashboard for school admins (attendance trends, competency distribution, fee collection rate, shop revenue) — likely the feature that justifies subscription pricing
- Guided onboarding/setup wizard for new schools signing up (classes, CBC data seeding, staff invites)

---

## 6. Explicit Non-Decisions (Do Not Assume)

- Schema-per-tenant migration path is deferred, not designed — do not build it unless explicitly asked
- No UI has been built for shop, scheme-of-work editor, or recruitment pipeline board — only data models and workflow logic are designed
- Full API contract (exact endpoint paths + JSON request/response shapes) has not been written yet
- Item "2" from the original requester's numbered list was never specified — do not invent it

---

# Appendices (added by agent — original brief above left unchanged)

## A. Repository Layout (as built)

```
my-django-project/
├── backend/                 # Django + DRF project
│   ├── manage.py
│   ├── db.sqlite3           # dev DB (see reconciliation B.1)
│   ├── media/               # user uploads
│   ├── venv/                # Python virtualenv (activate: source venv/bin/activate)
│   ├── core/                # project config: settings, urls, wsgi, asgi
│   ├── tenants/             # tenant middleware + models
│   ├── accounts/            # custom User, auth
│   ├── academics/           # (brief's CBC academic model lives here + curriculum/assessment)
│   ├── assessment/          # competency assessments
│   ├── attendance/
│   ├── curriculum/          # LearningArea/Strand/SubStrand/Outcome
│   ├── exams/
│   ├── fees/
│   ├── library/
│   ├── messaging/
│   ├── shop/                # e-commerce
│   ├── api/                 # empty placeholder package (lowercase)
│   ├── Ecomerse/            # empty (note odd casing — legacy)
│   └── lms/                 # empty
└── frontend/
    ├── codingclubskenya/    # React + Vite web app (staff)
    ├── parent_app/          # Flutter parent app
    └── parents/             # Flutter parent app (alt scaffold)
```

## B. As-Built Reconciliation (observations only — brief decisions preserved)

1. **Database:** brief specifies PostgreSQL; `backend/core/settings.py` currently uses SQLite (`django.db.backends.sqlite3`, `NAME = BASE_DIR / 'db.sqlite3'`). Switch to Postgres before any real multi-tenant deployment.
2. **Django apps mismatch:** brief's app list omits `curriculum` and `assessment` (both exist with full `models.py`/`serializers.py`/`views.py`/`urls.py`) and lists `recruitment`, which does **not** yet exist in the repo. Decide whether `curriculum`/`assessment` are the realization of the brief's CBC module, and scaffold `recruitment` when that work begins.
3. **M-Pesa & Celery already configured:** `MPESA_*` settings and `CELERY_BROKER_URL`/`CELERY_RESULT_BACKEND` (Redis) already exist in `settings.py`, even though the brief frames these as decisions. No broker/consumer code is present yet.
4. **API versioning:** brief's roadmap wants `/api/v1/`; `core/urls.py` currently exposes unversioned `/api/...`. Wrap the existing `include()` calls under a `api/v1/` prefix when versioning is adopted, to avoid breaking current clients.
5. **`api/` folder:** exists but is empty (lowercase, post-restructure). The brief's API lives inside each app (`<app>/views.py`, `<app>/serializers.py`, `<app>/urls.py`), included from `core/urls.py`.

## C. Running the Backend

```bash
cd backend
source venv/bin/activate        # Linux/macOS (NOT venv/Scripts/activate)
python manage.py check          # verify config
python manage.py migrate        # apply migrations
python manage.py runserver      # http://127.0.0.1:8000
```

API docs (drf-spectacular) at `/api/schema/` and Swagger UI at `/api/docs/` once running.

## D. Suggested Next Steps (not yet executed)

- Reconcile the app list with the brief (confirm `curriculum`/`assessment` mapping; scaffold `recruitment`).
- Add `/api/v1/` versioning wrapper.
- Introduce a typed OpenAPI client generation step for React + Flutter.
- Add a `.env`/settings split for dev vs prod (DB, M-Pesa keys, Celery broker) before going live.
