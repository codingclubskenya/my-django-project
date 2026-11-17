# Catalogue to production: discovery (read-only)

Date: 2026-11-17. Nothing was changed locally or on the server. Prod queries were read-only ORM counts through `ssh contabo` (`manage.py shell --settings=core.settings_production`, no writes, no secrets read).

## 1. Local catalogue (3,858 products)

| Facet | Result |
|---|---|
| Products | 3,858, all active, all `school = Demo School (id 1)` |
| Created | 2026-11-11 16:10:38 to 16:10:58 UTC (one 20-second run) |
| Supplier / distributor link | None. `linked_distributor_product` is null on all 3,858; `is_reseller_listing` false on all; local has 0 `DistributorProfile`, 0 `DistributorProduct` |
| Brand (publisher, from import file) | Oxford 1,097; Savanis Book Centre 942; Longhorn 669; KLB 461; StoryMoja 393; Spotlight 296 |
| Categories (12, all Demo School) | Books 2,741; Educational Books 942; Stationery 108; Art 31; Technology 20; Education & Reference 9; five singletons |
| Variants | 3,858 products with a variant (exactly one `Default`, stock 0 on every row); no gallery images |
| Images | 3,855 external `https://image.codingclubskenya.com/...` (stored as the ImageField name); 0 local `/media`; 3 with no image |
| SKU | Empty on all rows. There is no slug field |
| Price | No zero prices, no "Untitled" |
| Duplicates | 3,832 distinct (brand, name); 91 duplicate (school, name) groups. Distinct (brand, name, image) has no duplicates, so that triple is the usable natural key |
| Orders | 0 locally |

### How they were created
`backend/shop/management/commands/import_cdn_catalog.py` (added in `da2896a`) reads six scraped WooCommerce JSON files bundled in `backend/shop/data/` (`books, oxford, storymoja, klb, spotlight, lornghorn`.json) and creates one Product plus one `Default` variant per row. The counts above match that command exactly (brand per file, image from the scraped `image src`/thumbnail URL). It is not a distributor sync and not a fixture.

Hazards in that command, relevant to prod:
- It runs `Product.objects.all().delete()` and then `ProductCategory.objects.all().delete()` first (unless `--keep-categories`). On prod this would wipe the 134 existing products and cascade into order lines.
- It has no dry run and is not idempotent (a re-run deletes and recreates, so ids change).
- It targets `School.objects.first()` unless `--school-id` is given.

Other commands, not the source of this data: `seed_bookshop_products` and `seed_shop_products` (demo seeds, none of their rows survive locally), `backfill_imported_listings` (dry-run by default, repairs reseller listings), and `shop/listing.py` (`import_distributor_product`, `import_shared_product`).

## 2. Test data
- **Rival School**: exists locally (id 2) but has 0 products and 0 categories. Nothing to skip.
- **Seed rows**: none (no seed-command product names present).
- Name matches for "test/demo/sample" (22 rows) are false positives: SmartPlus "KCPE Test Papers", "Test it & Fix it KCSE ...", "Demographic Methods and Concepts". They are real books.
- The only "test-like" aspect is that every product hangs off the dev seed school `Demo School`. Placement under the right prod school is what needs a decision (see 4).
- 3 products with no image, and 91 duplicate-name groups, are import quality issues rather than test data.

## 3. Production (read-only)

| Facet | Result |
|---|---|
| Schools | One: `Demo School` (id 1, code `demo-school`). No Rival School |
| Products | 134 (133 active), all Demo School; created 2026-09-27 17:58 to 17:59 UTC (seed) |
| Origin | 133 `is_reseller_listing`, 2 linked to a distributor product; 133 `DistributorProduct` rows |
| Distributors | One: `Demo Distributor Ltd` (id 1, verified). No other suppliers/distributors |
| Categories | 20 (School Uniforms, Stationery, Books & Learning Materials, Cleaning & Sanitation, ...), all Demo School |
| Variants | 5 variants on 4 products |
| Images | 134 local `shop/products/2026/...`; 0 external |
| Brand / SKU | Empty on all |
| Orders | 1 existing order (must survive any import) |
| Overlap with local | None by case-insensitive name (0 of 134). SKUs are empty on both sides, so SKU overlap is moot; ids are not comparable |

Prod is itself demo data (one demo school, one demo distributor). "Real" prod schools and distributors do not exist yet, which affects the mapping target.

Version caveat: prod backend is `qa/hardening-fixes @ 7f2d760` (2026-10-20, with uncommitted files); local is at `9402a34` (2026-11-16). Before any import, confirm prod's `shop/serializers.py` passes through absolute `https://` image names (local does, at `shop/serializers.py:33-39`); otherwise the 3,855 external covers would render as broken `/media/https:/...` URLs.

## 4. Recommendation

**Do not re-run `import_cdn_catalog` on prod.** It deletes all products and categories (including the 134 prod rows and anything referenced by the existing order), has no dry run, and is not idempotent.

**Build a new command instead**, e.g. `import_catalogue_bundle`, in two modes:
1. **Source**: read the bundled JSON files (already in git, no local DB export needed) or a `--from-json` export produced by a companion `export_catalogue` command. The JSON files are the canonical source; exporting from the local DB adds nothing, since all 3,858 rows came from them.
2. **Dry run by default**; `--apply` to write. Print created/updated/skipped counts and a sample, all inside one transaction.
3. **Natural key and idempotency**: `(school, brand, name, image)`; `get_or_create`/`update_or_create` on that key, never delete. Re-runs update price and category and create nothing new. Needed because there is no SKU or slug and ids differ between environments.
4. **Mapping**: required `--school <id|code>` (no `School.objects.first()` default); categories `get_or_create` per target school by name; fail loudly if the school does not exist. No distributor link (these are catalogue listings, not reseller listings), so no distributor mapping is needed. Decision for you: whether they go under prod's `Demo School` (the only school there) or a new real school/"platform" school first.
5. **Skip test data**: skip rows with no title or price 0 (none today), skip Rival-School-scoped data, and report the 3 imageless rows and the 91 duplicate-name groups for review (decide: keep both, since they differ in image/brand, or skip).
6. **Safety**: refuse to run if `DEBUG` is false unless `--i-know-this-is-prod`; never touch existing products outside the natural-key match; take and report a fresh DB backup path before `--apply`, as the server rules require.

Open decisions for you: (a) target school on prod, (b) stock quantity (all variants are stock 0, i.e. "available to order"), (c) duplicates policy, (d) hotlinking `image.codingclubskenya.com` in prod vs mirroring images to `/media` (hotlinking is simplest and matches local; mirroring avoids the CORS rewrite but needs about 3,800 downloads).

Prod also needs `/lp-cover/` (the CORS-avoiding cover path) wired in nginx for the 3D bookshop, since the static export has no Next rewrites. Check this separately before expecting covers in prod.
