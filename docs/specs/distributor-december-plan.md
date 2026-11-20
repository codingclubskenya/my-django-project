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

### Decisions (2026-11-20)

1. A payment failure keeps the reservation until it expires (`SHOP_STOCK_RESERVE_MINUTES`, default 30), because the customer can retry the STK push. Stock is released at once only when the customer or an admin cancels.
2. Money is never refused. A payment that arrives after the reservation expired tries to re-reserve; if stock is gone the order stays `paid`, is marked `shortfall` (no stock moved) and the platform admins are emailed immediately.
3. Unlinked products use `ProductVariant.stock_quantity`. Linked products use `DistributorProduct.available_stock`, shared by all variants and school listings.
4. Production read-only count (2026-11-20): 3,916 products; 3,783 unlinked with every variant at zero stock, 3 stocked, 130 with no variants; 2 linked; 133 distributor products, all stocked; 1 order pending payment. A data migration therefore sets `backorders=True` on products whose variants are all zero, so the cart fix does not make the catalogue unbuyable.
5. Setting stock above zero on a product, variant or distributor product turns `backorders` off automatically. The toggle stays visible and the change is written to the ledger.
6. Backorder products never block a sale. They record commit movements and on-hand may go below zero (stock fields become signed). APIs and the distributor UI show "N on backorder", never a negative number.

### Design

- `distributor.DistributorProduct`: `available_stock` becomes a signed integer (on hand, may be negative only through backorders); new `reserved_stock` (default 0). Sellable = `available_stock - reserved_stock`. API reads clamp `available_stock` at 0 and add read-only `on_backorder`. Writes cannot set `available_stock` below `reserved_stock`.
- `shop.ProductVariant`: `stock_quantity` becomes signed; new `reserved_quantity` (default 0), used only for unlinked products.
- `shop.Order`: `stock_state` (`none`, `reserved`, `committed`, `released`, `shortfall`) and `reserve_expires_at`, indexed with `status`.
- `shop.StockMovement` (append-only ledger): exactly one of `distributor_product` or `variant` (check constraint); `kind` (`reserve`, `commit`, `release`, `restock`, `adjust`); `quantity`; `on_hand_after`; `reserved_after`; `order`; `order_item`; `created_by`; `note`; `created_at`. A partial unique constraint on `(order_item, kind)` for reserve, commit, release and restock makes retries idempotent.
- `shop/services/stock.py`: `reserve`, `commit`, `release`, `restock`, `sellable_quantity`. Each locks the order row, then stock rows in primary-key order, then re-checks `stock_state`. Backorder lines are not reserved; their commit decrements on hand without touching reserved.
- Hooks: both order serializers reserve inside `transaction.atomic` (400 naming the item when short); `_confirm` and `pay_fee_balance` commit; `refund` and a `PATCH` to `cancelled` release (reserved) or restock (committed and still only `paid`); `release_expired_reservations` command plus a sweep inside `reserve`.
- `carts/views.py`: one `sellable_quantity` check; zero stock is "out of stock" unless backorders are on.
- Shortfall email goes to active `SUPER_ADMIN` users, sent on commit of the transaction.

### Migrations (`distributor` and `shop` only, generated with `makemigrations`)

1. `distributor`: signed `available_stock`, `reserved_stock`.
2. `shop` (depends on 1): signed `stock_quantity`, `reserved_quantity`, `Order.stock_state`, `Order.reserve_expires_at`, `StockMovement`.
3. `shop` data migration: `backorders=True` where the product has variants and all are at zero stock and it is not linked.

### Tests

`shop/test_stock.py`, `distributor/tests.py`: oversell blocked; last unit under parallel threads on a throwaway `postgres:16` container (SQLite ignores row locks); duplicate callback commits once; expiry and sweep; late payment re-reserve and shortfall email; cancel releases, refund of a paid order restocks; backorder sale goes negative and is shown as on backorder; stock above zero turns backorders off with a ledger row; ledger sums match counts; tenant scoping and `test_payment_security.py` unchanged.

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

1. Should school bulk orders (`SchoolOrder`) later share `FulfilmentOrder`, or stay separate?
