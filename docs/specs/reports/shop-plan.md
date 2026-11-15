# Report: school shop and supplier administration (spec + plan only)

Files: `docs/specs/school-shop-admin.md`, `docs/specs/school-shop-admin-plan.md`. No code changed.

## Gap analysis in one screen
Graph checked first (6134 nodes). Existing: global supplier verification (platform-only already), supplier catalogue, school orders + deliveries, shop products/orders/payments, per-school settings, audit log, `Procurement`-style group helpers. Missing or wrong:
- **No school-to-supplier relationship** (G1) and **no `supplier_approval_delegated` / `shop_enabled` flags** (G4); **no `Procurement` group** (G5).
- **Any school can use any verified supplier**, including suspended ones: `DistributorProductViewSet` and `import_from_distributor` check only `is_verified` (G2); global suspension does not delist from the anonymous catalogue (G3).
- **Parents can probably order another school's variant** and there is no shop on/off check (G7; the plan starts with a failing test to prove it).
- **Admin panel guard lets a school ADMIN in** (`role === 'ADMIN'`, plus a `SUPER_ADMIN` role that does not exist) (G8); `/me/` has `is_superuser` but no `is_platform_admin` (G9).
- **Dashboard totals are computed from the first page** (G10).
- Teachers can write procurement suppliers/stock (G6); no stock link between deliveries and inventory (G11); no performance/report endpoints (G12); no shared catalogue (G13); two unrelated supplier concepts (G14).

## Design in one screen
- New `distributor.SchoolSupplier` (PENDING/APPROVED/REJECTED/SUSPENDED, decided_by/at, audited); one helper `school_can_trade` applies the rules everywhere: verified + not suspended + APPROVED. Global suspension overrides without rewriting the school row.
- Decision rights: platform admin always; school ADMIN or Procurement only when the platform set `supplier_approval_delegated`. Only the platform admin can set it.
- Reuse, don't duplicate: no new inventory or order models; `SchoolOrder`/`Delivery` for purchasing, `StockItem` + variant stock for inventory (receive action), performance and reports computed. One new thin app `schoolshop` for the API. `procurement.Supplier` stays as the local off-platform vendor list.
- **Host the school-scoped view in `codingclubskenya`**: school ADMIN, Procurement and parents already sign in there with school-scoped tokens, the shop pages, group-based gating and `ImportDialog` live there. The distributor app stays for suppliers, the public storefront and the platform operator (admin panel guarded on `is_platform_admin`, dashboard from API counts/summary).

## Phases (4, one session each, after school-data Phase 6)
1. Flags, `SchoolSupplier`, `Procurement` group, permissions, decision service, `is_platform_admin`.
2. School-shop API, gating of existing supplier/catalogue/order paths, stock receive, performance, reports, parent storefront and order checks.
3. Frontends: codingclubskenya School Shop + parent shop; distributor admin guard, Schools tab, dashboard totals.
4. Seed (`distributor@`, `platform@`, `procurement@`, Rival Supplies approved only for Rival), `api_probe` roles, `shop_privacy_probe`, end-to-end, docs.

## Needs your decision (defaults in the spec if you say nothing)
1. Keep a shared catalogue of school-less products (D3)?
2. May a school ADMIN switch their own shop on (D4), or platform-only?
3. Suspended supplier: block new orders but let in-flight orders finish (D8)?
4. Anonymous storefront stays global for now, only hiding suspended/unapproved supply?
5. **Deploy impact:** closing G2 means schools lose supplier products until relationships are approved. The plan has a reviewed one-off command to pre-approve existing school/supplier pairs, run only with your go-ahead.
6. The prompt said "Phases: 3-4"; I planned 4. Say if you want it merged into 3 (frontends plus seed/probe together).
