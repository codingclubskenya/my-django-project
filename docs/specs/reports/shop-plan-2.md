# Shop plan, round 2: hotfix, decisions, bookshop investigation

## 1. Security hotfix (backend `fix/private-media`, merged into `feat/school-data-management`)

Commit `a96bd4c`, merge `8f8e8ae`. `fix/private-media` was 12 commits behind, so the merge brought no conflicts.

| Gap | Result |
|---|---|
| G7 | Test first. Cross-school variant/product was **already rejected** by `TenantFKValidationMixin` (tests added to pin it). The real hole: a **school-less product** was orderable by any parent (failed with 201, now 400). `_check_sellable` (shop/serializers.py) now requires an active listing of the parent's own school and a live supplier. Guest orders must be single-school, non-shared, active. |
| G2/G3 | Suspended or unverified suppliers are filtered from: school distributor catalogue, `import_from_distributor`, `sync_distributor_categories`, anonymous `/shop/public/` list and detail, `hero_items`. `OrderCreateSerializer`, `GuestOrderCreateSerializer` and `SchoolOrderSerializer` reject them. `/discovery` already filtered. |
| G6 | `SupplierViewSet`, `StockItemViewSet`: `IsAuthenticated + IsAdminOrReadOnly` (ADMIN writes; reads authenticated). A first attempt with `IsAdminOrReadOnly` alone let anonymous reads reach the queryset (500); caught by `procurement.tests`, fixed. PO, items, goods received, assets unchanged (not in scope). |

Side effect: `shop/tests.py` fixture distributor had `is_verified=False`; set to True (orders now require a verified supplier, consistent with the storefront).

**Decided:** parents never order school-less products; the shared catalogue is an import source (spec decisions 7 and 8).

Tests: `shop distributor procurement core` 134 OK on the hotfix branch, `shop distributor procurement` 47 OK after merge. New: `shop/test_order_scoping.py` (4), `shop/test_supplier_suspension.py` (7).

Probe: see section 7.

## 2. Docs updated
`school-shop-admin.md` (D3, D4, D8, anonymous storefront, pre-approve with dry run, four phases, role table, new section 11 listing the hotfix) and `school-shop-admin-plan.md` (Phase 1 D4 rule, Phase 2 "already shipped" note, suspension flag, `preapprove_school_suppliers` dry-run default, bookshop parity work; Phase 3 bookshop/shop parity).

## 3. Where /shop and /bookshop live
Both are in `distributor/` (Next.js), both anonymous, both read **the same endpoint**, `GET /api/shop/public/` (`PublicProductViewSet`, all schools, active products only).

| | /shop | /bookshop |
|---|---|---|
| Page | `app/shop/page.tsx` (+ `shop/[id]`) | `app/bookshop/page.tsx` → `components/learning-pack-3d/` (3D store) |
| Fetch | `api.get('/shop/public/', page_size, page)` all pages | `fetchCatalogue()` in `learning-pack-3d/src/api.js`, 200/page, all pages; plus `hero_items/`, `/storefront/schools/` |
| Filters | client-side over the full list (taxonomy from `lib/shopCategories`, level, brand, price, audience) | none server-side; `classify()` regex into 8 aisles, 64 tiles/aisle |
| Cart | `lib/cart.tsx`, `variant_id` | same store (`useSupermarketStore`) |
| Nav | `GlobalHeader` (`/shop` only), `Header.tsx` (`/shop`) | **no link anywhere** (`rg href="/bookshop"` finds nothing) |

## 4. Root cause: distributor products missing from /bookshop
Static analysis only; I did not drive the browser.

1. **Wrong table (primary).** The school "add product" dialog (`frontend/.../ShopProducts.jsx`, `useApiList('/api/distributor/products/')`) lists `DistributorProduct` rows. `/shop/public/` and both pages show `shop.Product` rows. A distributor product exists in the shop only after a school ADMIN runs `import_from_distributor`. Not imported = absent from /shop and /bookshop. This is by design but looks like a bug.
2. **Imports are incomplete.** `import_from_distributor` creates a `Product` with **no variant, no image, no brand/sku**. In the bookshop `normalise()` then sets `variantId = raw.id` (the product id), so add-to-cart posts a *variant id that is a product id*: wrong item, or a 400 now that G7 is closed. `image` empty gives rank 0, so imports sort last and, with the **64-tiles-per-aisle cap** (`stockAisles`), are dropped whenever the aisle already has 64 ranked items. `brand` defaults to "Learning Pack".
3. **Bookshop rule drops.** `classify()` returns -1 for names matching `NOT_SHELVED`/`NOT_SCHOOL` or category `Technology`; those never reach a shelf or search.
4. **No shared filters.** /shop filters client-side, /bookshop barely at all; no facets endpoint, so categories/brands differ between pages.
5. Checked and ruled out: pagination (both fetch every page, `page_size` 200 ≤ max 500, stable ordering), school scoping (the endpoint is global, not school-scoped), the suspension filter (new, only removes suspended supply).

