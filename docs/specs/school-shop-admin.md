# School shop and supplier administration: spec

Status: draft for approval. No code yet. Written 2026-11-15 on branch `feat/school-data-management`; build after the school-data-management phases (see the plan).

## 1. Goal

A school can run its own shop from its own suppliers, and a platform operator controls which suppliers exist at all.

- **Two-level supplier approval.** The platform verifies a supplier globally. Each school then decides whether to trade with that supplier.
- **School-scoped shop management** for the school ADMIN and the `Procurement` group: suppliers, catalogue, stock, orders, deliveries, supplier performance, purchase and sales reports. Strictly their own school.
- **Parents** browse and order from their own school's shop when the school has enabled it.
- **Global distributor admin panel** (`distributor/app/admin`) is for the platform admin only.
- The distributor dashboard shows true totals, not the length of the first page.

## 2. Roles and rules

| Actor | Can do |
|---|---|
| Platform admin (`is_platform_admin(user)`, i.e. `is_superuser`) | Verify, suspend, unsuspend a `DistributorProfile` (already true). Set `supplier_approval_delegated` for any school. Decide any school-supplier relationship. See everything (the only cross-school role). |
| School ADMIN | Decide school-supplier relationships **only when** that school's `supplier_approval_delegated` is True. Manage everything in section 4 for their own school. Disable (never enable) the school's own shop via `shop_enabled`. |
| `Procurement` group member (school-bound) | Same as school ADMIN for sections 3 and 4 (not `shop_enabled`, not school settings). |
| Distributor (role DISTRIBUTOR) | Own profile, products, orders, deliveries, wallet (existing). Sees which schools approved them; cannot approve themselves. |
| Parent | Browse and order from their own school when `shop_enabled`. Own orders only. |
| Teacher, STAFF, student | No shop-management access (today a teacher can write procurement suppliers; that is closed, see 6). |

Rules that must hold everywhere, enforced server-side by one helper `school_can_trade(school, distributor)`:

1. A school may approve a supplier only if the supplier is `is_verified` and not `is_suspended`.
2. A school-supplier relationship counts as active only when its status is APPROVED **and** the supplier is currently verified and not suspended. Global suspension overrides school approval **without rewriting the school's row**, so unsuspending restores it.
3. If `supplier_approval_delegated` is False, school users cannot approve, reject or suspend; only the platform admin decides for that school. They can still request a supplier (status PENDING) and see the status.
4. Only the platform admin can change `supplier_approval_delegated` (the school settings serializer makes it read-only for everyone else; a dedicated platform-only action sets it).
5. Every state change writes an `AuditLog` row (before/after status, actor, school, supplier, note) and stamps `decided_by` / `decided_at`.
6. Every queryset is scoped to `request.user.school`; the platform admin is the only exception. Every FK in a write payload goes through `TenantFKValidationMixin`.

### School-supplier status machine

`PENDING` (school or platform requests) goes to `APPROVED` or `REJECTED` (decider). `APPROVED` goes to `SUSPENDED` (decider) and `SUSPENDED` back to `APPROVED`. `REJECTED` goes back to `PENDING` (school re-requests, new note). Anything else is a 400. Decisions use `select_for_update` so two deciders cannot race. Each transition needs a permitted actor per the table above and rule 3.

## 3. Gap analysis (what exists vs what is missing)

Graph checked first: `graphify-out/graph.json` has 6134 nodes (more than 3000). Findings below were then confirmed in the source.

### Exists

