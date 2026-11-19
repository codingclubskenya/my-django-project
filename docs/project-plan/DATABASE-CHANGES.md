# Learning Pack — Database Changes Log

Every schema or data change is recorded here before it merges. Each entry gives: migration, reason, data impact, rollback, and the date applied to prod.

## Baseline (2026-11-12)

| App | Migration state |
|---|---|
| academics | 0001–0004 committed. **0005–0008 untracked** (stream academic_year/capacity/status/code, curriculum versions/subjects/overrides/learner selections, grade options). |
| accounts | **0008–0010 untracked**. 0010 is a *data* migration (`populate_studentprofile_fields`). |
| payroll | ⚠️ Model change without a migration: `LeaveRequest.approved_by` |
| procurement | ⚠️ Model change without a migration: `Asset.tag` |
| others | in sync |

> The untracked migrations must be committed before they reach production, and checked against what prod has already applied (`showmigrations` on the server). Otherwise migration history will diverge.

## Pending / planned changes (not yet written)

| Ref | Change | Data impact | Approval |
|---|---|---|---|
| S0 | ~~Add missing payroll/procurement migrations~~ ✅ done (below) | none | — |
| C1–C3 | ~~Unique provider receipt; raw callback log~~ ✅ done as `MpesaCallbackLog` (below) | none (additive) | — |
| C2 | ~~`shop.Order.public_token` (UUID), backfilled~~ ✅ done (below) | additive | — |
| H1 | Private file metadata model; move existing private media to private storage | file moves | **yes** |
| D1 | Merge `payroll.StaffProfile` into `accounts.StaffProfile` | data migration | **yes** |
| D2 | Merge `requirements.*` into `booklists.*` (or reverse) | data migration | **yes** |
| D10 | Tenant-scoped `academics.AcademicYear`; FKs replace strings | data migration | **yes** |
| M2 | Ledger + reversal entries for fees | additive | — |

## Changes on branch `fix/critical-security` (not yet applied to production)

Commit `da2896a` committed the previously untracked migrations (academics 0005–0008, accounts 0008–0011, booklists/carts/storefront 0001, gradebook 0002 seed, website 0002). **Check `showmigrations` on prod before deploying.** If prod already applied hand-copied versions of these, fake-apply only after comparing them.

| Migration | Type | Reversible | Notes |
|---|---|---|---|
| `payroll.0002_alter_leaverequest_approved_by` | AlterField (related_name) | yes | No data change |
| `procurement.0002_alter_asset_tag` | AlterField (`blank=True`) | yes | Field was already unique. `save()` auto-generates tags. |
| `accounts.0012_user_must_change_password` | AddField bool, default False | yes | Existing users unaffected until rotated |
| `shop.0013_daraja_payments_and_order_token` | Additive: new `MpesaCallbackLog`, `Payment` fields, unique receipt constraint, `Order.public_token` | yes (drops added columns) | `public_token` added in 3 steps (nullable → backfill per row → unique). **The migration stops (no data change) if two existing payments share an M-Pesa receipt.** Resolve those with finance first: they may be forged confirmations. Pre-check SQL: `SELECT mpesa_receipt_number, count(*) FROM shop_payment WHERE mpesa_receipt_number <> '' GROUP BY 1 HAVING count(*) > 1;` |

### Data operations (manual, after deploy, need operator)
| Command | Effect | Approval |
|---|---|---|
| `manage.py audit_superusers` then `--demote --keep <real operator emails>` | Removes `is_superuser`/`is_staff` from school-bound ADMIN accounts | ✅ (C5 fix). Run the list-only form first. |
| `manage.py reset_default_passwords --dry-run` then `--output /root/password-resets` | Rotates every active non-superuser account still on a known default password. Writes per-school CSVs (mode 600) for admins. | ✅ approved 2026-11-12 |

## Changes on branch `fix/stage2-tenancy-files` (stacked on R1, not applied)

| Migration | Type | Notes |
|---|---|---|
| assessment 0004, courses 0010, curriculum 0005, distributor 0005, recruitment 0002, shop 0014, tenants 0003, website 0003 | AlterField: validators / `upload_to` only | **No SQL on PostgreSQL** (Python-side options). SQLite rebuilds the table, which is harmless. Existing files keep their current paths and are **not** re-validated; validation applies to new uploads only. |

## Stage 3 (branch `fix/private-media`, not applied)

| Migration | Type | Reversible | Notes |
|---|---|---|---|
| `fees.0003_payment_ledger_reversals` | AddField `reason` (text, default ''), AddField `reversal_of` (nullable one-to-one to self, PROTECT) | yes | Additive. Existing payments are untouched and become immutable at the model/API level. **No DB check constraint** on amount sign (legacy rows may violate it); enforced in code. Pre-check for legacy anomalies: `SELECT id, amount FROM fees_payment WHERE amount <= 0;` |

## Applied to production

*(none yet)*
