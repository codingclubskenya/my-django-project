# Release 1 readiness

Tested on `feat/school-data-management` (backend, a superset of `fix/private-media`: every fix commit is merged into it; the dev DB is migrated for the feature branch) and the `frontend/` submodule on `feat/school-data-management`. Dev servers only (backend `DEBUG=True` on :8000, Vite :5173, Next :3000 under Node 22; the system Node 18 is too old for Next). Seed accounts only (`seed_dev_users`, Demo School). Nothing was fixed in part 4 (as asked). Servers stopped afterwards.

## 1. Paginated endpoints (fixed, uncommitted)
Only `shop/products` and `shop/variants` are paginated (`ShopAdminPagination`, 200/page, max 500). Findings:
- `frontend/codingclubskenya/src/hooks/useApiList.js` took `res.data.results` only, so **ShopProducts.jsx and Requirements.jsx showed page 1 (200 rows) of a school's catalogue**. Fixed: follows `next` (re-requests its own URL with `?page=N`, never the absolute `next`), 200-page guard. Plain lists are unchanged.
- `distributor/lib/adminApi.ts` `getProducts` (admin products page, dashboard counts) had the same page-1 problem. Fixed with `getAllPages` (same approach).
- `shop/variants/` has no frontend consumer; `variants/search` is an unpaginated action; the storefront already follows `next`/`count`; `PublicProductViewSet` list is paginated and both /shop and /bookshop fetch every page.
- Not changed: `distributor/lib/api.ts` `shopApi.getProducts` returns one page by design (callers pass params); check at use sites if a full list is ever needed.
Edits are in the working trees (not committed): `frontend/codingclubskenya/src/hooks/useApiList.js`, `distributor/lib/adminApi.ts`. `tsc --noEmit` clean for the touched TS.

## 2. nginx
`backend/deploy/nginx/learningpack` had **no** private-media protection (public `/learningpack/media/` served everything). Added to both HTTPS server blocks, matching `deploy/nginx/school_management`: the same prefix list in a regex `location ~* ^/learningpack/media/(recruitment|assessment_evidence|reference_documents|scheme_uploads|course_attachments|course_materials|submissions|form_submissions|disputes)/ { return 404; }` (path prefixed with `/learningpack` because that vhost mounts media there) and the identical `location /protected-media/ { internal; alias .../media/; add_header X-Content-Type-Options nosniff always; }` (alias is that server's media dir). nginx is not installed, so `nginx -t` was not run; I diffed the blocks instead: prefix lists identical, `protected-media` block identical apart from the alias path. `core/test_private_files.py::test_nginx_blocks_every_private_prefix` now also checks `learningpack` (both server blocks); it failed before the edit and passes now. Committed on `fix/private-media` and merged into feat. **Deploy notes:** run `nginx -t` on the server; set `PRIVATE_MEDIA_ACCEL_PREFIX=/protected-media/` in the backend environment; the file has two HTTPS server blocks with the same `server_name`/port (pre-existing, nginx will warn about the duplicate).

## 3. `npm run build` (frontend/codingclubskenya)
Passes (vite 5.4.21, 2038 modules). Only the usual >500 kB chunk warning. No errors to fix.

## 4. Browser pass: role x page
Legend: OK = loads and shows data or a correct empty/denied state; BROKEN = wrong or unusable; "console" = console errors; "API 4xx" = failing requests (not logged as console errors). Landing page = where `/` redirects.

| Page | admin | teacher | staff | parent | student |
|---|---|---|---|---|---|
| Landing / dashboard | OK; console: `<sectionHeader>` casing (x2), Chart.js "Invalid scale configuration: stacked" (x2) | OK (`/teacher-dashboard`); console: TeacherDashboard.jsx:69 AxiosError 400 (one of its three parallel requests), controlled-input warnings | OK (`/school-dashboard`); same console errors as admin | **BROKEN: `/parent-dashboard` is a blank page** (empty `#root`, no console error). The route was added in b6573ae and is no longer in `App.jsx`; `Homepage`, `AuthContext` and `Layout` still send parents there | OK (`/student-dashboard`) |
| Students (CBC gradebook) | OK (needs a learning area picked; shows "No learners found" until then; learner names are blank in seed data); console: controlled-input warning | OK; same warning | OK; same warning | loads (same page and warning) | loads (same page and warning) |
| Parents | OK (row shown, linked child, import/add) | OK, shows "You do not have access to parent records" | same | same | same |
| Teachers | OK | OK | loads, "No teachers found" | loads, empty; API 403 `teacher-leaves` | same as parent |
| Staff | OK page, **"No staff records found"** although `staff@demo.com` exists (`auth/staff-profiles/` returns 0 rows; payroll profiles are a separate table) | OK (read-only banner) | OK | loads read-only, API 403 `staff-profiles`, `staff-groups` | same as parent |
| Courses (Course Studio) | OK | OK | OK; API 403 `auth/users/students/` | loads (Course Studio shell shown) | loads |
| Fees | OK (summary KES 42,000 / 22,0xx) | OK; API 403 `invoices/report/` (handled: report tabs hidden) | OK | loads; API 403 `invoices/report/`; **shows an "Add Invoice" button** | same: **"Add Invoice" button shown** |
| Payroll | OK (2 profiles) | **BROKEN UX:** page renders with "0 staff profiles / No staff profiles found" while four APIs return 403 (`staff-profiles`, `leave-requests`, `payslips`, `settings`); should be an access-denied state | OK (1 profile) | same as teacher (4 x 403, misleading empty state) | same as teacher |
| Parent-Teacher Meetings | OK (2 meetings) | OK (2 shown) | **BROKEN UX:** form shown, "0 shown", API 403 on `meetings` and `notes` | OK (2 shown) | "No meetings scheduled", API 403 |
| /shop (Next :3000) | OK: 12 cards on first page | not separately opened (public page, same code) | not separately opened | OK; **add to cart works** (POST `/carts/items/` 201) | OK |
| /bookshop (Next :3000) | OK: 3D scene renders | not separately opened | not separately opened | OK: scene, search, product card, "Add to Trolley" works (cart count 1, server cart updated); no "sample products" fallback pill | OK |

Other findings (parent, /shop and /bookshop):
1. **BROKEN: `/cart` shows "Your cart is empty" on a direct page load even though the server cart holds items** (`GET /carts/` returned 2 items, 3 after bookshop add). The header badge shows the count; the cart page does not render the lines. During load `GET /carts/` also returned 401 then 400 before 200 (token refresh race).
2. /shop reports "3178 products" while `/shop/public/` count is 3858: 680 products are filtered out client-side (cause not investigated).
3. `/bookshop` nav link present in the header (added earlier); the top bar still shows "Log in" for signed-in users on both Next pages (cosmetic; "My Orders" appears).
4. Seed data: students have empty first/last names, so name columns are blank.

Console noise (all roles, dev build only): "value prop without onChange" on the gradebook page; `sectionHeader` lower-case component in the dashboard.

## Release blockers to fix next
1. Parent landing page blank (route missing).
2. `/cart` empty on direct load with a populated server cart.
3. Payroll and PTM pages show misleading empty states to roles the API rejects; Fees shows "Add Invoice" to parents and students.
4. Staff page empty for admin (check whether `staff-profiles` should list STAFF users).
5. Commit the two pagination fixes (frontend and distributor) once reviewed.
