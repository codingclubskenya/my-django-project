# Backlog (not scheduled)

Items noted during other work. Not part of any current release.

## Stronger authentication for student and parent accounts
Raised 2026-11-19 (during the staff Create login bug discovery). For later releases.

Today: students sign in with an admission number and a PIN (`/api/auth/student-login/`); parents are created with an unusable password and are meant to sign in through a password-reset link, which needs a real email on the account. Rate limiting and account lockout now cover both (Release 3), but the credentials themselves are weak.

Known gaps to design around:
- **Student PIN strength and handling:** PINs are short and are shown once to the admin; no forced change, no rotation, one shared admission-number namespace across schools unless a school code is sent.
- **Parents without a real email:** parent records imported with a placeholder email (no dot in the domain) and an unusable password cannot sign in by email, phone or reset (production has such accounts). Phone sign-in needs a usable password, so it does not help either.
- **No second factor** for any role (staff and admins included), no sign-in notifications, no way to see or revoke active sessions, refresh tokens are valid 7 days.
- Emails and SMS are not yet delivered from production (see `reports/staff-login-bugs-plan.md`, bug 4), which blocks any reset- or code-based option.

Options to evaluate (not decisions):
- Parents: sign in by phone number with a one-time code by SMS (needs an SMS provider; the OTP design is in `reports/auth-rate-limit-plan.md`, section 5), or invitation links sent by the school; guardian-initiated linking to their children.
- Students: longer random PINs generated per learner with a printable sheet, forced change at first use or school-level rotation each term, optional school code made mandatory, class-teacher reset with audit; optionally a QR sign-in card.
- All roles: TOTP or SMS second factor (mandatory for ADMIN and for Finance/HR/Principal), "new sign-in" notifications, session list with revoke, shorter refresh lifetime, `last_login` surfaced to admins.
- Account recovery that does not depend on a single email: school-admin-assisted reset with an audit trail (exists for temporary passwords) plus rate-limited self-service.
- Data hygiene: report accounts that cannot sign in by any route; make real contact details a requirement for parent records.

## Next release spec: Parent & student sign-in (decided 2026-11-19, not built)
Replaces the "options to evaluate" above for these two roles; the SMS/OTP, second-factor and session-list items stay open.

**Parents**
- Sign in with **phone or email + their own password**, through the same screen and `resolve_login_account` path as staff. Same lockout rules (per account, `lockout.gate`), phone normalised (`core.phone`).
- The first password is set from a link (same uid+token flow as the staff invitation; needs mail from production) or by the school registrar generating one. Parents with a placeholder email and no phone cannot be reached: the data-hygiene report in the list above comes first.

**Students**
- Sign in with **admission number + a password the school sets** (school admin or registrar sets or resets it; temporary, forced change at first use). **Never the parent's password, never the parent's phone**: one phone maps to a parent and all siblings, and a child's failed tries would lock the parent out.
- Lockout is keyed **per student account**; a parent cannot see, set or change the child's password (no parent endpoint touches the learner `User`).
- Every school-side set/reset writes an `AuditLog` row (who, which learner, no password value), as the staff login changes do.

**Identifying the school** (admission numbers are unique only per school). Recommendation, the simplest option: a required **school code** field on the Student tab of the login page (the API already accepts `school_code`; today it is optional), remembered in the browser after the first successful sign-in. School admins print the code on the learner sheet. A wrong code or number gives the same generic error. Not chosen for now: a school picker (lists every tenant publicly) and per-school subdomains (DNS and nginx work); a `/s/<code>` login link that prefills the field is a cheap later addition.

**Acceptance sketch:** two schools with the same admission number sign in separately; a child's lockout leaves the parent signed-in-able; a registrar of school A cannot reset a learner of school B (404); parents have no route to the learner password; audit rows exist for each reset.

## Next-release fixes from the UI smoke test (2026-11-19, none block Release 4)
Source: `reports/ui-smoke-2026-11-19.md` and its baseline/rerun reports (compared against production backend `b31c743`, frontend `745e978`). All are OLD unless marked NEW.

- **`Clubs.jsx:31` "destroy is not a function"** (teacher `/clubs`, page error): `useEffect(load, [])` where `load` is async, so React receives a promise as the cleanup. Wrap it: `useEffect(() => { load(); }, [])`.
- **Hide what the role cannot see instead of calling the API.** Finance/HR get correct 403s but the pages still call: `/health` (`health/records`, `health/visits`), `/discipline` (`discipline/records`, `discipline/appeals`), `/parent-teacher-meetings` (`parent-meetings/meetings`, `parent-meetings/notes`), `/website-builder` (`website/config`), and the fees report (`fees/invoices/report`). Gate on role before fetching, or drop the links from the sidebar for those roles.
- **`website/config` first-visit race** (`backend/website/views.py:80-90`): `.first()` then `.create()` on `WebsiteConfig` for a school; two concurrent first GETs can raise an IntegrityError and return 500 (seen intermittently for admin, on production too). Use `get_or_create` (or catch the integrity error and re-read). Not reproduced with a traceback yet.
- **Phone layout (390px):**
  - `/health`: "Create Record" button clipped at x -12 (NEW, likely from the `1a27ccc` header wrap).
  - Teacher dashboard: the floating "AI Teacher Assist" button overlaps two list buttons (NEW with the UI refresh).
  - `/payroll`: form inputs overlap by about 10px.
  - Clipped tables on `/teachers`, `/enrollments`, `/schools`, `/shop/orders` (wrap them in a horizontal scroller or stack rows on phone).
- Smaller, also old: React warning "`value` without `onChange`" on `/students`; the 402 on teacher `/courses` (an external resource, not investigated).
- Harness note: `scripts/ui_smoke.py` re-runs all of this with one command (`python3 scripts/ui_smoke.py`); pages that fetch `/api/...` on their own origin only work because the script mirrors nginx's `/api` forwarding.
