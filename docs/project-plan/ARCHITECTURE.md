# Learning Pack — Architecture (As-Built + Target)

- **Date:** 2026-11-12
- **Design intent:** `learning_pack_project_documentation/ARCHITECTURE.md`. This file records what actually exists and the deltas.

## 1. Runtime topology (current)

```
Browser (staff) ──► nginx ──► /schoolsystem/   React+Vite static build (frontend/codingclubskenya)
Browser (public/parents) ──► nginx ──► Next.js :3001 (distributor) ── storefront, shop, 3D supermarket
Flutter APK (frontend/parents) ──► https://codingclubskenya.com/api
                         nginx ──► /api/, /admin/ ──► gunicorn (unix socket, 3 workers) ──► Django
                         nginx ──► /media/  (PUBLIC alias — see SECURITY H1)
                         nginx ──► /static/
Django ──► PostgreSQL 16 (prod) / SQLite (dev)
       ──► Redis (cache db1, sessions db2) [reported]
       ──► Celery + beat [units exist; reported not running]
       ──► ChamaGO API (M-Pesa STK) · LLM API (optional) · SMTP
```

## 2. Backend layout

- `core/`: settings (`settings.py` dev, `settings_production.py` prod; they drift), `urls.py` (mounts every app under `/api/<app>/` **and** includes `urls_v1.py` under both `/api/` and `/api/v1/`), `celery.py`.
- **Tenancy:** shared schema. `tenants.School` is the root, and `User.school` is a single FK. Scoping lives in each view (`get_queryset` filtering `school=request.user.school`, via four copies of `SchoolScopedViewSetMixin`). `TenantMiddleware` resolves a school from the subdomain but nothing uses it.
- **Auth:** simplejwt (60 min access, 7 day rotating refresh). Separate student login. allauth/dj-rest-auth mounted (Google). axes in prod only.
- **Authorisation:** fixed `User.role` enum plus permission classes in `accounts/permissions.py`. No object-level framework (django-guardian is installed but unused).
- **Audit:** `audit.AuditLog` filled by post_save/post_delete signals on sensitive models.
- **AI:** `ai/client.py` (Anthropic SDK or OpenAI-compatible URL) with keyword fallbacks.

### App groups
| Domain | Apps |
|---|---|
| Platform | tenants, accounts, audit, website |
| Academics | academics, curriculum, assessment, gradebook, exams, homework, attendance, reports |
| Learning | courses, library, clubs |
| Commerce | shop, carts, booklists, requirements, storefront, discovery, distributor, procurement |
| Finance & HR | fees, payroll, recruitment |
| Community | messaging, notices, events, complaints, parent_meetings, health, discipline, alumni, transport |
| AI | ai |

## 3. Target deltas (in roadmap order)

1. **Payments:** a provider adapter interface (`ChamaGO`, `Daraja`) → verified webhook → `PaymentEvent` (raw, unique provider ref) → atomic ledger posting. Clients only read the status.
2. **Tenancy:** `core/tenancy.py` holding `TenantScopedViewSet`, `SchoolOwnedPrimaryKeyRelatedField`, and a `for_school()` queryset helper used by views, reports, exports and Celery tasks.
3. **Files:** `storage.PrivateFile` metadata (school, owner, classification), a private R2 bucket, short-lived signed URLs issued after a permission check, and public R2 + Cloudflare CDN for catalogue/3D assets.
4. **Finance ledger:** `LedgerEntry` (school, learner/account, debit/credit, source, reversal_of), which fees, shop fee-balance and transport billing post to.
5. **Booklist pipeline:** `ParentBooklistUpload` → Celery task → external OCR/LLM API → `ExtractedItem` (with confidence + catalogue match) → parent review → cart. Every AI output is stored and the confirmed values are stored separately.
6. **Automation:** n8n on a separate host. It consumes signed outbound webhooks from Django (domain events) and calls back only through authenticated, permission-checked API endpoints using a scoped service account.
7. **H5P:** a separate lightweight H5P host (e.g. Lumi/h5p-standalone static player for playback). Content packages live in R2. Django stores references and xAPI results.