## 5. Fix plan (superseded by section 6 for the parts already shipped)
Remaining for Phase 2/3: server-side filters plus `/shop/public/facets/`, shared `catalogueFilters` and `ProductCard`, aisle hints, "unshelved" list, /shop ↔ /bookshop links with query-string filters.

## 6. Hotfix 2 (shipped: backend `fix/private-media` `d279bec`, `b9eaafe`, merged `f0b5e5c`; frontend uncommitted)
Decisions recorded in the spec: shared catalogue = import source only; import-first.

| Item | Result |
|---|---|
| Import | Test first. `import_from_distributor` **crashed on every call** (`Decimal * float`/`str`), so nothing could be imported from the UI. Fixed with `shop/listing.py`: validated markup (400 on bad type/negative/non-number), Default variant (stock = supplier `available_stock`), image copied as an independent file, brand = supplier company, cost price, sku, tags, category. |
| Shared import | New `POST /shop/products/import_from_shared/` (school ADMIN): copies an active school-less product with variants, tags, levels and image into the caller's school; school-owned or inactive rows 404. |
| Backfill | `manage.py backfill_imported_listings` (dry run default, `--apply`, `--school N`): lists reseller listings missing variant, image or brand and fills them from the source distributor product; listings with no source are reported, never invented; idempotent. Dev DB dry run: 0 fixable, 0 orphans. **Production: run the dry run and send you the list before `--apply`.** |
| Variant id in cart | /shop card and detail page: a product with no variant shows a disabled "Unavailable" button and nothing is added (the old code added `variant_id: 0`, sent later as a product id). Bookshop: `normalise()` no longer falls back to the product id; items without a variant are flagged `unavailable`, `add()` refuses them (bundles only if every item is available), product card and booklist show "Unavailable". |
| Nav | `/bookshop` added next to `/shop` in `GlobalHeader` (main nav) and `Header.tsx`, with the same visibility as `/shop` (no role condition). |
| Filters vs real API | Mismatch found: /shop filters on `tags`, `applicable_levels`, `institution_categories`, `distributor_name`, but `PublicProductListSerializer` returned none of them, so the grade, subject, tag, audience and taxonomy-tag filters matched nothing or everything. Fields added (with prefetch). The API supports only `category` (id) server-side; /shop's `category`/`level` URL params are taxonomy labels handled client-side, which now works because the data is present. The bookshop sends no filters (Phase 3). |

Tests: 71 pass in the main checkout (`shop distributor procurement accounts.test_write_access core.test_tenant_isolation`). New: `test_import_listing.py` (7), `test_public_filters.py` (2). Frontend: `tsc --noEmit` shows no errors in the touched files; I did not run `next build` or a browser click-through.

## 7. Probe (`scripts/api_probe.py`, merged branch, scratch DB copy)
449 endpoints, all roles, writes done. No 500s listed. Nothing under `procurement/` or `distributor/` in the unexpected-2xx list, so teacher/STAFF are blocked from supplier and stock writes. Shop lines flagged (all pre-existing, none caused by the hotfix):
- `shop/guest-orders/` and `shop/form-submissions/` POST 201 for every role: public by design.
- `admin POST shop/categories/sync_from_distributors/` 200 with a Rival id in `parent`: the field is ignored (no cross-school write seen), but worth a tidy.
- **To investigate:** `admin DELETE /shop/categories/13/` and `/shop/products/3892/` returned 204 on "shared id" rows (visible to both schools). Both viewsets filter by `school=user.school`, so these are probably Demo rows the probe treated as shared; confirm in Phase 2 that a school ADMIN cannot delete school-less rows (D3 platform-only edits) and add a test.
- The wider list (310 unexpected 2xx, 41 FK creates) is school-data work outside the shop. Full log and TSV: the session scratchpad (`probe.log`, `probe.tsv`).

## 8. Shared-row writes (fix: backend `fix/private-media`, merged into `feat/school-data-management`)

**The "shared id" DELETE 204s were a probe false positive, not a hole.** Shop categories are always school-owned (`ProductCategory.school` is NOT NULL, so none can be "shared"), and the dev DB has 0 school-less products. Category 13 and product 3892 are Demo's own rows. Cause: the probe's DELETE loop looked ids up by the *last path segment* (`categories`, `products`) while pools are keyed by full path, so ids from unrelated public endpoints (`/categories/`, discovery products) were deleted as `shop/...` rows. Fixed in `scripts/api_probe.py` (uses `ep.key`). Side effect: the DELETE pass now genuinely runs for Rival/shared/Demo ids, which it mostly did not before.

