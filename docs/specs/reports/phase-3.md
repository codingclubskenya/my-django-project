# Phase 3 report: parents

Branch `feat/school-data-management`. Production untouched; dev DB not yet migrated for 0021/0022 (tests run on fresh DBs).

## Also done this turn
- Committed the audit fix (backend `bf68727`): snapshot keys lowercase so every audited model really gets a snapshot, allowlists per model, a central exclude list (passwords, tokens, national ID, NEMIS, DOB, address) applied to snapshots and to anything passed to `log_action`, `StudentProfile` now audited. Needs your eye: audit entries for User, Invoice, Payment etc. now contain field snapshots they never had before.

## What changed
- **Migrations:** `accounts.0021` (`ParentProfile`; relationship choices; unique national ID per school where set) and `0022` (data: free-text relationship to FATHER/MOTHER/GUARDIAN/OTHER, `Parent` and unknown to OTHER; empty profile for every existing parent). Details in `DATABASE-CHANGES.md`.
- **Matching service** `accounts/parents.py`: national ID, then phone (normalised to 254...), then email, always in the school. A phone/email match with a different national ID raises `ParentConflict` (never merged, for Phase 4 to show in the preview). Fills blank fields only. New parents get an unusable password.
- **Parents API** `/api/auth/parents/`: ADMIN and Registrar full and writable; Principal slim and read-only; everyone else 403. Search by name, email, phone, child name, admission number (national ID and alternate phone for ADMIN/Registrar only). Delete refused while children are linked.
- **Directory privacy:** teachers no longer receive a parent's phone from `users/parents/` or `users/?role=PARENT`. ADMIN, Registrar, Principal and the parent themself still do.
- **Links:** Registrar and Principal can list and write `parent-learner-links`; relationship validated against the four codes. Parents still see only their own links.
- Old student import writes a valid relationship code.

## Verification
- Full suite: 582 passed after updating one stale test (`check_duplicates` parent check now runs). 26 new tests in `accounts/test_parents.py`.
- Not done: the probe script, a dev DB migrate, frontend.

## Needs your attention
- **Frontend not changed:** nothing consumes `/parents/`, and `Students.jsx` still sends free-text relationship (the old import maps it; `parent-learner-links` writes would 400 on free text).
- **Decision:** Principal can write parent links (plan says "access"); say if that should be read-only.
- **Phone matching** scans the school's parents in Python (stored phones have mixed formats). Fine for thousands; Phase 4 may want a normalised phone column if imports get slow.
- **Deploy:** back up, `check_duplicates`, `migrate`.
- Root submodule pointers still not bumped.
