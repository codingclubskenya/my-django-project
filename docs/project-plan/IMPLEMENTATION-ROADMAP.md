# Learning Pack — Implementation Roadmap & Task Checklist

- **Date:** 2026-11-12 · Derived from SYSTEM-AUDIT.md and SECURITY-AUDIT.md
- **Principles:** Security before features. Reuse and consolidate before building new. One module per PR, with tests and docs. Nothing deploys without a passing suite and a rollback plan.

## Sequencing

| Stage | Goal | Contents | Exit criteria |
|---|---|---|---|
| **0. Stabilise** | Safe base to work on | Land or stash the in-progress `qa/hardening-fixes` work. Fix repo `settings_production.py` (boots, matches live). Add the 2 missing migrations. Make the test suite green. Set up CI (ruff + pytest + frontend builds). Run dependency audits. | `check --deploy` passes with prod settings; CI green |
| **1. Critical security** | Close exploitable holes | C1–C4 (payments + privilege escalation), storefront switches to server-verified payment status, H3, H4, H5, H6 throttling | Regression tests for each finding; manual exploit re-test fails |
| **2. Tenancy & files** | Isolation you can prove | Shared tenancy mixin + related-field validator (M5). Cross-tenant test harness across all endpoints. Upload validator (H2). Private storage + signed URLs (H1, Cloudflare R2). Fee immutability (M2). | Cross-tenant suite green for every ViewSet |
| **3. Consolidate** | Remove duplicate models | D1 staff/payroll, D2 booklists/requirements, D10 AcademicYear, D8 mixins. Data migrations preserve records. | No data loss on a prod-copy dry run |
| **4. Finish core modules** | Complete existing modules | A school mgmt (onboarding wizard, promotion, server-side import preview), F finance (ledger, receipts, reversals, reconciliation, reports), H staff, G transport | Module journeys pass |
| **5. Parent booklist → order** | Flagship flow | Upload → extraction job (worker, off the 4 GB box if heavy) → catalogue matching → parent review → cart → order → verified payment. Never auto-order. | E2E test of the booklist journey |
| **6. Learning** | Course Studio + exams | C consolidation (assignments/announcements), D question bank/papers/marking/publication workflow, E AI teacher-assist (draft-only, logged) | Teacher & student journeys pass |
| **7. Experience** | UI/UX, 3D, APK | Design tokens with brand colours across the staff app. 3D: single codebase, GLB/KTX2, instancing, lazy sections, 2D fallback. Flutter: signing, offline, parity. | Lighthouse/a11y baseline. 3D budget met on a mid-range Android. |
| **8. Ops & automation** | Run it reliably | Celery running, Redis, Sentry, backups + restore test, monitoring. n8n evaluation (separate host). H5P (separate service). | Restore drill done; alerts firing |
| **9. Launch** | Go-to-market | Full journey testing. Marketing assets (Phase 9 of the brief) only after this is stable. | TESTING-REPORT sign-off |

## Task checklist

### ✅ Completed
- [x] Phase 1 codebase audit (SYSTEM-AUDIT.md)
- [x] Phase 2 security audit, static (SECURITY-AUDIT.md)
- [x] As-built architecture doc (ARCHITECTURE.md)
- [x] Baseline test run (TESTING-REPORT.md)

- [x] Committed in-progress work: backend `da2896a`, distributor `f821206`, frontend `5459f2a` (approved 2026-11-12)
- [x] **S0** `settings_production` inherits `settings.py`, fails closed; integration settings env-driven
- [x] **S0** Missing payroll/procurement migrations
- [x] **S0** Test suite green (132 passed); `core.settings_test`; missing apps added to `testpaths`
- [x] **C1–C3** Daraja-verified payments; storefront polls status; guest public token; ChamaGO webhook retired
- [x] **C4** User serializer lock-down + tenant forced on create
- [x] **C5 (new)** School admins no longer created as superusers + `audit_superusers` command
- [x] **C6 (new)** Order PATCH/learner validation; **H8 (new)** booklist cross-school writes
- [x] **H3** Random temporary passwords, forced change (backend + staff web + storefront + Flutter), `reset_default_passwords` command (approved)
- [x] **H4** Cross-tenant checks use `is_superuser` only
- [x] **H6 (part)** Scoped DRF throttles

- [x] **Stage 2** (`1b86977`): H2 upload validator, H5 AI roles, M5 isolation sweep, C7 tenant-root lockdown, H9 wallets, H10 recruitment, H11 curriculum IDOR, public-form throttles, R1 anon-throttle regression (`1e6f5bb`)

