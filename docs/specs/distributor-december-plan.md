# Distributor December plan

Date: 2026-11-20. Source: `distributor-status.md` (main copy, 2026-11-19). Branch `feat/distributor-december` in `backend/` and `distributor/`. Dev ports: backend 8001, distributor 3001. No deploy, no root pointer bump.

## Decisions applied

| # | Decision | Effect on this plan |
|---|----------|---------------------|
| 1 | Platform resells distributor goods | Platform is seller of record; escrow and commission stay; distributors are paid out of the wallet. |
| 2 | `DistributorProduct` owns stock and base price; `shop.Product` = base + markup | Stock reserve/commit/release acts on `DistributorProduct.available_stock` via `shop.Product.linked_distributor_product`. Storefront price is derived, never typed in twice. |
| 4 | `/lp-cover` nginx rule exists | No work. Dev rewrite stays in `next.config.ts`. |
| 6 | Payouts manual | `/admin/withdrawals` is hidden (item 1); no B2C work. |
| 3, 5 | eTIMS and sample booklists pending | Invoicing and booklist-upload parsing are out of this plan. |

Scope rule: backend changes only in `shop`, `distributor`, `booklists`, `carts`, `storefront`. New migrations only there. Anything needing another app (for example `accounts` for notifications) stops and asks.

## Order and totals

| # | Item | Days | Notes |
|---|------|------|-------|
| 1 | Honest admin | 2 | Frontend only. Built first. |
| 2 | Stock reserve / commit / release | 5 | Money-adjacent, concurrency tests. |
| 3 | Fulfilment from paid orders + delivery status | 8-10 | Largest gap. |
| 4 | Booklist add-to-cart | 2-3 | Published lists only. |
| 5 | Submissions inbox | 2-3 | Mostly UI; endpoints exist. |
| | **Total** | **19-23** | One developer, with tests and browser pass, no deploy. |

## 1. Honest admin (2 d)

Goal: no invented numbers. A failed request shows the error; an empty result shows an empty state; pages without a backend are not offered.

- `distributor/lib/adminApi.ts`: delete `safe()` and every mock export; `createProduct` must not fabricate a product on POST failure; dashboard stats throw instead of returning `mockStatsList`; remove API methods for coupons, withdrawals, settings, reviews, notifications, content.
- `distributor/app/admin/layout.tsx`: drop nav links for reviews, withdrawals, coupons, notifications, content, settings. (Promotions and Featured links already point at missing pages; removed too.)
- `distributor/app/admin/{coupons,withdrawals,settings,reviews,notifications,content}/page.tsx`: replaced by a shared "Not available yet" notice so old bookmarks do not 404. Old UI stays in git history.
- `distributor/app/admin/page.tsx`: error state, empty states, no notifications panel, no payouts quick action.
- Real pages (users, sellers, pending, products, categories, courses, orders, payments, refunds, reports, product-new): visible load error with retry; mutations report failure instead of `.catch(() => {})`.
- New `distributor/components/admin/LoadError.tsx`, `NotAvailable.tsx`.
- Tests: `distributor/lib/adminApi.test.mjs` (Node test runner, no new deps): errors propagate for each real endpoint; no mock exports remain; empty list returns `[]`, not mock rows.
- Browser check on `localhost:3001` against API on 8001, including an API-down pass.

## 2. Stock reserve / commit / release (5 d)

- `backend/distributor/models.py`: `StockMovement` (distributor product, delta, reason: reserve/commit/release/adjust, order ref, timestamp); `DistributorProduct.reserved_stock`. Migration in `distributor`.
- `backend/shop/services/stock.py` (new): `reserve(order)`, `commit(order)`, `release(order)`, each inside `transaction.atomic()` with `select_for_update()` on the product rows, same pattern as `shop/services/payments.py`. Idempotent per order (a `stock_state` on `shop.Order`, migration in `shop`).
- Hooks: reserve on order create (`shop/views.py`), commit on payment confirmation (`payments.py`), release on cancel, payment failure and a reservation expiry command `shop/management/commands/release_expired_reservations.py`.
- `backend/carts/views.py:101`: stock 0 means out of stock (unless `backorders`), not unlimited. Behaviour change; called out in the PR.
- Price: `shop.Product.price` = `DistributorProduct.unit_price` + markup, computed in one function used by cart and order totals. Unlinked products keep `ProductVariant.stock_quantity` (open question 1).
- Tests (`shop/test_stock.py`, `distributor/tests.py`): oversell blocked, parallel reserve of the last unit (threaded `TransactionTestCase`), release on cancel, commit once on duplicate callback, tenant scoping unchanged.

## 3. Fulfilment from paid orders + delivery status (8-10 d)

- `backend/distributor/models.py`: `FulfilmentOrder` (shop order, distributor profile, status NEW/PACKING/SHIPPED/DELIVERED/FAILED) and `FulfilmentLine`; `Delivery` gains an optional link to `FulfilmentOrder` (migration in `distributor`). Open question 2 on sharing one model with `SchoolOrder`.
- `shop/services/payments.py`: on confirmation, split the order by distributor and create fulfilment rows in the same transaction as the stock commit.
- `distributor/views.py`: `FulfilmentViewSet` scoped to the signed-in distributor (list, packing list, advance status, set carrier and tracking number). Platform admin sees all.
- `shop/views.py`: read-only `guest-orders/<token>/tracking` returning delivery status only (no PII); `track-your-order` uses it.
- Frontend: `app/dashboard/fulfilment/page.tsx` (queue, packing list), `app/admin/fulfilment/page.tsx` (read-only), `app/track-your-order/page.tsx` (real status).
- Notifications on status change are out (needs another app); status is pull-only.
- Tests: split of a mixed-distributor order, distributor A cannot read or advance B's rows, tracking endpoint leaks no address or phone, token guessing returns 404.

## 4. Booklist add-to-cart (2-3 d)

- `backend/booklists/views.py`: `POST booklists/<id>/add_to_cart/`; published lists only; items resolved inside the list's school; skips inactive or out-of-stock variants and reports them.
- `backend/carts/`: bulk-add helper reusing the single-add checks (stock, min order quantity).
- Frontend: "Order this list" on the parent/school booklist view in `distributor/app/` (exact route confirmed when built).
- Tests (`booklists/test_add_to_cart.py`): draft list refused, cross-school list refused, out-of-stock reported, quantities honoured.

## 5. Submissions inbox (2-3 d)

- Backend: `shop.FormSubmission` list and `mark-reviewed` / `mark-resolved` already exist; add filters by `type` and `status` and a count endpoint if missing (`shop/views.py`).
- Frontend: `distributor/app/admin/submissions/page.tsx` with type and status filters, detail drawer, mark buttons; nav entry with a "new" count.
- Out: converting an onboarding submission into a distributor account (needs `accounts`; ask first).
- Tests: admin-only access, status transitions, filters.

## Risks

- Item 2 changes cart semantics (0 stock). Existing products with stock 0 become unbuyable until stocked.
- Items 2-3 touch payment confirmation: smallest change, keep `test_payment_security.py` green.
- Migration clash check against `feat/school-data-management` before any merge: `git diff feat/school-data-management --stat -- '*/migrations/*'` in `backend/` plus `makemigrations --check` on the merged tree.

## Open questions

1. Products with no distributor link: keep `ProductVariant.stock_quantity` as their stock, or require a link?
2. Should school bulk orders (`SchoolOrder`) later share `FulfilmentOrder`, or stay separate?
