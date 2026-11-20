# Distributor December: deploy notes (item 2, stock)

Branch `feat/distributor-december` (backend, distributor, root docs). Not merged. The school session merges and deploys.
Design and decisions: `distributor-december-plan.md`, item 2.

## Before the release
1. Fresh database backup (as for every release); note where it is.
2. Optional setting in the production `.env` (`epk/.env`): `SHOP_STOCK_RESERVE_MINUTES=30`. How long unpaid orders hold stock. Default is 30 when unset, so nothing is required.
3. Confirm at least one active superuser has an email address. Shortfall alerts (a paid order with no stock left) go to every active superuser with an email, and are only logged if there is none. Mail works in production now.
4. Migrations in this release (apply in this order; Django does it from the dependencies):
   - `distributor 0006_distributorproduct_reserved_stock_and_more` (adds `reserved_stock`, makes `available_stock` signed)
   - `shop 0016_stock_ledger_and_reservations` (reserved counts, order stock state, `StockMovement` ledger)
   - `shop 0017_backorders_for_unstocked_products` (data migration, has no reverse)
5. `0017` sets `backorders=True` on every unlinked product whose variants are all at zero stock, or that has no variant. Production read-only count on 2026-11-20: 3,916 products, 3,783 unlinked with all variants at zero, 3 stocked, 130 with no variants, 2 linked, 133 distributor products all stocked. Expect about 3,913 products flipped to backorders on. Without this the cart fix (zero stock is out of stock, no longer unlimited) would make the whole catalogue unbuyable.

## Cron (school session installs at deploy)
Add one line to the `devops` crontab (same style as the `purge_auth_lockouts` line; keep a `~/crontab.bak-<date>` first):
```
*/5 * * * * cd /home/devops/home/personal/personalweb/epk && DJANGO_SETTINGS_MODULE=core.settings_production venv/bin/python manage.py release_expired_reservations >> logs/release_expired_reservations.log 2>&1
```
It releases stock held for unpaid orders past their expiry and prints `Released N expired reservation(s).` Safe to run any time and repeatedly. New orders also free expired holds on the rows they need, so a missed run does not oversell; it only leaves counts untidy.

## After the release
1. **Check the 1 pending order.** Production had one order in `pending_payment` (read-only count, 2026-11-20). It predates stock tracking, so it has no reservation (`stock_state='none'`). Look at it (`shop.Order`, `status='pending_payment'`): its first payment attempt after deploy reserves the stock (and refuses to start the M-Pesa prompt if the items are gone); a payment that is confirmed without a reservation commits directly, or marks the order `shortfall` and emails the superusers. If the order is stale, cancel it from the admin.
2. Backorders flipped: `Product.objects.filter(backorders=True).count()` is about 3,913 higher than before. The 3 stocked products and the 2 linked ones stay off.
3. Run the cron command once by hand and read the log line.
4. In the distributor dashboard products table, a product with backorder sales shows "N on backorder" and held units show "N held for unpaid orders".
5. Place one test order on a stocked product and read the `StockMovement` rows (reserve, then commit after payment).
6. `/api/discovery/` and `/api/products/` return `total_stock` and variant `stock_quantity` as sellable units, never negative, plus `backorders` and `on_backorder`.

## Behaviour changes to know about
- Zero stock is out of stock in the cart and at checkout unless the product has backorders on. Setting stock above zero (product variant or distributor product) turns backorders off automatically and writes an `adjust` row to the ledger.
- A payment failure keeps the stock held until the reservation expires; a cancel or refund releases it at once. A confirmed payment is never refused for lack of stock.
- Stock fields are signed. APIs never return a negative number: below-zero stock is `on_backorder`. Admin tools that read the database directly will see negatives.

## Rollback
Code can go back; the migrations cannot be reversed cleanly (`0017` has no reverse, `available_stock` becoming signed is harmless to old code). Restore from the pre-release backup if the data must go back.
