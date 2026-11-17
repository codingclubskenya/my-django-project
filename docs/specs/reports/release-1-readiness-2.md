# Release 1 readiness, round 2

## 0. Working trees
Not mine, now in `git stash` (name `joe-wip-2026-11-15`, `stash@{0}` in both repos; `git stash pop` restores):
- `frontend` (on `feat/school-data-management`): `.gitignore`, `parents/android/app/build.gradle.kts`, `parents/android/app/src/main/AndroidManifest.xml`, untracked `gen-api-client.sh`.
- `distributor` (on `fix/verified-payments`): about 45 modified/deleted/untracked files, mainly the 3D bookshop rework (`components/learning-pack-3d/*`, `app/bookshop/*`, `shop-nav.css`, `next.config.ts`, `lib/api.ts`, `package-lock.json`, `.gitignore`, admin/dashboard layouts, student-boxes page).
- **Caveat:** my earlier uncommitted bookshop edits (the `/bookshop` nav link in `GlobalHeader.tsx`/`Header.tsx`, "Unavailable" for variant-less products on `/shop` and the product page, the bookshop `normalise()`/`add()`/ProductCard/BooklistPanel guards) sat inside files you had also changed, so they went into the same stash and are **not** in the release-1 commits. Consequence seen in the pass: the committed bookshop has no `/bookshop` nav link yet. Re-apply after `stash pop`.

Committed: `frontend` `d3d4b8a` (useApiList follows `next`), `distributor` `1b225de` (admin products follow `next`).

