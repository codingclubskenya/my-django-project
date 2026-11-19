# Learning Pack — Security Audit

- **Date:** 2026-11-12
- **Scope:** `backend/` (Django 6.0.7 / DRF 3.17.1, branch `qa/hardening-fixes` incl. uncommitted work), `distributor/` (Next.js storefront + 3D), `frontend/codingclubskenya/` (staff React app), `frontend/parents/` (Flutter), `deploy/` + `nginx/`.
- **Method:** Static review of code and config, Django system checks under both settings modules, OpenAPI schema generation, and AST scan of every ViewSet/APIView for tenant scoping. **No live/production testing was performed.** Production observations marked *(reported)* come from `IMPROVEMENT_PLAN.md` Appendix A (SSH inspection, Oct 2026) and were not re-verified.
- **Status legend:** Open / Fixed / Accepted risk

## Summary

| Severity | Count | Theme |
|---|---|---|
| Critical | 4 | Payments can be marked paid without the provider. School admin can escalate to platform superuser or create admins in other schools. |
| High | 7 | Private uploads are publicly served, uploads aren't validated, default passwords are used, and some endpoints leak data across tenants or roles. |
| Medium | 9 | Hardening, config drift, financial immutability, token storage |
| Low / Info | 6 | Hygiene |

What is already good: ORM is used throughout (the only raw SQL, `discovery/views.py:66,135` `.extra()`, is parameterised). There is no `eval`/`pickle`/`subprocess`/`shell=True`. `.env` is git-ignored. Repo `settings.py` defines DRF throttles. The `audit` app wires `post_save`/`post_delete` signals onto sensitive models. Most tenant data is scoped by `request.user.school` via `SchoolScopedViewSetMixin`. AI recruitment endpoints check `school` on the object.

---

## Remediation status (2026-11-12)

Backend branch `fix/critical-security` (commit `02512d7`), storefront `fix/verified-payments` (`2ff7fb6`), frontend `fix/temporary-passwords` (`adca15b`). **Not yet deployed.**

