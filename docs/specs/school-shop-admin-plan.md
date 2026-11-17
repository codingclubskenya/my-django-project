# School shop and supplier administration: plan

Spec: `docs/specs/school-shop-admin.md` (gap IDs G1-G14, decisions D1-D8). Four phases, one session each, started only after school-data-management Phase 6 is finished and reviewed. Each phase ends the same way as the school-data phases: tests for touched apps, probe, commit (backend and frontend separately), report in `docs/specs/reports/shop-phase-N.md`, DB changes appended to `docs/specs/DATABASE-CHANGES.md`.

Ground rules for every phase: `makemigrations` only (data migrations hand-written, reversible, abort-before-write on bad data), `backend/venv_new/bin/python`, `core.settings_test`, narrowest tests, `graphify update .` from the repo root, no production changes without your go-ahead, `showmigrations` on prod before applying (CLAUDE.md).

## Phase 1: Foundations and approval backend (G1, G4, G5, G9, D1, D4)

- **Migrations**
  - `tenants`: `SchoolSettings.shop_enabled` (default False), `supplier_approval_delegated` (default False). Rule (D4): only the platform admin may set `shop_enabled` True; the school ADMIN may set it False only.
  - `distributor`: `SchoolSupplier` (school, distributor, status, requested_by, decided_by, decided_at, note; unique `(school, distributor)`; index on status).
  - `accounts`: data migration adding the `Procurement` group (like `0015`).
- **Code**
  - `accounts/permissions.py`: `can_manage_school_shop(user)` (ADMIN or Procurement, school-bound), `IsSchoolShopManager`, and `can_decide_supplier(user, school)` (platform admin always; school ADMIN/Procurement only if the flag is True).
  - `distributor/services.py`: `school_can_trade(school, distributor)`, `request_supplier`, `decide_supplier(actor, relation, action, note)` with `select_for_update`, status machine, `AuditLog` via `log_action`, `decided_by/at`.
  - `SchoolSettingsSerializer`: `supplier_approval_delegated` read-only unless platform admin; new platform-only action `PATCH /tenants/school-settings/{school}/delegation/`. `shop_enabled` writable by ADMIN.
  - `UserSerializer`: read-only `is_platform_admin`.
  - Platform admin API: list all relationships, decide any (`/distributor/school-suppliers/`, platform-only), plus the flag setter.
- **Tests**
  - Machine: every allowed and forbidden transition; rejected to pending re-request.
  - Rules: unverified or suspended supplier cannot be approved; global suspension overrides an APPROVED row and unsuspend restores it; delegation off gives 403 for school ADMIN and Procurement on decisions (request still works); delegation on lets both decide; teacher/STAFF/parent 403; platform admin always.
  - `supplier_approval_delegated` cannot be set by a school ADMIN (field ignored or 403) and can by the platform admin; `me` returns `is_platform_admin` true only for superusers.
  - Tenant: Demo ADMIN cannot read, decide or request on Rival rows (404); `TenantFKValidationMixin` rejects a foreign school id; audit row per change with before/after; double decision race test.
  - Migration: group created, idempotent, reverse.
- **Deliverable:** backend complete for the approval flow; nothing user-visible yet.

## Phase 2: School shop backend (G2, G3, G6, G7, G11-G14, D2, D3, D5-D8)

**Already shipped as a hotfix** (see spec section 11): G7 own-school orders, G2/G3 suspension filtering and order blocking, G6 for suppliers and stock. Phase 2 builds on it (approval gate, `shop_enabled`, shared catalogue, remaining procurement models via the Procurement group) and keeps the hotfix tests green.