## 1. Branch `release-1`
**Frontend.** Backend `fix/private-media` contains the fees append-only ledger, `users/directory`, shop pagination and the security fixes, but not the school-data Phase 1+ work (import framework, staff groups, parent profiles, FRONTEND_URL reset). The matching frontend commit is `ba64887` (`fix(fees): hide Report/Defaulters tabs...`): it already has the temporary-password flow, append-only payments UI and the `users/directory` pickers; the next commits (`52f22e0` ImportDialog, `f57a4cf` parents/staff pages, `2d8382b` reset flow) need Phase 1. `release-1` = `ba64887` + cherry-pick of the pagination fix + `d121912`, merged into `feat/school-data-management` as `dff3512` (one conflict, `Staff.jsx`, resolved by keeping feat's HEAD lines and adding `forbidden`; build passes after the merge).
**Distributor.** Cut from `fix/verified-payments` (matches the verified-payments backend work): `release-1` = `1b225de`, `1c165f7`, `e6efafd`; `fix/verified-payments` fast-forwarded to the same commits (no `feat/school-data-management` exists in that repo).

### Fixes
1. **`/parent-dashboard` (and `/parent-report-cards`) routes.** Why they vanished: added in `b6573ae`, dropped by the merge commit `f8e4c3d` ("Merge samantha branch...") when `App.jsx` conflicts were resolved (that merge replaced the `Home` route and removed both imports and routes; a plain `git log -S` hides it because it is a merge). `Homepage`, `AuthContext` and `Layout` kept redirecting parents there, hence the blank page. Restored in `App.jsx`.
2. **/cart on direct load** had three separate causes, all fixed in the distributor app:
   - `GET /carts/` returns one cart object (`{id, items:[...]}`) but `CartProvider` read only a bare list or `results`, so it always loaded zero items (the real reason for "Your cart is empty"; found only by re-running the pass).
   - Token refresh race: the API rotates and blacklists refresh tokens (`ROTATE_REFRESH_TOKENS`, `BLACKLIST_AFTER_ROTATION`) but both apps never stored the new refresh token and each concurrent 401 fired its own refresh. Fixed in `distributor/lib/api.ts` and `frontend/.../services/api.js`: one shared in-flight refresh (later 401s wait for it), the rotated `refresh` is stored, the refresh call itself is never retried. Verified in the browser: with an invalid access token, `/cart` fired 2 concurrent 401s (`carts`, `users/me`), exactly one `auth/refresh` (200), both retried with 200.
   - Once the cart rendered, checkout crashed ("Objects are not valid as a React child"): the learner dropdown assumed `parent-learner-links.learner` is an id but the API nests the user object. Fixed (id and name label). Lines also fall back to the server's name/price/image when the product store is empty (direct load).
3. **`AccessDenied`** (`components/AccessDenied.jsx`): `useApiList` now returns `forbidden` (403); `ResourceManager` shows it for any list; Payroll (profiles), Parent-Teacher Meetings (meetings), Teachers (users or leaves) and Staff early-return it. **Fees:** `ResourceManager` got `allowCreate`; Invoices, Payments and Fee Structures hide "Add" unless role is ADMIN, STAFF or superuser (matching `IsAdminOrStaffOrReadOnlyOrOwner`).
Build: `npm run build` passes on `release-1` and on feat after the merge; `tsc --noEmit` clean for the touched distributor files.

## 2. Why admin's Staff page is empty (investigated, not fixed)
Two unrelated models: `accounts.StaffProfile` (HR/employee record: name, group, employee number, optional user; served at `/api/auth/staff-profiles/`, used by the Staff page, academic-structure lookups and audit) and `payroll.StaffProfile` (salary/bank record, user required; `/api/payroll/staff-profiles/`, used by Payroll). Nothing creates one from the other; there is no sync. `seed_dev_users` creates only payroll profiles (4 rows), so `accounts.StaffProfile` has 0 rows and the Staff page correctly shows "No staff records found". It is a seed gap, not a code bug.
Which one production uses cannot be told from this machine (no production DB access): both have working UIs, and the Staff page's create/import flows (and the 2026-11 school-data work) target `accounts.StaffProfile`, Payroll's "Add Staff Profile" targets the payroll one. Check with `StaffProfile` counts per model in production.
**Does release-1 show staff for admin?** The viewset and page exist on `fix/private-media` + `ba64887`, and the page loads without error for admin, but with the fresh DB it is empty for the same reason (0 accounts profiles). Creating one through "Add Staff" is the way to confirm (not done: no writes in this pass).

## 3. Browser pass: backend `fix/private-media` + frontend `release-1` (+ distributor `release-1`)
Fresh SQLite DB (`DATABASE_URL` pointed at a scratch file) migrated on `fix/private-media`, `seed_dev_users`, plus a verified distributor and 30 test products for school 1 (`seed_shop_products` fails on this branch: `shop_product.price NOT NULL`). Servers: backend DEBUG, Vite, Next under Node 22; stopped afterwards. API 403s are listed in brackets; "console" = console errors.

| Page | admin | teacher | staff | parent | student |
|---|---|---|---|---|---|
| Landing | OK `/school-dashboard`; console: `sectionHeader` casing x2, Chart.js "stacked" scale x2 | OK `/teacher-dashboard`; no console errors this time | OK `/school-dashboard`; same console errors as admin | **OK `/parent-dashboard` renders (was blank)**; no console errors | OK `/student-dashboard` |
| Students (gradebook) | OK (needs a learning area; "No learners found" until selected); console: controlled-input warning | same | same | loads (same page) | loads |
| Parents | OK (1 parent row) | OK, lists parent, Add/Edit shown | loads, "No parents found" | loads, shows own row **with Edit** | loads, "No parents found", Add shown |
| Teachers | OK | OK | loads, "No teachers found" | **AccessDenied** [403 teacher-leaves] | **AccessDenied** [403 teacher-leaves] |
| Staff | OK page, empty (see 2) | loads, empty | loads, empty | **AccessDenied** [403 staff-profiles] | **AccessDenied** [403] |
| Courses (Course Studio) | OK | OK | OK [403 users/students] | loads | loads |
| Fees | OK, summary shown, Add buttons present on writable tabs | OK, **no Add**, invoices list [403 report, handled]; **Edit/Delete buttons still shown** | OK, report shown | **no Add**; invoices list; Edit/Delete shown | **no Add**; Edit/Delete shown |
| Payroll | OK (2 profiles) | **AccessDenied** [403 x4] | OK (1 profile) | **AccessDenied** | **AccessDenied** |
| Parent-Teacher Meetings | OK (2) | OK (2); console: controlled-input warning | **AccessDenied** [403 meetings, notes] | OK (2) | **AccessDenied** |
| /parent-report-cards | not opened | not opened | not opened | stays on "Loading report card..." after 3 s (not investigated) | not opened |
| /shop (Next) | opened last round | | | OK, add to cart 201 | |
| /cart direct load | | | | **OK after fixes**: line item, total, learner dropdown; refresh race verified | |
| /bookshop (Next) | | | | loads (the committed, older 3D scene renders; no console errors); add-to-trolley **not exercised** on this version; **no `/bookshop` nav link** (my edit is in the stash) | |

Not opened this round: teacher/staff/student for `/shop`, `/bookshop`, `/cart` (public pages, same code); admin `/shop` and `/bookshop` were checked in round 1.

## 4. Remaining before release (not fixed)
1. `/bookshop` nav link and the variant-less "Unavailable" guards live only in your stash (re-apply, or tell me to port them onto `release-1`).
2. Fees (and other `ResourceManager` tables) still show Edit/Delete to read-only roles; `allowEdit`/`allowDelete` are not role-gated.
3. On `release-1` the Parents page has no role gating (arrived later with `f57a4cf`): students/teachers see Add, parents see Edit on their row.
4. `/parent-report-cards` loading state; `sectionHeader` and Chart.js dev errors on the dashboard; `seed_shop_products` crash on this branch; `seed_dev_users` lacks an `accounts.StaffProfile`.

---

# Round 3 (follow-up)

## 1. Stash to branches
`git stash branch wip/joe-2026-11-15 stash@{0}` in both repos, everything committed as "WIP: Joe's bookshop rework etc. (from stash)" (`frontend` `a1c5a86`, `distributor` `009bf70`), then back on the previous branches. Both stashes are gone (`git stash list` empty), both `wip/joe-2026-11-15` branches exist, all three repos clean. Branches now: backend `feat/school-data-management`, frontend `feat/school-data-management`, distributor `fix/verified-payments`.

## 2. Distributor `release-1`: my own edits only (`ab36002`)
Re-applied on the committed (older, gamified) bookshop; nothing taken from the WIP branch.
- `/bookshop` link in `GlobalHeader.tsx` (main nav, next to Shop) and `Header.tsx`.
- `/shop` card and product page: no variant means a disabled "Unavailable" button and nothing is added (no more `variant_id: 0`).
- Bookshop: the committed `mapItems` used the **product id** as `backendId` (the id sent to the cart as a variant id); it now uses `variants[0].id`, or `null` with `unavailable` when there is none. `useShop.add` ignores falsy ids, `ProductCard` and `BooklistPanel` show "Unavailable" without a variant id. Side effect: the sample (offline) products on the shelves, which have no `backendId`, can no longer be added (they were added under a made-up id before).
Expect conflicts with `wip/joe-2026-11-15` in `GlobalHeader.tsx`, `Header.tsx`, `app/shop/page.tsx`, `ProductDetailClient.tsx`, `useShop.js`, `ProductCard.jsx`, `BooklistPanel.jsx` when you merge it; the edits are small and listed above.

## 3. Frontend `release-1` (`a6a0dcc`)
- Fees: `Invoices` and `Fee Structures` now get `allowEdit`/`allowDelete` = `canWrite` (ADMIN, STAFF, superuser), same as `allowCreate`; Payments and Defaulters were already read-only. Other `ResourceManager` users (TeacherAssignments, Exams, Library) keep the defaults and still need the same treatment.
- Parents (release-1 version): Add and Edit only for ADMIN or superuser, read-only subtitle otherwise, `AccessDenied` on 403. This release-1 page has no Import button. On `feat/school-data-management` the merge kept feat's own gated Parents page (`canEditParents`, from `f57a4cf`).

## 4. `/parent-report-cards` hang
Cause: `loading` started `true` and was only cleared inside the report fetch, which returns early when no child is selected, so the page sat on "Loading report card..." and its child picker never rendered. The backend serves it fine (`GET /api/exams/report-cards/cbc/<id>/`, 200). Fix: loading only while a request is in flight, single child auto-selected, explicit error text on 403 or failure.

## 5. Merge, builds, browser re-check
- Frontend: `release-1` merged into `feat/school-data-management` (`e6a94c9`; one conflict in `Parents.jsx`, resolved by keeping feat's version). `npm run build` passes on both branches.
- Distributor: no feat branch exists; `fix/verified-payments` fast-forwarded to `release-1` (`fc1aa29`). `next build` (Node 22) **failed on code I had not touched** and now passes after three small fixes: type errors in `app/shop/[id]/page.tsx` and `app/product-category/student-boxes/page.tsx` (`getPublicProducts` already returns the full list), and `useSearchParams` without Suspense on `/track-your-order`. These are in `fc1aa29`; your WIP branch touches the student-boxes file too.
- Browser re-check on backend `fix/private-media` (fresh DB) + frontend and distributor `release-1`:

| Check | parent | student |
|---|---|---|
| Dashboard | OK (`/parent-dashboard`) | n/a |
| Report cards | **OK**: child auto-selected, term "Seed Term 3", card renders (4 API calls, all 200), no console errors | n/a |
| Fees | OK; **no Add/Edit/Delete buttons**; [403 invoices/report handled] | OK; no write buttons; same 403 handled |
| Parents | n/a | "Parent records (read-only)", no Add/Edit/Import, "No parents found" |
| `/cart` direct load | OK: line item, total, learner dropdown | n/a |
| `/bookshop` | nav link present; **Booklist panel Add works** (server cart gained variant 29 "Test Exercise Book 29"; no "Unavailable" shown because all API-backed slots have variants); no console errors | n/a |

Servers stopped afterwards; nothing else changed.