**How "shared" is marked:** only `school IS NULL` on a nullable `school` FK. Of all models in shop, distributor, storefront, booklists, discovery and procurement, `shop.Product` is the only one with a nullable school. The generic guard in `core/shared_rows.py` already blocked PATCH/DELETE and null-school saves on such rows.

**Audit result**

| Model(s) | Finding |
|---|---|
| `Product` | Covered; school ADMIN gets 404/403 on PATCH/PUT/DELETE, image upload, `school: null` and moving an own product to shared (tests). |
| `ProductVariant`, `ProductImage` (no school FK, hang off Product) | **Hole found:** a school ADMIN could `POST /shop/variants/` with `product=<shared product>` (201). Fixed: `shared_rows` now also guards *children of shared rows* (rows whose school path passes through a nullable-school parent whose school is NULL), on fetch and on save (rolled back, 403). Applies to every app; full suite 621 pass. |
| `ProductCategory`, `Order`, `SchoolOrder`, `Booklist`, `Supplier`, `PurchaseOrder`, `StockItem`, `Asset` | school NOT NULL: cannot be shared; other-school rows are 404 for writes (tested for categories). |
| `Tag` (global, no school) | Any school ADMIN can create tags implicitly via `tags_data`; no API edits or deletes them. Accepted; note for Phase 2 if tags should be curated. |
| `DistributorProfile`, `DistributorProduct`, wallet models | Owner-scoped (distributor) or platform-only; not school data. |
| `ShelfSection`, `ProductModelMapping`, `AcademicYear`, `ShoppableVideo`, public discovery/storefront views | Read-only viewsets. |
| `BooklistItem` | Scoped to the school's booklists; may reference a shared product's variant (read use). Parents still cannot order it (decision 7). |

Tests first: `shop/test_shared_rows.py` (12; the variant-create one failed before the fix). Probe re-run on the merged branch (admin and teacher roles, scratch DB): **no "shared row written" findings**, no 500s in shop other than the one below. Remaining probe lines are the pre-existing school-data items and public-by-design shop endpoints (guest orders, form submissions).

**Found by the now-working DELETE pass and fixed:** deleting a variant or product that orders, carts or booklists reference returned **500** (`ProtectedError`); now 409 with a message (`ProtectedDeleteMixin`, test added). **Not fixed (outside shop):** `DELETE /academics/school-academic-years/1/` also 500s on a protected row; needs the same treatment in the academics work.

Full backend suite on `feat/school-data-management`: 621 pass before the delete fix; `shop core` pass after it.

## 9. Global 409 handler, tags, green fix branch

Backend `fix/private-media` (commit "global ProtectedError/RestrictedError -> 409; tags platform-admin only"), merged into `feat/school-data-management`, plus one feat-only test commit.

**1. Global handler.** `core/exception_handler.py`, set as `REST_FRAMEWORK['EXCEPTION_HANDLER']`: `ProtectedError`/`RestrictedError` anywhere in the API become 409 `{detail, blocked_by: [model names]}`. The one-off `ProtectedDeleteMixin` in `shop/views.py` is removed. Tests: `shop/test_protected_delete.py` (product and variant used by an order item; free product still 204) and `academics/test_protected_delete.py` (academic year used by streams, then 204 once free). The academic-year test exists **only on feat**, because the protecting `Stream.academic_year` FK (PROTECT) was added there; on `fix/private-media` the academic year has no relations, so its earlier probe 500 could not occur.

**2. Tags.** `Tag` has no school field, so school-owned tags are not supported: school users get 403 for any create. New `GET/POST/PATCH/DELETE /shop/tags/`: read for signed-in users, write platform admin only (`IsPlatformAdmin`). `tags_data` on products: a school ADMIN may attach existing tags but a name that does not exist is 403 before anything is saved (no half-created product); malformed `tags_data` is 400; platform admin may create. `import_from_distributor` and `import_from_shared` no longer create global tags from supplier strings (existing tags only); `backfill_imported_listings --apply` (an ops command) still creates them. Tests: `shop/test_tags.py` (6), `test_import_listing.py` adjusted.

**3. The failing test on `fix/private-media`:** `parent_meetings.tests.MeetingScopeTests.test_note_create_only_on_visible_meeting` expected 403 when an ADMIN of school B posts a note on school A's meeting. The tenant-FK mixin rejects that foreign `meeting` id during validation (400) before the view's visibility check (403). Either way the write is refused, so the **test was too strict, not the code**; feat already carried the corrected assertion (`in (400, 403)`), now applied to the fix branch too (same hunk, merged cleanly).

**4. Full suites (`core.settings_test`, serial; `--parallel` crashes on an unrelated unpicklable traceback):**
- `fix/private-media`: 458 tests, OK.
- `feat/school-data-management`: 631 tests, OK.