- **Migrations:** `SchoolOrder.received_at`, `received_by` (generated). Optional index on `SchoolOrder(school, status, created_at)`.
- **New app `schoolshop`** (no models): `views.py`, `services.py`, `reports.py`, `urls.py` mounted at `/api/v1/school-shop/` (and `/api/auth`-style prefix if the project mounts both, as for the other apps).
- **Endpoints** (spec section 4): suppliers + request/decide + performance, catalogue + gated import, stock, purchase orders, sales orders, deliveries, receive, three reports with CSV.
- **Hardening of existing routes**
  - `DistributorProductViewSet`: school users see only currently tradeable approved suppliers' products (G2).
  - `ProductViewSet.import_from_distributor`: delegates to the gated catalogue import; `school_can_trade` required (G2).
  - `SchoolOrderViewSet` create/update: supplier must be tradeable; items must belong to that supplier; school scoping unchanged.
  - `PublicProductViewSet` and cart/checkout/guest order creation: delist suspended or unverified or unapproved supply; variant must belong to the order's school or the shared catalogue; `shop_enabled` required (G3, G7). Failing test first for the cross-school order (G7).
  - `procurement` viewsets: write access to ADMIN and Procurement only; teachers and STAFF lose write access (G6); update `accounts/test_write_access.py` accordingly.
  - Shared catalogue: `school IS NULL` products visible read-only to shop-enabled schools; writes platform-only (D3); shared items are an import source only (decision 7): parents never order them directly; `import_from_shared` already shipped.
  - Suspension flag (D8): `supplier_suspended` on supplier rows and `SchoolOrder` serializers so schools see affected suppliers and in-flight orders; in-flight orders remain completable.
  - **Bookshop/shop catalogue parity (root cause fix, see `reports/shop-plan-2.md`):** (1) **[shipped in hotfix 2]** `import_from_distributor` must create a `Default` `ProductVariant` (stock from the supplier's `available_stock`), copy `image`, `brand` (company name), `sku`, tags and set `applicable_levels` when mapped, so an imported product is complete the moment it exists; one-off `backfill_imported_listings` command (dry-run first) repairs existing variant-less/imageless imports. (2) Public product serializers always return a usable `variants[0]` (never empty) and expose `distributor_name`, `school` and `is_reseller_listing`. (3) One shared filter implementation on `/shop/public/` (`category`, `level`, `brand`, `min_price`, `max_price`, `q`, `school`) used by both pages, plus `GET /shop/public/facets/` (categories, brands, price bounds, counts) so /shop and /bookshop render identical filter options. (4) Replace the fixed 64-per-aisle cap by server-ranked results per aisle, with an `aisle` hint computed server-side from the category.
  - `preapprove_school_suppliers` management command: `--dry-run` is the default and prints the full school/supplier list with evidence; `--apply` writes APPROVED rows (with audit log). Never run against production without your go-ahead.
- **Tests:** per endpoint: scoping (Demo vs Rival), role matrix (ADMIN, Procurement, teacher, STAFF, parent, student, distributor, platform), delegation on/off, suspension override, receive adds stock once and is audited, performance and report numbers against a hand-computed fixture, CSV escaping, pagination `count`, parent storefront off and on, cross-school order rejected, in-flight orders survive suspension.
- **Deliverable:** full backend; API documented in the report.

## Phase 3: Frontends (G8-G10, hosting decision)

**Where the school view lives: `frontend/codingclubskenya`.** Reasons: school ADMIN, Procurement and parents already sign in there with school-scoped tokens; it has the shop pages (`ShopProducts`, `ShopCategories`, `ShopOrders`), `utils/permissions.js` and `user.groups` for gating, the shared `ImportDialog`, and the layout/sidebar. The distributor app is for suppliers, the public storefront and the platform operator; putting school roles there would mean a second school login and would put a school ADMIN one click from the platform panel.

- **codingclubskenya**
  - New "School Shop" section (sidebar gated by `canManageSchoolShop(user)`; parent view gated by the shop flag): Suppliers (status chips, request, approve/reject/suspend/reinstate buttons shown only when delegation allows, "approval is handled by the platform" message otherwise), Catalogue (import with markup), Stock (below-reorder highlight, receive), Purchase orders, Sales orders, Deliveries, Supplier performance, Reports (date range + CSV).
  - Parent "Shop" page: school storefront, cart, checkout against the existing order/pay APIs; "shop not available" state.
  - Settings: shop on/off for ADMIN; delegation shown read-only to school users.
  - Platform-operator controls (set delegation) are **not** here (see below).
- **distributor (bookshop and shop parity)**
  - Add `/bookshop` to `components/GlobalHeader.tsx` main nav and mobile menu (and `Header.tsx`); `/shop` and `/bookshop` link to each other (a "Browse in 3D" button on /shop, "Browse as list" on /bookshop), and the active filters travel in the query string both ways.
  - One filter module (`lib/catalogueFilters.ts`) and one `ProductCard` used by `/shop`, `/shop/[id]` and the 3D bookshop panels (`ui/ProductCard.jsx` becomes a thin wrapper); both pages read facets from `/shop/public/facets/` and send the same query params instead of filtering client-side over the full catalogue.
  - Bookshop `normalise()` must stop using the product id as `variantId` (use `variants[0].id`, skip items without one). Filters (category, level, brand, price, search) apply to what is shelved and to search results; "no matches" state and a visible "N of M products" count.
  - Bookshop shows an "unshelved" list for items its aisle rules drop (`NOT_SHELVED`, `Technology`, 64/aisle cap) so nothing from the catalogue is silently invisible.
- **distributor**
  - `lib/auth.tsx`: `is_platform_admin` on `User`. `app/admin/layout.tsx` and `app/admin/products/new/page.tsx` guard on it only; school ADMIN redirected; remove the `SUPER_ADMIN` check.
  - Admin panel: Schools tab for the platform admin (list schools, toggle `supplier_approval_delegated`, view and decide school-supplier relationships). Sellers pages keep global verify/suspend.
  - `app/dashboard/page.tsx`: render from `dashboard-summary` (counts from the API, revenue server-side); add the endpoint in Phase 2 or here as a small backend addition (decided at the start of this phase; it is tiny and tested).
  - Read `distributor/node_modules/next/dist/docs/` before writing Next code (AGENTS.md).
- **Checks:** `vite build` and `next build`/lint pass; local click-through with seed accounts only (rules in CLAUDE.md); the admin panel is unreachable for a school ADMIN account.

## Phase 4: Seed, probes, hardening, docs

- `seed_dev_users`: `distributor@demo.com`, `platform@demo.com`, `procurement@demo.com` (and rival-domain equivalents where needed), Rival Supplies approved only for Rival, Demo relationships in APPROVED / PENDING / REJECTED, one globally suspended supplier, orders and deliveries in both schools.
- `api_probe.py`: roles `distributor`, `platform`, `procurement`; the summary must show zero cross-school rows and no non-platform role reaching `approve|suspend|unsuspend|pending|suspended`, the delegation setter, wallet admin actions, or importing from an unapproved supplier.
- `scripts/shop_privacy_probe.py` (read-only, scratch copy): targeted assertions for Demo roles and Rival data; ADMIN without delegation cannot decide; parents see only their school's storefront; teacher gets 403 on all school-shop routes.
- End-to-end test of the three flows: platform verifies, school requests, (delegated) school approves, school imports and orders, delivery, receive into stock, report; global suspension mid-flow.
- Audit coverage review; export escaping review; `docs/specs/school-shop-admin-implementation.md`; update `DATABASE-CHANGES.md` with the production order of operations.

## Production notes (gather before deploying, none applied now)

- Migrations are additive (two booleans default False, one new table, one nullable field pair, one group): safe on a live DB; run `showmigrations` first.
- Behaviour change on deploy: schools lose access to supplier products until each relationship is approved (G2 is closed). Plan: platform admin bulk-creates APPROVED relationships for existing school/supplier pairs found in `SchoolOrder` and `Product.linked_distributor_product`, via a one-off reviewed management command run with your go-ahead, so nobody is cut off silently. List the pairs in the report first.
- Teachers lose procurement write access (G6): tell schools, or give them the `Procurement` group.

## Effort and risk

| Phase | Size | Main risk |
|---|---|---|
| 1 | medium | status machine and flag protection correctness |
| 2 | large | touching existing public/cart/order paths; regression in the storefront (run `shop`, `carts`, `storefront`, `distributor` suites) |
| 3 | large | two frontends; admin guard correctness |
| 4 | small to medium | probe coverage |