| Area | Where | What it gives us |
|---|---|---|
| Global supplier | `distributor.DistributorProfile` (`is_verified`, `is_suspended`) | Global verification already platform-only: `approve`, `suspend`, `unsuspend`, `pending`, `suspended` actions use `IsPlatformAdmin`. |
| Supplier catalogue | `distributor.DistributorProduct` (price, stock, min order, bulk pricing) | Supplier-side products. |
| School purchasing | `distributor.SchoolOrder`, `SchoolOrderItem`, `Delivery` (status, tracking, ETA, delivered_at) | Orders from a school to a supplier, with deliveries. Scoped to `school=user.school`. |
| Supplier wallet | `DistributorWallet`, `WalletTransaction` | Commission credits. |
| School shop | `shop.ProductCategory`, `Product` (school FK, `linked_distributor_product`, markup, commission), `ProductVariant` (stock), `Order`, `OrderItem`, `Payment` (M-Pesa) | Parent orders with escrow (`fund_status`), disputes, pickup codes. `Product.school` is nullable. |
| Cart | `carts.Cart`, `CartItem` | Parent cart on variants. |
| Procurement | `procurement.Supplier` (per-school, free text, `is_approved` flag), `PurchaseOrder` (multi-step approval chain), `GoodsReceived`, `StockItem`, `Asset` | School-internal purchasing and inventory. Not linked to platform suppliers. |
| Settings | `tenants.SchoolSettings` (one row per school; ADMIN writes) | Place for flags. |
| Audit | `audit.AuditLog`, `log_action`, central field exclusions | Reuse for every decision. |
| Platform-admin helper | `is_platform_admin`; `/auth/users/me/` returns `is_superuser` | Reuse. |
| Groups | `Registrar`, `Principal`, `HR`, `Finance` etc. with `in_school_group` / `_admin_or_groups` helpers in `accounts/permissions.py` | Pattern for `Procurement`. |
| Frontends | `codingclubskenya`: `ShopProducts`, `ShopCategories`, `ShopOrders`, `Requirements`, `ParentRequirements`. `distributor` (Next.js): public storefront, distributor dashboard, platform admin (`app/admin/*`: products, orders, sellers, sellers/pending, payments, withdrawals, users, reports...). | Both exist; neither has a supplier-approval or school procurement view. |

### Missing or wrong

| # | Gap | Evidence |
|---|---|---|
| G1 | **No school to supplier relationship.** Nothing records that a school trades with a distributor. | `SchoolOrder` has `school` and `distributor` but no approval; no join model. |
| G2 | **Any school can use any verified supplier.** `DistributorProductViewSet` lists all verified products to every school user, and `ShopProduct.import_from_distributor` lets any school ADMIN import any verified product. Neither checks `is_suspended` or school approval. | `distributor/views.py` (`distributor__is_verified=True` only), `shop/views.py` `import_from_distributor`. |
| G3 | **Global suspension does not delist.** A suspended distributor's products stay in the anonymous catalogue and in school imports. | `PublicProductViewSet.get_queryset` filters only `is_active`. |
| G4 | **No `supplier_approval_delegated` or `shop_enabled` flags.** | `SchoolSettings` has neither; `SchoolSettingsViewSet` lets the school ADMIN write every field (so a platform-only flag needs explicit protection). |
| G5 | **No `Procurement` group.** | Only Registrar, Principal, HR, Finance, Health groups exist. |
| G6 | **Procurement permissions too wide.** `SupplierViewSet`, `PurchaseOrderViewSet`, `StockItemViewSet` use `IsAdminOrStaffOrTeacher`: a teacher can create suppliers and stock. | `procurement/views.py`. |
| G7 | **Parents can order across schools and when the shop is off.** `OrderCreateSerializer` checks the learner's school but not that each variant's product belongs to that school; no `shop_enabled` check. To be proven by a failing test first. The public catalogue lists every school's products anonymously. | `shop/serializers.py` (create), `PublicProductViewSet`. |
| G8 | **Admin panel guard lets a school ADMIN in.** `distributor/app/admin/layout.tsx` allows `role === 'ADMIN'` or `'SUPER_ADMIN'` (no such role exists in the backend) and `app/admin/products/new/page.tsx` repeats it. A school ADMIN logs in with role ADMIN. The backend is the real gate but the UI should not render. The frontend `User` type has no platform flag. | `distributor/app/admin/layout.tsx:147`, `lib/auth.tsx`. |
| G9 | **`/auth/users/me/` has `is_superuser` but no explicit `is_platform_admin`.** Frontends should guard on a purpose-named field, not on a Django flag. | `UserSerializer.fields`. |
| G10 | **Dashboard totals are wrong.** `distributor/app/dashboard/page.tsx` counts `products.filter(...)`, `orders.filter(...)` and sums revenue over the first page returned (`.results || data`). | `app/dashboard/page.tsx:65-69`. |
| G11 | **No school stock link.** `procurement.StockItem` (consumables) and `shop.ProductVariant.stock_quantity` (sale stock) are unrelated; receiving a delivered `SchoolOrder` updates neither. `SchoolOrder` has no received state. | models. |
| G12 | **No supplier performance or purchase/sales reports.** | none. |
| G13 | **No shared catalogue.** `Product.school` is nullable but nothing creates or serves school-less products; school queries use `school=user.school`. | `ProductViewSet.get_queryset`. |
| G14 | **Two supplier concepts.** `procurement.Supplier` (local vendor, free text) vs `DistributorProfile` (platform supplier). | models. |

