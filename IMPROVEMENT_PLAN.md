# Improvement Plan — Security, DevOps, Code Quality, Architecture

> Status: **Draft v1** — covers all three running systems (backend Django API, React staff frontend, Next.js distributor). Prioritized into 4 phases. Each item is actionable with an effort estimate.

---

## 0. Current State Summary

| Area | Status |
|---|---|
| Backend | Django 6.0.7 + DRF + JWT. 31 apps. `settings.py` (dev: DEBUG=True, SQLite, CORS `*`) + `settings_production.py` (DEBUG=False, Postgres, `.env`, SSL flags, logging). `.env` exists. No throttling. |
| Staff frontend | React 19 + Vite + Tailwind. Port 5173. Has oxlint, no tests. |
| Distributor | Next.js 16 + React 19. Port 3000. Has ESLint, no tests. |
| Deployment | gunicorn + nginx config present. No Docker. `start_gunicorn.sh` exists. |
| Tests | 1 test file total (`clubs/tests.py`). No CI backend. |
| Auth | 31 registered users across roles (admin, teacher, parent, student, driver, distributor). Passwords found/reset and documented. |

---

## Appendix A: Production Environment Audit (SSH inspection — vmi3555221)

SSH access confirmed at `213.199.41.219` (user `devops`).

### A.1 Architecture as deployed