| ID | Status | Fix | Regression tests |
|---|---|---|---|
| C1 | ✅ Fixed | Payments confirmed only via Daraja (callback re-verified by STK query, or server-side status query). Manual confirm is finance staff only, with receipt + reason. Parents can't PATCH orders; nobody can PATCH an order to `paid`. | `shop/test_payment_security.py` |
| C2 | ✅ Fixed | Guest orders by UUID `public_token`, guest-only queryset, `force` removed, throttled | same |
| C3 | ✅ Fixed | ChamaGO webhook returns 410. New Daraja callback on a secret URL with optional IP allow-list, amount check, unique receipt, row locks, raw `MpesaCallbackLog`. | same |
| C4 | ✅ Fixed | `is_staff`/`is_superuser` read-only, school forced to the creator's, platform-only roles guarded | `accounts/test_security.py` |
| **C5 (new)** | ✅ Fixed in code; **data clean-up pending** | `tenants/admin.py` "Create school with admin" made every school admin a **superuser**, i.e. cross-tenant. It no longer does. `manage.py audit_superusers [--demote --keep <ops email>]` fixes existing accounts. | `accounts/test_security.py` |
| **C6 (new)** | ✅ Fixed | Parents could PATCH their own order's `status`/`total_amount`, and order for any learner id (then charge that child's fees) | `shop/test_payment_security.py` |
| **H8 (new)** | ✅ Fixed | Booklists: any school's ADMIN could edit or delete other schools' published booklists and see their drafts; public read was broken | `booklists/test_security.py` |
| H3 | ✅ Fixed in code; **rotation pending on prod** | Random temporary passwords + `must_change_password` enforced in JWT auth. Change-password and admin reset endpoints. `manage.py reset_default_passwords` covers Pass@1234 / Teacher@1234 / Learner@1234 / admin123 / 1234. | `accounts/test_security.py` |
| H4 | ✅ Fixed | Form submissions: platform admins only. Cross-tenant checks now use `is_superuser`, not `is_staff` (website, distributor, form submissions). | `accounts/test_security.py` |
| H6 | 🟡 Partly | Scoped throttles (login, password reset, payment, guest checkout). Prod settings now inherit them. nginx `limit_req` still to do. | — |
| M1 | ✅ Fixed for prod | `settings_production` fails closed without a strong `SECRET_KEY`, `DEBUG=False` | manual check |
| **M10 (new)** | ✅ Fixed | Student login crashed (500) when two schools shared an admission number, and wasn't throttled | `accounts/test_security.py` |
| **C7 (new)** | ✅ Fixed (stage 2) | `tenants.SchoolViewSet`: **any logged-in user (incl. students) could PATCH or DELETE their School**, which is the tenant root and cascades every record. Any user could also create schools or edit school settings. Now: update = school ADMIN (`code`/`is_active` platform-only); create/delete = platform admin. | `core/test_stage2_security.py` |
| **H9 (new)** | ✅ Fixed (stage 2) | Distributor wallets (balances, earnings) were listable by every non-distributor user | same |
| **H10 (new)** | ✅ Fixed (stage 2) | Recruitment: applications, CVs, offers and notes were readable by any role in the school (parents, students). Now ADMIN/STAFF; interviews/scorecards also TEACHER. Public form: server-side deadline (it used to crash or be spoofable), throttled. | same |
| **H11 (new)** | ✅ Fixed (stage 2) | Scheme of work upload/generate fetched learning area, term and stream from any school (IDOR) | sweep + manual |
| H2 | ✅ Fixed (stage 2) | `core/uploads.py` on every File/ImageField and direct `request.FILES` use: magic bytes vs extension, Pillow verify, OOXML structure/macro/zip-bomb checks, text checks, size limits; SVG/HTML/legacy `.doc`/`.xls` rejected; private files get random names | `core/test_stage2_security.py` (10 validator tests) |
| H5 | ✅ Fixed (stage 2) | AI recruitment endpoints ADMIN/STAFF, moderation staff roles; report narratives exclude DRIVER/DISTRIBUTOR; all AI endpoints throttled | same |
| H6 | 🟡 More done | Public application and form-submission throttles. **R1 regression fixed:** global anon rate was 100/day per IP (would block guest browsing behind NAT), now 1200/h. nginx `limit_req` still open. | — |
| M5 | ✅ Fixed (stage 2) | `core/test_tenant_isolation.py` sweeps all 130 list endpoints and fails on any unscoped tenant-owned queryset. Verified by mutation (removing the library filter makes it fail). | itself |
| H1 | ✅ Fixed (stage 3) | Private files (CVs, submissions, evidence, internal documents, dispute/form files) are no longer under public `/media/`. Serializers emit 10-minute signed links bound to the requesting user; the download view re-checks permission for that user at download time; production hands off to nginx (`X-Accel-Redirect`). nginx returns 404 for the private prefixes. A test fails if a new upload field isn't classified public/private. **Needs deploy steps:** nginx reload + `PRIVATE_MEDIA_ACCEL_PREFIX=/protected-media/`; nginx syntax unverified. | `core/test_private_files.py` (20) |
| M2 | ✅ Fixed (stage 3) | Fee payments are append-only (model + API); corrections via admin-only reasoned reversal entries; invoice status/paid_at derived from the ledger. Also fixed: payments against other schools' invoices, spoofable `recorded_by`, overpayment/negative amounts, receipts crashing without a fee structure, shop fee-balance merging into the first invoice. Receipt popup escaped (XSS). | `fees/test_ledger.py` (17) |
| M4 | ✅ Fixed | Dead `TenantMiddleware` removed | — |
| M8 | 🟡 Partly | AI default model id updated. `anthropic==0.49.0` pin and install not touched. | — |
| M9 | ✅ Fixed | Guest carts need a valid session key; empty-key carts can't leak; quantity validated | `carts/tests.py` (5) |
| **R1 follow-up (new)** | ✅ Fixed | The login throttle I added in R1 was per IP (10/min): a school behind one NAT would lock out a class. Now per IP+account with a loose per-IP ceiling. `NUM_PROXIES=1` in prod so `X-Forwarded-For` can't be spoofed to evade throttles. | `accounts/test_security.py` |
| H6 | ✅ Done | + nginx `limit_req` (30 r/s/IP, burst 100) in both configs (unverified syntax) | — |
| H7 | 🟡 Prepared | Release signing reads `android/key.properties`-style `key.properties`; falls back to the debug key with a warning **so nothing changes until you create a keystore**. Switching keys stops existing installs from updating. Manifest: `allowBackup=false`, explicit INTERNET, cleartext off. `applicationId` is still `com.example.parents` (changing it also breaks upgrades): decision needed. | build in progress |
| M3, M6 | ⏳ Open | M3 tokens in `localStorage` (needs an httpOnly-cookie design); M6 axes only active in production settings | — |
| M7 | ⛔ Needs SSH | Server hardening (socket umask, Celery, phpMyAdmin) | — |

