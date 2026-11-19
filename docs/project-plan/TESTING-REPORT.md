# Learning Pack — Testing Report

## Run 4 — Stage 3: private files, fee ledger, throttles, carts (2026-11-12)

- Backend `fix/private-media` @ `8b8a1c2`: **193 passed, 0 failed.**
- New: `core/test_private_files.py` (20): classification guard for every file field, nginx/backend prefix agreement, rule matrix per file kind, tampered/swapped/expired tokens, deactivated user, X-Accel hand-off, dev media handler. `fees/test_ledger.py` (17): derived status, overpay/negative/zero, cross-school invoice, immutability (API + model), reversals, cancel, receipts, parent visibility. `carts/tests.py` +5: session-key rules, isolation from empty-key carts, quantity validation. `accounts/test_security.py` +2: one account gets 429 while others log in; 25 students from one IP all log in.
- Staff app `vite build` ✅ after the Fees changes.
- **Not verified:** nginx syntax (no nginx binary; `nginx -t` needed before reload). Real browser click-through of the new payment reversal UI and file links. A real M-Pesa sandbox payment. Release APK build: see below.


## Run 3 — Stage 2: uploads, tenant root, isolation sweep (2026-11-12)

- Backend `fix/stage2-tenancy-files` @ `1b86977`: **149 passed, 0 failed** (`core` added to `testpaths`).
- New: `core/test_tenant_isolation.py` (1 sweep test over 130 list endpoints, 115 scoped + 15 reviewed exceptions). **Mutation check:** patching the library mixin to return all schools' books makes the sweep fail and name all 3 library endpoints, so it detects real regressions.
- New: `core/test_stage2_security.py` (16 tests): valid files pass; spoofed extensions, SVG/HTML/exe/legacy doc, macro DOCX, non-Office zip, 20 MB zip bomb, oversize, empty, corrupt image and binary CSV are rejected; random paths strip traversal; students can't edit/delete the school; admins can't recode it or create schools; students can't change settings; parents can't list wallets; parents/students/teachers can't read applications.
- Frontend accept lists aligned with the server (storefront `d683c78`, staff `ac53cc4`). Not rebuilt (one-attribute changes).


## Run 2 — Critical security fixes (2026-11-12)

- **Backend** (`fix/critical-security` @ `02512d7`): `pytest` with the new `core.settings_test` (now the default in `pytest.ini`; `booklists`, `carts`, `storefront` added to `testpaths`) → **132 passed, 0 failed**.
  - New regression suites: `shop/test_payment_security.py` (18 tests: forged confirmation, PATCH-to-paid, guest token, retired webhook, wrong callback secret, forged callback rejected when Daraja disagrees, underpaid, duplicate callback idempotency, duplicate receipt, unlinked learner, staff-only fulfilment); `accounts/test_security.py` (14 tests: superuser escalation, cross-school create/move, platform-only roles, `is_staff` not cross-tenant, temp passwords in bulk import, API lock until password change, admin reset scoping, `reset_default_passwords`, `audit_superusers`, student login across schools); `booklists/test_security.py` (2 tests).
  - Previously failing tests fixed: gradebook fixture vs seeded data; website config list for school admins (restored the original create-default behaviour).
  - Daraja is **mocked** in tests. **No sandbox call to Safaricom has been made yet**; this needs sandbox credentials (see DEPLOYMENT-GUIDE).
- **`manage.py check --deploy`** with `core.settings_production`: no security warnings (only OpenAPI schema hints). It refuses to start without a strong `SECRET_KEY`.
- **Staff web app:** `vite build` ✅ (output to scratch dir, `dist/` untouched). oxlint shows no new errors.
- **Storefront (Next.js):** `tsc --noEmit` ✅ for all changed files; eslint shows no new errors. ⚠️ **`next build` not run**: local Node is 18.19 and Next 16 needs ≥ 20.9.
- **Flutter:** `flutter analyze` shows no issues in the changed/new files. ⚠️ APK not built or run on a device.
- **Not done:** manual end-to-end click-through of checkout, password change and bulk import in a browser or on a device.


## Run 1 — Baseline (2026-11-12)

- **Code under test:** backend `qa/hardening-fixes` **including uncommitted changes**, SQLite test DB
- **Command:** `pytest -q --ds=<core.settings + MD5 password hasher>`. The hasher override lived in a scratch settings module outside the repo; no repo files were changed.
- **Result:** **82 passed, 4 failed** in 116s. pytest collects 86 of the 98 `test_` functions, because `pytest.ini` `testpaths` omits `booklists`, `carts`, `storefront` and `procurement`.

| Failing test | Error | Likely cause |
|---|---|---|
| `gradebook/tests.py::LearnerRosterTests::test_patch_learner_report` | `IntegrityError: UNIQUE constraint failed: gradebook_corecompetency.code` | Test creates `CoreCompetency('COMM')` that a data migration already seeds. Fix: use `get_or_create`. |
| `website/tests.py::WebsiteConfigCRUDTests::test_get_config_creates_default` | `response.data` is a list, test expects an object | `/api/website/config/` returns a list (the uncommitted `website/views.py` change, or router behaviour). Endpoint and test disagree. |
| `website/tests.py::WebsiteConfigCRUDTests::test_get_config_returns_existing` | same | same |
| `website/tests.py::WebsitePermissionTests::test_cannot_access_other_school_config` | same | same. This is a tenant-isolation test, so it has to be fixed rather than skipped. |

### Performance note
- With the default PBKDF2 hasher, each test took about 9s (25 tests in 220s), so the full suite blows past a 10-minute limit. With the MD5 hasher the per-test cost is negligible.
- Of the 116s, **109s is test-DB setup** (migrations).
- Fixes:
  - add a `core/settings_test.py` with a fast hasher;
  - run pytest with `--reuse-db`;
  - add the missing apps to `testpaths`.

### Coverage gaps
- **Apps with zero tests:** fees, exams, transport, recruitment, courses, attendance, messaging, payroll, distributor, requirements, curriculum, homework, discovery, tenants, library-views, and 8 minor apps.
- **No tests for any SECURITY-AUDIT critical finding (C1–C4).** Each fix must land with a regression test.
- **No frontend tests** (staff React, Next.js) and no Flutter tests were run.
- **Not executed in this run:**
  - frontend builds (`npm run build`), `oxlint` / `eslint`
  - `flutter analyze` / `flutter build apk`
  - load tests
  - mobile responsiveness checks

### Journey testing status
| Journey | Status |
|---|---|
| Admin / school admin / teacher / staff / parent / student | Not tested (no E2E harness) |
| Booklist → order | Not testable (upload/extraction not built) |
| Finance & payment | Unit only (`shop` commission + fee-balance tests pass). The payment-confirmation path is insecure (C1–C3). |
| Transport, courses, exams | Not tested |
| Android APK | Not built |