### Decisions on the overlaps (proposed defaults; say if you disagree)

- **D1 New join model `distributor.SchoolSupplier`** (school, distributor, status, requested_by, decided_by, decided_at, note; unique school+distributor). Lives in the `distributor` app next to `SchoolOrder`. Not on `procurement.Supplier`.
- **D2 Keep `procurement.Supplier` as the school's local, off-platform vendor list** and fix its permissions (G6). Platform suppliers are traded through `SchoolSupplier` + `SchoolOrder` + `Delivery`. No data merge. The school-shop UI shows both lists, labelled.
- **D3 (decided: keep) Shared catalogue = active `Product` rows with `school IS NULL`**, created and edited by the platform admin only, visible read-only to every shop-enabled school. Schools build their own listing by importing from approved suppliers (existing import action, now gated). Parent checkout of a shared item is a Phase 2 decision (the G7 hotfix allows own-school listings only).
- **D4 (decided) The platform enables the shop; the school ADMIN may only disable it.** `shop_enabled` defaults False; setting it True is platform-admin only, setting it False is allowed to the school ADMIN (and platform). Re-enabling after a school disable needs the platform. `supplier_approval_delegated` is platform-only (default False).
- **D5 Stock:** no new inventory model. "Receive" on a delivered `SchoolOrder` stamps `received_at/received_by` and adds quantities to the matching school `ProductVariant.stock_quantity` (listings linked to that distributor product) or to a `StockItem` (by name) otherwise. Every receive is audited. School inventory view = both tables.
- **D6 Performance is computed, not stored:** per approved supplier and period: orders, fulfilment rate, cancellations, average days order to delivered, on-time rate against `estimated_delivery`, disputes on linked parent orders.
- **D7 New app `schoolshop`** (views, services, reports, permissions glue only, no models). New models are limited to `SchoolSupplier` (distributor app), two settings flags (tenants), `SchoolOrder.received_at/received_by`.
- **D8 (decided) Suspended supplier:** no new orders, imports or catalogue/storefront listings (hotfix shipped for orders, imports, catalogues and the anonymous storefront). Orders in flight stay visible and can finish (completed or cancelled). Affected schools are flagged: the school-shop supplier list and each in-flight order show a "supplier suspended" marker (Phase 2 field `supplier_suspended` on supplier rows and `SchoolOrder` serializer; Phase 3 banner).

## 4. School shop management (for ADMIN and Procurement, own school only)

All under `/api/v1/school-shop/`. Permission `IsSchoolShopManager` (= ADMIN or `Procurement` group, school-bound; platform admin allowed). Each list is `school=request.user.school`, paginated, with a `count`.