## Critical

### C1 — Any order owner can mark their own order **paid** without paying
- **Where:** `backend/shop/views.py:470` `OrderViewSet.confirm_payment` (permission: `IsAuthenticated`; queryset gives a parent their own orders).
- **Exploit:** Parent creates an order, calls `pay_mpesa` (creates `Payment` status `initiated`), ignores the STK prompt, then `POST /api/shop/orders/{id}/confirm-payment/`. Order becomes `paid`, `credit_for_payment` credits distributor wallets.
- **Called by:** `distributor/lib/api.ts:288`, `distributor/lib/storefrontApi.ts:68` — the storefront *relies* on client-side confirmation.
- **Fix:** Confirmation must come only from a verified provider callback or a server-side status query to the provider. Restrict the endpoint to finance staff, require a reason, and write an audit record. Replace the client call with polling of a read-only payment-status endpoint.

### C2 — Anonymous guest-order takeover: read any guest order + force-confirm it
- **Where:** `backend/shop/views.py:603` `GuestOrderViewSet` (`AllowAny`, `queryset = Order.objects.all()`, lookup by sequential integer `pk`); `confirm_payment` at `:665` accepts `{"force": true}`, which skips the `checkout_request_id` check.
- **Exploit:** `GET /api/shop/guest-orders/1..N/` enumerates **every** order (not just guest orders), exposing names, phones and delivery addresses. `POST .../confirm-payment/ {"force": true}` marks any order paid. `pay_mpesa` can also trigger STK pushes to arbitrary orders.
- **Fix:** Limit the queryset to `parent__isnull=True`. Look orders up by an unguessable token (UUID or signed token returned at creation), not `pk`. Remove `force`. Same verified-confirmation rule as C1. Throttle per IP.

### C3 — ChamaGO payment webhook is unauthenticated
- **Where:** `backend/shop/views.py:701` `chama_webhook` (`AllowAny`, `csrf_exempt`).
- **Exploit:** Anyone who knows or observes a `transaction_id` (the `mpesa_checkout_request_id`, also returned to browsers by `pay_mpesa`) can POST `{"event":"deposit.received","transaction_id":...}` and the order is marked paid. There is no signature check, no amount check, and no source-IP allow-list.
- **Fix:**
  - Verify the provider signature or shared secret, using whatever mechanism ChamaGO documents. **This needs ChamaGO's docs.**
  - Check `amount == payment.amount`.
  - Enforce idempotency on the provider transaction code with a unique constraint.
  - Process inside `transaction.atomic()` with `select_for_update`.
  - Log the raw event.
  - Optionally allow-list provider IPs at nginx.

### C4 — School ADMIN → platform superuser / cross-tenant admin creation
- **Where:**
  - `backend/accounts/serializers.py:39`: `UserSerializer` exposes `role`, `school`, `is_staff`, `is_superuser` and `is_active` as **writable** (only `id`, `created_at` and `last_login` are read-only).
  - `backend/accounts/serializers.py:106`: `UserCreateSerializer` accepts `school` and `role`.
  - `backend/accounts/views.py` `UserViewSet.perform_create` saves the client-supplied `school` when one is given.