| Component | Details |
|---|---|
| **Nginx** | Ports 80→443 redirect, SSL (Let's Encrypt). Serves React dist + static + media. Proxies `/api/`, `/admin/` → gunicorn Unix socket. |
| **Gunicorn** | systemd service `gunicorn.service`, 3 workers, socket `unix:/home/devops/home/personal/personalweb/epk/epk.sock`, `--umask 000`. Version 26.2.0 (local repo pins 23.0.0 — **drift**). |
| **Django** | `core.settings_production` via `.env`. PostgreSQL 16.15 (port 5432), Redis 7.0.15 (cache DB 1, sessions DB 2). Timezone Africa/Nairobi. |
| **Next.js** | Distributor on port 3001 (`next start`), served statically via nginx alias. |
| **MySQL + phpMyAdmin** | MySQL 8.x (port 3306), phpMyAdmin at `/pma/`. |
| **Celery** | Installed (5.6.3) but **NOT RUNNING** — no systemd service, no process. Async tasks (M-Pesa callbacks, notifications, PDFs) are broken. |

### A.2 Critical production issues

| # | Issue | Severity | Evidence |
|---|---|---|---|
| 1 | **Gunicorn `--umask 000`** makes socket `srwxrwxrwx` — any local user can connect to backend | **CRITICAL** | `ls -la epk.sock` shows `srwxrwxrwx` |
| 2 | **Celery not running** — queued tasks (notifications, M-Pesa, PDFs) never execute | **CRITICAL** | No celery process or service; `CELERY_BROKER_URL` set in `.env` but worker absent |
| 3 | **`django-redis` not installed** but referenced in `CACHES` config — Redis-backed sessions + cache will crash at runtime | **CRITICAL** | `importlib: No module named 'django_redis'`; settings use `django_redis.client.DefaultClient` |
| 4 | **phpMyAdmin exposed at `/pma/`** — frequent attack target | HIGH | nginx config `location ^~ /pma/` |
| 5 | **No nginx rate limiting** (`limit_req_zone` / `limit_req`) | HIGH | nginx.conf grep shows no rate-limit directives |
| 6 | **No DRF throttling** — `REST_FRAMEWORK` has no `DEFAULT_THROTTLE_*` | HIGH | Production settings lines 151–162 |
| 7 | **No gunicorn resource limits** — `MemoryMax=infinity` (OOM kill risk) | MEDIUM | `systemctl show gunicorn` shows `MemoryMax=infinity` |
| 8 | **No `django-axes`** — no login brute-force protection | MEDIUM | Not installed in venv |
| 9 | **No Sentry** — no centralized error tracking | MEDIUM | Not installed in venv |
| 10 | **Missing security headers** — no CSP, no Referrer-Policy, no Permissions-Policy | LOW | Only HSTS/XSS-filter/nosniff configured |
| 11 | **Settings drift** — repo `settings_production.py` (236 lines) < live (296 lines with Redis cache/session config) | LOW | `scp` diff |
| 12 | **Gunicorn version drift** — prod 26.2.0 vs repo pin 23.0.0 | LOW | venv python check |

### A.3 What's already good

- `DEBUG=False`, `SECRET_KEY` from env, `ALLOWED_HOSTS` restricted ✓
- HTTPS enforced (HTTP→HTTPS 301 redirect) ✓
- HSTS 1yr + preload + subdomains ✓
- Secure session cookies (HttpOnly, Secure, SameSite=Lax) ✓
- Static/media with cache headers ✓
- `.env` file permissions `600` (owner-only) ✓
- gunicorn systemd with `Restart=on-failure` ✓
- gzip + TLS 1.2/1.3 ✓

---

## Phase 0 — Production Critical Fixes (P0, do first, 2–4 hours)

These are fixes found via SSH audit of the live Contabo VPS (`213.199.41.219`). All can be done without downtime.

### 0.1 Kill the world-readable gunicorn socket
- **Problem:** `--umask 000` makes `epk.sock` → `srwxrwxrwx`. Any local user/process can connect to the Django backend directly (bypassing nginx).
- **Action:** 
  1. Fix the systemd unit: change `--umask 000` → `--umask 077` (socket readable/writable only by `devops`).
  2. `chmod 660 /home/devops/home/personal/personalweb/epk/epk.sock`
  3. `systemctl daemon-reload && systemctl restart gunicorn`
  4. Verify: `ls -la epk.sock` should show `srw-rw----`
- **Effort:** 15 min

### 0.2 Start Celery workers (currently not running at all)
- **Problem:** Celery 5.6.3 is installed but neither the worker nor beat scheduler is running. All async tasks silently fail — M-Pesa callbacks, fee reminders, notifications, PDF/report-card generation.
- **Action:**
  1. Create `/etc/systemd/system/celery.service` and `/etc/systemd/system/celerybeat.service` (or use `django-celery-beat` already in deps if present).
  2. Start both: `systemctl enable --now celery.service celerybeat.service`
  3. Verify with: `celery -A core inspect ping`
  4. Test a task: `python manage.py shell -c "from django.core.management import call_command; ..."` or trigger an MPesa webhook.
- **Effort:** 1–2 hours (writing service files + verification)
  - **Service file template (celery.service):**
    ```ini
    [Unit]
    Description=Celery Service
    After=network.target redis-server.service

    [Service]
    User=devops
    Group=www-data
    WorkingDirectory=/home/devops/home/personal/personalweb/epk
    EnvironmentFile=/home/devops/home/personal/personalweb/epk/.env
    ExecStart=/home/devops/home/personal/personalweb/epk/venv/bin/celery -A core worker -l info
    Restart=always

    [Install]
    WantedBy=multi-user.target
    ```

### 0.3 Fix missing `django-redis` package (sessions + cache will crash)
- **Problem:** `settings_production.py` (live version, 296 lines) configures Redis cache with `CLIENT_CLASS: 'django_redis.client.DefaultClient'`, but `django-redis` is **not installed** in the production venv. This will raise `ModuleNotFoundError` when any cache operation runs (including session-backed auth on every authenticated request).
- **Action:**
  1. `pip install django-redis` in the production venv.
  2. Or — if using Django's built-in `RedisCache` (Django 4.2+), remove the `CLIENT_CLASS` and `COMPRESSOR` options from `CACHES` in settings since they're django-redis-specific.
  3. Restart gunicorn after fix.
- **Effort:** 15 min
  - **Investigation needed:** Confirm which approach (install vs. simplify settings) is less disruptive. Check if `django.core.cache.backends.redis.RedisCache` works standalone (Django 4.2+ has built-in Redis support, but `COMPRESSOR` key is django-redis-only).

### 0.4 Add nginx rate limiting for public endpoints
- **Problem:** No `limit_req_zone` / `limit_req` in nginx. API, login, and phpMyAdmin endpoints can be hammered.
- **Action:** Add to nginx.conf `http` block:
  ```nginx
  limit_req_zone $binary_remote_addr zone=login:10m rate=5r/m;
  limit_req_zone $binary_remote_addr zone=api:10m rate=60r/s;
  limit_req_zone $binary_remote_addr zone=pma:10m rate=5r/m;
  ```
  Then apply `limit_req zone=login burst=10 nodelay;` inside `/api/auth/login/` and `limit_req zone=pma burst=5;` inside `/pma/`.
- **Effort:** 30 min

### 0.5 Remove or restrict phpMyAdmin access
- **Problem:** `/pma/` is world-exposed and a frequent attack vector.
- **Action:** Either remove the location block entirely (use `psql` over SSH for DB admin), or restrict to specific IPs:
  ```nginx
  location ^~ /pma/ {
    allow YOUR_OFFICE_IP;
    deny all;
    # ... rest of config
  }
  ```
- **Effort:** 15 min

---

## Phase 1 — Critical Security Fixes (P0, 1–2 days)

### 1.1 API rate limiting
- **Problem:** No throttling anywhere. Public endpoints (`/shop/`, `/distributor/`, career application form) are vulnerable to brute-force and abuse.
- **Action:** Add `drf-throttling` via DRF's `ScopedRateThrottle` in `REST_FRAMEWORK` settings:
  ```python
  'DEFAULT_THROTTLE_CLASSES': ['rest_framework.throttling.ScopedRateThrottle'],
  'DEFAULT_THROTTLE_RATES': {'anon': '100/day', 'login': '5/min', 'distributor': '500/hour'},
  ```
  Tag public viewsets (`@extend_schema`) with `throttle_scope = 'anon'`.
- **Effort:** 1 hour

### 1.2 Public endpoint hardening
- **Problem:** Job application form accepts anonymous submissions (rate limiting, honeypot, file validation explicitly called out in the brief as required but not built).
- **Action:** Add honeypot field, file-type allowlist (`pdf, doc, docx`), max 2 MB file size, and `@throttle_classes([AnonRateThrottle])`.
- **Effort:** 2 hours

### 1.3 Replace `CORS_ALLOW_ALL_ORIGINS = True` in dev settings
- **Problem:** Dev settings allow any origin — dangerous if deployed.
- **Action:** Change to `CORS_ALLOWED_ORIGINS = ['http://localhost:5173', 'http://localhost:3000']` in `settings.py`.
- **Effort:** 15 min

### 1.4 Secret key & env hygiene
- **Problem:** `SECRET_KEY` is hardcoded in `settings.py` (the dev file). Anyone with repo access can forge JWT.
- **Action:** Generate via `from dotenv import load_dotenv; os.environ.get('SECRET_KEY')` in `settings.py` as well, and create a `.env.example` template in the repo (no secrets committed).
- **Effort:** 30 min

### 1.5 Add `django-axes` to backend requirements
- **Problem:** No brute-force protection on login.
- **Action:** `pip install django-axes`, add to `AUTHENTICATION_BACKENDS` and `INSTALLED_APPS`, configure lockout (5 attempts → 300s). This covers `/api/auth/login/`.
- **Effort:** 3 hours (including migration + testing)

---

## Phase 2 — Observability & DevOps (P1, 2–3 days)

### 2.1 CI/CD pipeline for backend
- **Problem:** No backend CI. Tests aren't gated.
- **Action:** Create `.github/workflows/backend-ci.yml`:
  - `python -m pip install -r requirements.txt`
  - `python manage.py check`
  - `python manage.py migrate` (SQLite in-memory via `pytest-django` or override)
  - `ruff check` + `ruff format --check`
- **Effort:** 4 hours (includes adding `ruff` to requirements)

### 2.2 Frontend CI for both React and Next.js
- **Action:** Two workflow files (or one reusable): lint + typecheck + build for both `frontend/codingclubskenya` and `distributor/`.
- **Effort:** 3 hours

### 2.3 Sentry error tracking
- **Problem:** Brief explicitly calls this out as day-one requirement.
- **Action:** `pip install sentry-sdk`, init in `settings.py` + `settings_production.py`, capture Django + Celery + DRF exceptions.
- **Effort:** 2 hours

### 2.4 Database migration: SQLite → PostgreSQL (dev)
- **Problem:** Dev uses SQLite. Production uses Postgres. Drift causes subtle bugs (JSONField behavior, case-insensitive lookups, etc.).
- **Action:** Provide a `docker-compose.yml` with Postgres + Redis for local dev so `settings.py` can point to it. Keep SQLite as fallback only.
- **Effort:** 2 hours

### 2.5 Fix gunicorn `start_gunicorn.sh` path bug
- **Problem:** Script hardcodes `DJANGO_SETTINGS_MODULE=core.settings_production` and reads `.env`, but the `cd "${SCRIPT_DIR}"` + venv activation path is fragile.
- **Action:** Add a `systemd` service file + a verified startup script; test with `gunicorn --check-config`.
- **Effort:** 1 hour

---

## Phase 3 — Testing & Code Quality (P1, 3–4 days)

### 3.1 Add test framework
- **Action:** `pip install pytest pytest-django pytest-cov`. Create `pytest.ini` + `conftest.py` with factory-based fixtures (user, school, tenant).
- **Effort:** 2 hours

### 3.2 Write tests for security-critical paths
- **Action:** Tests for:
  - JWT login/lockout (wrong password → 401; after N failures → 429/locked)
  - Rate limiting on public endpoints
  - Multi-tenant isolation (user A can't see user B's school data)
  - Parent ↔ Learner access control
- **Effort:** 2–3 days

### 3.3 Lint + type-check the backend
- **Action:** `ruff check` + `ruff format` across all 31 Django apps. Fix drf-spectacular `@extend_schema` warnings (annotate APIViews, fix duplicate `Payment` component name in shop vs fees serializers).
- **Effort:** 1 day

### 24. Lint + type-check the frontends
- **Action:** Add `tsc --noEmit` as a lint gate to both frontend `package.json` scripts + GitHub Actions.
- **Effort:** 2 hours

---

## Phase 4 — Architecture & API Improvements (P2, 1–2 weeks)

### 4.1 API versioning
- **Problem:** Brief roadmap wants `/api/v1/`. Currently unversioned. React and Flutter won't update in lockstep.
- **Action:** Add `Accept` header versioning or URL prefix (`/api/v1/`) using `drf-versioning`. Migrate existing includes.
- **Effort:** 4 hours

### 4.2 Typed API client generation
- **Problem:** Manual API client code duplicates types. Drift risk.
- **Action:** Generate TypeScript clients from drf-spectacular OpenAPI (`.openapi-typescript` for React, `openapi_fetch` or `swagger_dart` for Flutter).
- **Effort:** 3 hours setup + 1 day integration

### 4.3 Audit logging for sensitive actions
- **Problem:** Brief calls for logging record views/edits, hiring decisions, fee changes. Currently none.
- **Action:** Add `django-simple-history` or a custom `AuditLog` model. Log: User CRUD, fee balance changes, Offer accept/reject, CompetencyAssessment edits.
- **Effort:** 2 days

### 4.4 Fix duplicate `Payment` serializer component
- **Problem:** `shop.serializers.PaymentSerializer` and `fees.serializers.PaymentSerializer` both named `Payment` in the OpenAPI schema → ambiguity.
- **Action:** Rename one (e.g., `ShopPaymentSerializer`) with `@extend_schema` fix.
- **Effort:** 1 hour

### 4.5 Object-level permissions
- **Problem:** Brief wants field/object-level permissions. Currently only `IsAuthenticated` + tenant-scoping in `get_queryset`.
- **Action:** Install `django-guardian`, add `IsOwnerOrReadOnly` + object permission checks for sensitive objects (e.g., a parent viewing another parent's learner data).
- **Effort:** 1–2 days

---

## Phase 5 — Future Roadmap Items (P3, ongoing)

Items pulled directly from the AGENTS.md roadmap where engineering work is needed:

| # | Item | Effort | Priority |
|---|---|---|---|
| A | **AI-assisted scheme of work drafting** — use LLM to draft `learning_experiences`, `key_inquiry_question`, `learning_resources` per `SchemeWeek` | 2–3 days | High |
| B | **Report card narrative generation** — LLM generates narrative from `CompetencyAssessment` records | 2 days | High |
| C | **Parent-facing AI chatbot** (Flutter) — LLM + API tool-use answering fee/event/uniform questions | 3–4 days | Medium |
| D | **Resume screening assist** — LLM summarizes candidate + fit rationale (never auto-reject) | 2 days | Medium |
| E | **At-risk learner flagging** — periodic agent combining attendance + competency + fee data | 2–3 days | Medium |
| F | **Automated timetable generation** — constraint-satisfaction solver | 3–5 days | Lower |
| G | **Interview question generation** — LLM drafts questions + scoring rubric per `JobPosting` | 1 day | Lower |
| H | **Swahili support** (Flutter + SMS) | 2–3 days | Medium |
| I | **SMS fallback** (Africa's Talking) for announcements/fee reminders | 2 days | Medium |
| J | **NEMIS integration** for statutory reporting | 3 days | Low |
| K | **Analytics dashboard** for attendance trends, competency distribution, fee collection, shop revenue | 3–5 days | High (pricing driver) |

Every AI feature (A–G) must follow the **human-in-the-loop** rule from the brief: AI output is a draft/suggestion, never auto-committed to `CompetencyAssessment`, `Offer`, or financial records. Log AI suggestions separately from confirmed values.

---

## Appendix B — Gap Analysis: What's Built vs. Full CBC School ERP

### B.1 Backend — modules COMPLETE (models + serializers + views + URLs all exist)

| Module | App | Key models | Status |
|---|---|---|---|
| Multi-tenancy | `tenants` | School, SchoolSettings, TenantMiddleware | ✅ Complete |
| User accounts | `accounts` | User (7 roles), ParentLearner, StudentProfile, TeacherProfile | ✅ Complete |
| CBC academics | `academics` | Grade, Pathway, Stream, LearningArea, Strand, SubStrand, LearningOutcome, RubricDescriptor, Timetable, Assignment, Term | ✅ Complete |
| Competency assessment | `assessment` | CompetencyAssessment, AssessmentTask, AssessmentTaskResult, AssessmentEvidence, LearnerPortfolio | ✅ Complete |
| Attendance | `attendance` | AttendanceRecord, AttendanceSummary, AttendanceNotification | ✅ Complete |
| Curriculum / schemes | `curriculum` | ReferenceDocument, SchemeOfWork, SchemeWeek | ✅ Complete |
| Courses / LMS | `courses` | Course, Topic, Lesson, QuizQuestion, QuizAttempt, Post, Submission, LearningMaterial, Enrollment | ✅ Complete |
| Fees | `fees` | FeeStructure, Invoice, Payment (Cash/Card/Bank/M-Pesa) | ✅ Complete |
| Shop (e-commerce) | `shop` | ProductCategory, Product, ProductVariant, Order, OrderItem, Payment, FormSubmission, GuestOrder | ✅ Complete |
| Exams & report cards | `exams` | Exam, ExamGrade, ReportCard (plus CBC report card view) | ✅ Complete |
| Library | `library` | Book, Loan, Reservation | ✅ Complete |
| Messaging | `messaging` | Announcement (with featured_products M2M), Conversation, DirectMessage, Notification | ✅ Complete |
| Clubs | `clubs` | Club, ClubSession | ✅ Complete |
| Recruitment (ATS) | `recruitment` | PipelineStage, JobPosting, Candidate, Application, Interview, ScoreCard, Offer | ✅ Complete |
| Distributor | `distributor` | DistributorProfile, DistributorProduct, SchoolOrder, Delivery, DistributorWallet, WalletTransaction | ✅ Complete |
| Supply lists | `requirements` | RequiredItem, RequiredItemOption | ✅ Complete |
| Complaints | `complaints` | Complaint, ComplaintComment | ✅ Complete |
| Events | `events` | Event | ✅ Complete |
| Homework | `homework` | Homework, HomeworkSubmission | ✅ Complete |
| Notices | `notices` | Notice | ✅ Complete |
| Transport | `transport` | Route, BusStop, Bus (live GPS), BusAssignment (pickup locations) | ✅ Complete |
| Gradebook | `gradebook` | CoreCompetency, CoreValue, LearningAreaScore, StudentCompetencyScore, PortfolioArtifact, CycleMeta | ✅ Complete |
| Reports | `reports` | Views only: overview, attendance_trend, results, performance, teachers_report | ✅ Complete |

**Backend API total:** 282 endpoints registered in drf-spectacular schema.

### B.2 Backend — modules MISSING (in brief roadmap or ERP essentials)

| Module | Brief reference | Why needed | Effort |
|---|---|---|---|
| **Health records** | §5 Future Roadmap | Allergies, medications, nurse visit logs — mandatory for any school with a nurse/campus clinic | 1–2 days |
| **Disciplinary records** | §5 Future Roadmap | Separate restricted access from academics; KDPA requirement for handling student conduct data | 2 days |
| **Staff payroll / HR / leave** | §5 Future Roadmap | Recruitment currently stops at onboarding (inactive User). Payroll, leave requests, HR file still needed | 3–5 days |
| **Parent-teacher meeting scheduling** | §5 Future Roadmap | Brief says "reuse Interview scheduling pattern" — no module yet | 1 day |
| **NEMIS integration** | §5 Kenya-specific | Statutory reporting to Kenya's national education data system | 3 days |
| **SMS fallback** | §5 Kenya-specific | Africa's Talking for critical announcements/fee reminders (not all parents have smartphones) | 2 days |
| **Swahili localization** | §5 Kenya-specific | Flutter app + SMS content in Swahili for low-literacy parents | 2–3 days |
| **Low-bandwidth mode** | §5 Kenya-specific | Text-first Flutter mode, on-demand images | 1–2 days |
| **Unified notification center** | §5 UX/Product | Announcements, orders, interview invites, fee reminders are currently fragmented concepts | 2–3 days |
| **Analytics dashboard** | §5 UX/Product | Comprehensiveschool admin dashboards: attendance trends, competency distribution, fee collection, shop revenue — the pricing-justification feature | 3–5 days |
| **Data retention policy / parental consent** | §5 Security | KDPA compliance: lawful basis for children's data, explicit consent flows, retention schedule | 2 days |
| **Audit logging** | §5 Security | Who viewed/edited what, when — especially fee balances, hiring decisions, competency scores | 2 days |
| **Object-level permissions** | §5 Security | Currently only endpoint-level (`IsAuthenticated`) + tenant-scoping. `django-guardian` not installed. | 1–2 days |

### B.3 Frontend — what's built

| App | Framework | Pages/routes | Status |
|---|---|---|---|
| Staff web | React 19 + Vite + Tailwind + shadcn/ui | 35+ routes (login, dashboard, students, parents, teachers, classes, learning areas, schemes of work, shop, fees, timetable, attendance, exams, library, messaging, homework, reports, transport, driver map, AI teacher assist) | ✅ Full |
| Distributor | Next.js 16 (static export) | Products, orders, wallet, categories, grades, learning areas | ✅ Full |
| **Parent mobile** | Flutter 3.x | **35 pages** across: announcements, courses, dashboards (4 role types), exams, messaging, orders, requirements (supply lists), shop, teacher, timetable, transport (bus tracking) | ✅ **More complete than brief** — brief said "paused mid-scaffold"; actually built out |
| **Parent web** | — | Not present (parents use Flutter only per brief) | N/A |

### B.4 AI / Agentic features — built vs. proposed

| # | Feature (brief §4) | Status |
|---|---|---|
| 1 | AI-assisted scheme of work drafting (learning_experience, key_inquiry, resources per SchemeWeek) | ⚠️ Partial — only a basic `AITeacherAssistView` + `weekly_timetable` AI helper exist. No full SoW drafting agent. |
| 2 | Report card narrative generation | ❌ Not built |
| 3 | Parent-facing AI chatbot | ❌ Not built |
| 4 | Resume screening assist | ❌ Not built |
| 5 | At-risk learner flagging | ❌ Not built |
| 6 | Automated timetable generation | ⚠️ Partial — `Timetable` model + AI weekly timetable helper, but no constraint-satisfaction solver |
| 7 | Interview question generation | ❌ Not built |
| 8 | Swahili voice interface | ❌ Not built |
| 9 | Automated content moderation | ❌ Not built |

### B.5 Infrastructure gaps (vs. brief §5 Technical roadmap)

| Gap | Status |
|---|---|
| API versioning (`/api/v1/`) | ❌ Unversioned (`/api/` only) |
| CI/CD with automated tests | ❌ Backend CI missing; frontend CI exists in `frontend/classroomio` only |
| Sentry / error tracking | ❌ Not installed in prod venv |
| Rate limiting (all public endpoints) | ❌ Not configured |
| Typed OpenAPI client generation | ❌ Manual API calls in both React and Flutter |
| `.env`/settings split dev vs prod | ⚠️ Production has `settings_production.py` + `.env`; dev uses hardcoded `settings.py`. No Docker for parity. |

---

## Quick Wins (can do immediately, < 30 min each)

1. ✅ **Done:** All login credentials discovered/reset and verified — documented above.
2. Rename `backend/requirements/` app → `backend/supply_lists/` (the name `requirements` conflicts with `requirements.txt` and confuses tooling). Requires `Rename`, `apps.py`, migration `db_table` rename, settings update.
3. Add `.env.example` to repo root and `backend/` with all keys documented (no secrets).
4. Run `manage.py check --deploy` against production settings — it will flag remaining security gaps.