| Area | Endpoints (new unless noted) |
|---|---|
| Suppliers | `GET suppliers/` (all verified suppliers with this school's relationship status, rule 2 applied); `POST suppliers/{distributor}/request/`; `POST suppliers/{id}/approve|reject|suspend|reinstate/` (rules 1-3). `GET suppliers/{id}/performance/`. |
| Catalogue | `GET catalogue/` = products of currently tradeable approved suppliers (`DistributorProduct`) + the shared catalogue; `POST catalogue/import/` replaces the ungated `import_from_distributor` (calls `school_can_trade`). The school's own listings stay on the existing `shop/products` API. |
| Stock | `GET stock/` (variants + `StockItem`, with below-reorder flag); `POST orders/{id}/receive/` (D5). |
| Orders | `GET purchase-orders/` (`SchoolOrder`, create/cancel only for tradeable suppliers); `GET sales-orders/` (shop `Order` for the school: status, fund status, disputes). |
| Deliveries | `GET deliveries/`, filters by status/supplier. |
| Reports | `GET reports/purchases/`, `reports/sales/`, `reports/suppliers/` with `from`, `to`, `format=csv` (CSV through `core.imports.tabular_response`, so formula escaping applies). |

Existing `shop/products`, `shop/categories` and `shop/orders` stay for day-to-day shop admin. Today they use `IsAdminOrReadOnly`, so a Procurement member could not write there; Phase 2 swaps in `IsSchoolShopManager` for these three so ADMIN and Procurement behave the same.

## 5. Parents

- `GET /api/v1/school-shop/storefront/`: the parent's school only, only when `shop_enabled`, only listings whose supplier is currently tradeable (or the school's own and shared products). 404 or empty with a clear message when the shop is off.
- Order creation (`OrderCreateSerializer`, cart checkout, guest orders): each variant must belong to the order's school (never a school-less product, decision 7), the school must have `shop_enabled` (platform-enabled, D4), and reseller listings must pass `school_can_trade`. This closes G7.
- `PublicProductViewSet` (anonymous): filter out listings whose distributor is not verified or is suspended (G3). **Decided:** the anonymous storefront stays global (all schools' active listings), minus suspended or unverified supply. Per-school storefronts remain out of scope.

## 6. Global distributor admin panel

- Add `is_platform_admin` (read-only, computed) to `UserSerializer` and so to `/auth/users/me/`. Keep `is_superuser` as is.
- `distributor/lib/auth.tsx`: add `is_platform_admin: boolean` to `User`. `app/admin/layout.tsx` and `app/admin/products/new/page.tsx` guard on `user.is_platform_admin` only (drop the `ADMIN`/`SUPER_ADMIN` role checks). A school ADMIN is redirected.
- Audit every backend call made by `app/admin/*` (`lib/adminApi.ts`): each must be either platform-only or school-scoped; any that a school ADMIN could use to reach a global action gets `IsPlatformAdmin`. Add a probe check (section 8).
- `procurement` permission tightening (G6): suppliers, purchase orders, stock, assets writable by ADMIN and `Procurement` only; teachers and STAFF read nothing they do not need.

## 7. Distributor dashboard totals

- Use the API `count` for list totals; never `array.length` of one page.
- Items that need a filtered total (active products, pending orders) use either the filter on the list call and its `count`, or a new `GET /api/v1/distributor/dashboard-summary/` (distributor-scoped) returning `{products_total, products_active, orders_total, orders_pending, revenue, deliveries_pending}`. Revenue is summed server-side. Proposed: the summary endpoint (one request, correct for any size).
- `app/dashboard/page.tsx` renders from the summary; the recent-orders table still uses the first page and says "latest".

## 8. Security requirements

- `TenantFKValidationMixin` on every new serializer that takes an FK; `SchoolSupplier` serializers expose `status` read-only (changes only through actions).
- Every new queryset: `school=request.user.school`; platform admin is the only widening. Parents see only their own orders.
- IDOR tests for every new route: a Demo school ADMIN requesting Rival ids gets 404.
- School ADMIN or Procurement can never reach global actions: `approve|suspend|unsuspend|pending|suspended` on distributors, the platform flag setter, wallet withdrawals, other schools' relationships.
- Delegation off: school ADMIN and Procurement get 403 on approve/reject/suspend/reinstate; request still works.
- Global suspension: school-approved relationship stops working at once (catalogue, import, new orders, storefront); reappears on unsuspend.
- Audit: every decision, flag change and receive has an `AuditLog` row; the central exclude list stays in force.
- **Seed data** (`seed_dev_users`): `distributor@demo.com` (role DISTRIBUTOR, verified profile with products), `platform@demo.com` (superuser, platform admin), `procurement@demo.com` (Procurement group) in both schools' domains where it applies, a second verified supplier `Rival Supplies` that only the Rival school has approved, and Demo relationships in several states (APPROVED, PENDING, REJECTED) plus one globally suspended supplier. A Rival `SchoolSupplier` and `SchoolOrder` exist so cross-school leaks are visible.
- **`api_probe.py`** gains `distributor` and `platform` roles (and `procurement`) and must show: zero Rival `SchoolSupplier`, `SchoolOrder`, `Delivery`, purchase and sales rows visible to any Demo role; no Demo non-platform role reaching a global action (2xx on `approve/suspend/unsuspend/pending/suspended`, the flag setter, `import_from_distributor` for a non-approved supplier). A dedicated `shop_privacy_probe.py` (read-only, scratch DB) repeats the targeted assertions like `parent_privacy_probe.py`.

## 9. Out of scope

Payments and escrow release logic, M-Pesa, the 3D storefront, commission rules, supplier onboarding forms, multi-currency, per-school anonymous storefront URLs, deleting `procurement.Supplier`, migrating existing `Supplier` rows into `SchoolSupplier`.

## 10. Decisions (confirmed)

1. D3: keep the shared catalogue; platform-only edits.
2. D4: platform enables the shop; school ADMIN may disable it.
3. D8: suspended supplier = no new orders; in-flight orders finish; schools are flagged.
4. Anonymous storefront: stays global, minus suspended or unverified supply.
5. **Deploy impact:** closing G2 means schools lose supplier products until relationships are approved. A one-off `preapprove_school_suppliers` command creates APPROVED rows for existing school/supplier pairs. It must first run as a **dry run that prints the full list** (school, supplier, evidence such as existing `SchoolOrder`s or imported listings) for your review; it writes only with `--apply` and your go-ahead.
6. Four phases kept (frontends and seed/probe stay separate).

7. **Shared catalogue is a source, not a storefront (decided).** Parents never order a school-less product directly. Schools import from the shared catalogue (`POST /shop/products/import_from_shared/`) exactly as they import from distributors; the copy becomes the school's own listing. The hotfix rule (parent and guest orders only for active listings of one school) stands. This supersedes the "or to the shared catalogue" wording in section 5.
8. **Import-first (decided).** Distributor and shared products reach /shop and /bookshop only after a school imports them. Imports must produce complete listings (variant, image, brand, category, cost, stock, tags).

## 11. Hotfix already shipped (backend `fix/private-media`, merged into `feat/school-data-management`)

- G7: parent order items must be active listings of the parent's own school; guest orders must be one school, non-shared, active.
- G2/G3: suspended or unverified suppliers are hidden from school distributor catalogues, import, `sync_distributor_categories`, the anonymous storefront and `hero_items`; parent, guest and `SchoolOrder` creation reject them.
- G6 (partial): `procurement` suppliers and stock are writable by school ADMIN only (reads stay authenticated). Purchase orders, items, goods received and assets are unchanged until the Procurement group exists (Phase 1/2).
- Import hotfix: imports create a Default variant (stock from the supplier), copy the image, brand, cost price, tags and category; markup is validated (the old code crashed on every import). `import_from_shared` added. `backfill_imported_listings` (dry run default, `--apply`) repairs old imports. The public list now returns tags, levels, institution categories and distributor name.