- **Exploit:**
  1. A school ADMIN can `PATCH /api/auth/users/{own id}/ {"is_superuser": true, "is_staff": true}`. They then see all schools' data, because many querysets short-circuit on `is_superuser`, and they get Django admin access.
  2. They can also `POST /api/auth/users/ {"role":"ADMIN","school":<other school id>,...}` to plant an admin in another tenant.
- **Fix:**
  - Make `is_superuser`, `is_staff` and `school` read-only for every non-superuser.
  - Always force `school = request.user.school` on create.
  - Validate `role` against an allow-list per actor (an ADMIN cannot mint superusers; nobody can self-change their role).
  - Add regression tests.

---

## High

| ID | Finding | Where | Fix |
|---|---|---|---|
| H1 | **Private files are publicly downloadable.** nginx serves `/media/` with no auth, and `MEDIA_ROOT` holds resumes, student submissions, assessment evidence, dispute evidence and form uploads. Paths are date-based and use original filenames, so they're guessable. | `deploy/nginx/school_management:74`; `recruitment/models.py:60`, `courses/models.py:107,164,281`, `assessment/models.py:123`, `shop/models.py:166,245` | Split storage into public (catalogue images, logos) and private. Store private files in R2 (private bucket), or serve them via `X-Accel-Redirect` behind a Django permission check. Use random object keys and short-lived signed URLs. |
| H2 | **No upload validation** on 16 of 17 File/ImageFields. Only `website` images use `FileExtensionValidator`. No size limits, no magic-byte check, no filename sanitising beyond Django's default. `client_max_body_size 50M`. | All `FileField`s listed above | A shared `validate_upload(kind)` that checks extension allow-list, magic bytes, max size per kind, and rejects macro-enabled Office files and SVG. Re-encode images with Pillow. Serve private files with `Content-Disposition: attachment` and `X-Content-Type-Options: nosniff`. Use the same validator for the booklist uploads planned in roadmap B. |
| H3 | **Hard-coded default password `Pass@1234`** for bulk-imported students and auto-created parents. | `backend/accounts/views.py:169,230` | Generate random passwords or issue one-time activation links, and force a reset on first login. Rotate existing accounts that still use the default (needs an approved data migration). |
| H4 | **Cross-tenant read of public form submissions.** Any school `ADMIN` (or `is_staff`) lists *all* schools' submissions. | `backend/shop/views.py:758` | Scope to `school`, or restrict to superusers/platform staff. |
| H5 | **AI recruitment endpoints open to any role in the school** (parents/students can request resume screening summaries and interview questions). | `backend/ai/recruitment_ai.py:53,91,130` (`IsAuthenticated` only) | Restrict to ADMIN/HR roles. Log every AI suggestion (the brief already requires this). |
| H6 | **Repo production settings lack DRF throttling** (dev `settings.py` has it). Production is also reported to lack nginx `limit_req`. Public endpoints include guest checkout, careers application, form submissions, login and password reset. | `backend/core/settings_production.py` | Port `DEFAULT_THROTTLE_*` into prod. Add scoped throttles for login, password-reset, guest-order, application and webhook. Add nginx `limit_req`. |
| H7 | **Flutter release build signed with the debug key.** | `frontend/parents/android/app/build.gradle.kts:35-38` | Create an upload keystore (kept out of git) and use Play App Signing. |

## Medium