- [x] **Stage 3**: H1 private files via signed links + nginx (R2 can plug in behind it later), M2 fee ledger (append-only, reversals), H6 nginx limits, M4, M9, login-throttle NAT fix, H7 prepared (opt-in signing)

### 🔄 In progress
- [ ] Release R1: needs Daraja sandbox test + deploy (DEPLOYMENT-GUIDE runbook), then the data clean-up commands on prod

### ⏳ Pending, in priority order
1. [ ] **S0** Reconcile with the *live* prod settings file (Redis cache/session config): compare on the server before deploy
2. [ ] **S0** CI pipeline (GitHub Actions: ruff, pytest, `npm run build` ×2, `pip-audit`, `npm audit`)
5. [ ] **M5 (rest)** Consolidate the 4 `SchoolScopedViewSetMixin` copies into `core/tenancy.py` (the sweep now guards behaviour)
7. [ ] Consolidations D1, D2, D10, then the module completion stages above

### ⛔ Blocked
- [ ] **Daraja go-live:** needs sandbox + production credentials (shortcode, passkey, consumer key/secret) and a public HTTPS callback. Decision made: Daraja replaces ChamaGO (2026-11-12).
- [ ] **Production verification (M7):** needs SSH access during the work session. Confirm the gunicorn umask, Celery, `/pma/` and the live settings file.
- [ ] **Dependency CVE scan:** needs network access and `pip-audit` installed.
- [ ] **Cloudflare R2:** needs an account, bucket and API token (as env vars, never committed).
- [ ] **AI features:** need an API key and a budget decision.

### 🟠 Requires approval (product/owner decisions)
- [ ] Which booklist model survives (D2), and the staff/payroll merge (D1): data migrations on production records
- [ ] ClassroomIO (AGPL): inspiration only vs a separate service
- [ ] School-configurable roles (custom RBAC) vs the fixed role enum
- [ ] Multi-school memberships (D13)
- [ ] Where n8n and H5P run (recommend a separate small VPS, not the 4 GB app server)
- [ ] Retiring the `learning-pack-3d` Vite app (D7)
- [ ] Deprecation date for unversioned `/api/`
- [ ] Data Protection Act consent/retention policy

## Server budget (4 GB Contabo)

| Process | Approx. RAM | Note |
|---|---|---|
| PostgreSQL | 500–800 MB | Tune `shared_buffers` ≈ 512 MB |
| Gunicorn 3 workers | 450–750 MB | Set `MemoryMax`, `max_requests` |
| Redis | 50–150 MB | `maxmemory` + LRU |
| Celery 1 worker (concurrency 2) | 200–300 MB | No OCR or LLM inference locally; call APIs |
| Next.js `next start` | 200–400 MB | Or static export behind nginx where possible |
| nginx | < 50 MB | |
| **MySQL + phpMyAdmin** *(reported)* | 300–500 MB | **Remove if unused.** That frees headroom. |

OCR, AI extraction, H5P and n8n should run as external APIs or on a separate host.

### Follow-ups noticed during R1 (not yet done)
- The Flutter app folder `frontend/parents/` is listed in `frontend/.gitignore`, yet 60+ of its files are tracked and 13 under `lib/` are not. Decide whether the app gets its own repo or the ignore rule is removed.
- Local Node 18 can't build Next 16. Use Node ≥ 20.9 on dev machines and CI.
- `ChamaGoIntegrator` (`shop/services/mpesa.py`) is now unused: remove after R1 is stable.
- `pay_fee_balance` still mutates an invoice amount (TODO marker; needs the finance ledger, M2).
- Distributor wallets: `DistributorProfileViewSet` previously let every school ADMIN list all distributors. It's now platform-admin only. Confirm no school-admin screen needs it.

### Follow-ups from stage 3
- Flutter shows lesson/assignment attachments as raw text; with signed links they should open in the browser (`url_launcher`) and be re-fetched when expired.
- `applicationId` is still `com.example.parents`. Choose the final id and signing key together, once, before the Play Store: both break in-place upgrades.
- Existing private files keep guessable paths (now unreachable publicly). A one-off command can rename them to random names (needs a data-migration approval).
- Cloudflare R2: only `core/private_files._file_response` and the upload storage backend need to change.
- M3 (tokens in localStorage) needs a cookie-based session design; M6 (axes only in prod settings).
- Signed download links are checked on every request but not logged. Add `AuditLog` entries for CV and evidence downloads (Data Protection Act).
