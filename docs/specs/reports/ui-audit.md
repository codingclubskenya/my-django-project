# UI audit: Dashboard, Staff, Classes, Students, Parents, Fees (2026-11-19)

Method: local dev servers (`localhost:5173` + `:8000`), logged in as the seed `admin@demo.com` (Demo School), 2400x1219 viewport, computed styles read via the page, keyboard Tab check. No code changed; branch `feat/ui-refresh` exists, empty.

**Caveat:** the Impeccable plugin is enabled in `~/.claude/settings.json` but its skill is not installed or loaded in this session (not in the skill list, nothing under `~/.claude/plugins`). This is a manual critique, not an Impeccable run. Re-run `/impeccable` after reinstalling if you want its checklist applied on top.

Target direction (School Admin Dashboard canvas): dark green nav `#10241D`, accent `#0E6B52` (deep `#0A4F3C`), text `#15201B`, muted `#56635D`, borders `#E1E7E3`, page `#F3F5F2`, warning `#FCEFD9`/`#8A4B08`, danger `#B42318`, Space Grotesk headings, Inter body.

## Ranked findings

### 1. No design system: four unrelated accents, three font stacks (all pages)
- Nav is navy `#0B1F3A`. Primary actions are blue (Staff "Add Staff", Parents "Add Parent", Fees tabs), orange-red (Classes "New Class", Dashboard "Buy SMS Credits"), amber (Staff/Parents "Bulk Import"/"Import"), and green (Students FABs, Parents "Add child"). Same intent, different colour per page.
- Colours are Tailwind defaults (`oklch` blue-600, amber-500), not tokens. No `#0E6B52` anywhere.
- Fix: define tokens once (CSS variables or Tailwind theme) and map one primary, one secondary (outline), one destructive style. Highest leverage: every later change inherits it.

### 2. Fonts are wrong everywhere
- Computed body and heading font is **Aptos** (`index.css:33`, stack `Aptos, Segoe UI, Trebuchet MS`), which falls back to system sans on Linux/Android. Inter is loaded in `index.html` but only used in one rule (`index.css:86`). Space Grotesk is not loaded.
- All headings render in the body face (H1 24px, brand H1 16px), so there is no type hierarchy beyond size.
- Fix: load Space Grotesk (600/700) + Inter, set `body` to Inter, `h1-h3` and stat numbers to Space Grotesk, drop Aptos.

### 3. Dashboard shows placeholder numbers as live data
- "Last broadcast delivered to 248 recipients", "Intake ↑124", SMS balance "1,250 credits / Ksh 6,250", and the School Diary events (CBC Assessment Day, Science Fair...) look hard-coded. The same page shows 31 enrolled students, streams 8, avg class size 28, but Classes shows no classes. A school admin will trust these numbers.
- Fix: bind to real endpoints or mark unavailable cards clearly (empty state / "Not connected"). Needs a short data check before the visual pass.

### 4. Fees summary does not add up
- Total expected KES 42,000, paid 22,000, pending 27,000. 22,000 + 27,000 is 49,000, not 42,000. Either pending includes something expected excludes (overdue, carried-forward, penalty), or a calculation bug. Not a visual issue but it is the first thing a bursar sees.
- Also: the page is three tinted cards and a tab strip, then 80% empty canvas. Red/green/blue pastel cards rely on hue alone to tell paid from pending.
- Fix: confirm the formula (and label it), add expected/paid/pending as one proportional bar, and show the next action (overdue invoices, record payment) under it.

### 5. `/students` is not a student list
- The route opens "CBC Gradebook & Portfolio" with tabs (Gradebook, Learner Roster, 360 Profile, KNEC Reports), Grade/Learning Area/Stream selects and an empty table. Staff and Parents open straight into a searchable list with Add/Import; Students does not, and registration/import is two floating round buttons bottom-right with no labels.
- Fix: default to Learner Roster (search, filter by class, Add student, Bulk import) like Staff/Parents; move the gradebook under Academics.

### 6. Information density and layout on wide screens
- Main content is 2016px wide on a 2400px viewport; the Staff table spans ~1490px with 12px uppercase grey headers and a lot of dead space between columns. Row actions are 14px text links ("Edit", "Has login", "Deactivate") about 20px tall.
- Header band on every page: "CURRENT SESSION Demo · admin" strip plus "CBC ready / Multi-tenant" pills. It spends vertical space on developer-facing status ("Multi-tenant") that school users do not need.
- Fix: cap content at ~1280-1440px, move the session strip into the user menu, group row actions (primary Edit, overflow menu for the rest), row min height 44px.

### 7. Small text and low contrast
- Table headers: 12px uppercase, colour `oklch(0.551 0.027 264)` (Tailwind slate-500, about 4.6:1 on white; fails on the tinted card backgrounds). Dashboard has 14 text nodes at 11-12px; Classes/Students sub-captions are lighter and smaller still. Sidebar group labels (ACADEMICS...) are tiny letter-spaced caps.
- 7 buttons on the dashboard are under 32px in one dimension. Status pills 12px.
- Fix: minimum 13-14px for anything meaningful, muted text `#56635D` (about 6:1), table header 12px only with `font-weight 600`.

### 8. Empty states and orientation
- Classes opens on "My Classes" ("You have no classes yet...") for the admin; "Manage Classes" is the tab that matters. The page has three overlapping "New Class"/"Add New Class" entry points (header button, table header button, third tab).
- Staff empty/search states are fine; Fees tabs have no counts.
- Fix: admins land on Manage Classes; one New Class button; empty states with the next step ("Import students", "Add your first class").

### 9. Interaction polish
- Search inputs: default browser outline only (`auto`), no brand focus ring. Keyboard Tab does show a ring on nav items (good), but the sidebar uses accordion buttons with chevrons only and no active-page highlight visible on the six pages checked.
- Modals use `bg-black/50` with unconstrained inputs; create-login password is selectable but has no copy button.
- Fix: one focus style (2px `#0E6B52`), active nav state, copy-to-clipboard on the temporary password.

### 10. What works (keep)
- Sidebar collapse control, tab strips, and the status chips are consistent in structure. No console errors on any of the six pages. All images have alt text, no unlabelled buttons on the dashboard. Staff "Has login / Create login" indicator (new) reads clearly.

## Suggested order for the refresh (no code yet)
1. Tokens + fonts + nav colour (findings 1, 2): one PR, whole app changes at once.
2. Shared components: Button, Table (header/row/action menu), PageHeader, Card/Stat, EmptyState, focus ring (7, 9).
3. Fees summary correctness check, then restyle (4).
4. Students default view and Classes landing tab (5, 8).
5. Dashboard: decide real vs removed cards (3), then restyle.
6. Layout width cap and header strip cleanup (6).

## Not checked
Mobile/phone width (the canvas says "PAGEs work at phone width"; the dev browser window is 2400px), non-admin roles, dark mode, the Fees sub-tabs (Fee Structures, Invoices, Payments, Defaulters) and the Classes "Manage Classes" tab.