| ID | Finding | Where | Fix |
|---|---|---|---|
| M1 | Insecure fallbacks in `settings.py`: hard-coded `SECRET_KEY` default, `DEBUG` defaults to `True`, `ALLOWED_HOSTS` defaults to `['*']`. If prod ever loads `core.settings` with a missing env var, it runs in debug. | `backend/core/settings.py:13-22` | Fail closed: no default secret, `DEBUG=False` by default. |
| M2 | Fee `Payment`/`Invoice` are full `ModelViewSet`s: STAFF can edit or delete posted payments. That breaks the "no silent overwrite of financial records" rule. | `backend/fees/views.py:23,69` | Make posted payments immutable and add reversal/adjustment entries. |
| M3 | JWTs are stored in `localStorage`, so any XSS can steal tokens. Tokens are read ad hoc in several pages. | `frontend/codingclubskenya/src/services/api.js:18-39`, `Students.jsx:161`, `SchemesOfWork.jsx:35`, `Homepage.jsx:162` | Short-term: centralise in `api.js` and add a CSP. Longer-term: httpOnly refresh cookie plus in-memory access token. |
| M4 | `TenantMiddleware` stores the school in a **module-level dict** (not thread-local). It also runs a DB query on every request, keyed on the host's first label. It's harmless only because nothing reads `get_current_school()`. | `backend/tenants/middleware.py` | Remove it, or rewrite it with `contextvars` if subdomain tenancy is adopted. |
| M5 | **Tenant isolation is enforced per view**, by four copies of `SchoolScopedViewSetMixin` (accounts, academics, library, procurement) plus ad-hoc `get_queryset`s. Write-side FK validation is inconsistent, e.g. linking a `stream` id from another school. `user.school is None` users filter to `school=None`. | 112 `get_queryset`s across apps | One shared mixin plus a serializer `SchoolOwnedRelatedField` that limits FK choices to the user's school. Add a cross-tenant test suite (school A token vs school B ids) per endpoint. |
| M6 | django-axes is configured only in prod settings, so brute-force behaviour isn't exercised in dev or tests. | `core/settings_production.py:41,59,103` | Enable in both and add a test. |
| M7 | Production ops issues *(reported, not re-verified)*: gunicorn `--umask 000` world-writable socket, Celery not running, `django_redis` missing, phpMyAdmin exposed at `/pma/`, no CSP/Referrer-Policy/Permissions-Policy, `MemoryMax=infinity`. | `IMPROVEMENT_PLAN.md` App. A | Verify on the server, then fix (see DEPLOYMENT-GUIDE). |
| M8 | AI client defaults to a retired model id (`claude-3-5-sonnet-20240620`) and the pinned `anthropic==0.49.0` is old. AI features silently degrade to keyword stubs. | `backend/ai/client.py:37`, `requirements.txt` | Update the SDK and model id when AI work starts. Surface "AI unavailable" explicitly. |
| M9 | Unauthenticated guests cannot write to carts (`IsAuthenticatedOrReadOnly`) even though guest carts are modelled. It's a functional bug, not an exposure, but it encourages workarounds. | `backend/carts/views.py:15,53` | Allow anonymous writes scoped by a server-issued session key. |

## Low / Info

- L1 — `.extra()` in `discovery/views.py:66,135` is parameterised (safe) but deprecated; replace with a JSONField lookup.
- L2 — dj-rest-auth registration views fail to import (`User has no field named 'username'`). Registration is therefore not exposed, which is fine, but the warnings hide real schema issues.
- L3 — `core/urls.py:12` hard-codes a developer home path for `FRONTEND_DIST_DIR`.
- L4 — The same API is mounted twice (`/api/` and `/api/v1/`, 434 paths each). That doubles the attack surface to review, though not to exploit.
- L5 — `website` uploads allow GIF without re-encoding.
- L6 — ClassroomIO (`frontend/classroomio`) is **AGPL-3.0**. Modifying it and serving it over a network obliges you to publish the source. This is a licensing risk, not a vulnerability; get a decision before integrating it.

## Not yet assessed (gaps)

- **Dependency CVEs:** `pip-audit` isn't installed in the venv, and `npm audit` returned no data (likely offline). Both need a run with network access, added to CI.
- **Live production:** headers, TLS, open ports, DB user privileges (least privilege), backup existence and restore test.
- **Flutter:** certificate pinning, `flutter_secure_storage` options, exported Android components, FCM token handling.
- **Per-endpoint object-level authorisation** beyond the tenant filter, e.g. teacher → only assigned classes, parent → only linked children. This needs the cross-tenant/role test suite (M5).
- **Data Protection Act 2019** consent/retention flows: not implemented, so a policy decision is needed.

## Remediation order

1. C1–C4 (one PR, with regression tests), coordinated with the storefront change to stop calling `confirm-payment`.
2. H1, H2 (storage split + upload validator). These are prerequisites for booklist uploads.
3. H3–H7, M1, M2.
4. M5 cross-tenant test harness, then the rest.
