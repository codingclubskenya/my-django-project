# Staff -> Create login bugs: discovery and plan (2026-11-19)

Discovery only. **No fix is written, nothing is deployed.** Repro tests are in `backend/accounts/test_staff_login_bugs.py` (12 tests, 3 fail on purpose; uncommitted until you approve). Production checks were read-only (counts and booleans, no values, no addresses).

## Summary
| # | Report | Verdict | Root cause |
|---|---|---|---|
| 1 | Editing a staff member's email does not save | The staff record saves; **the login email never changes**, and the page never shows the email, so it looks lost | no sync between `StaffProfile.email` and `User.email` |
| 2 | Role selection does not work | The dropdown is the *staff category* (`StaffGroup`), not an access role. **Nothing in the API or UI can assign Principal / Registrar / Finance / HR / Health** | `UserSerializer.groups` is read-only; groups can only be set in Django admin. In production no user has any group |
| 3 | Staff cannot log in with phone | Cannot be reproduced on production data (all 4 logins resolve by phone and by email). Three real code gaps would break it for later edits and for linked accounts | phone copied once at creation, never synced, never copied when linking an existing user |
| 4 | No email on Create login | Never built, **and production cannot send email at all** (no mail settings, no mail server); password-reset emails are failing silently for the same reason | `create_login` sends nothing; no `EMAIL_*` in the server `.env`; `fail_silently=True` hides it |

## Bug 1: staff email edit
**Reproduced** (`Bug1EmailEdit`, payload built exactly as `Staff.jsx` builds it: blank form overlaid with the list row, then the edit):
- `test_edit_saves_on_the_staff_record`: PUT returns 200 and `StaffProfile.email` updates. So "does not save" is not an API error.
- `test_edit_reaches_the_login_account`: **fails**: `User.email` stays `old@a.test`; signing in with the new email gives 401.
- `test_old_email_still_signs_in_after_the_edit`: passes: the old email keeps working.

**Root cause.**
- `backend/accounts/serializers.py:64-69`: `StaffProfileSerializer` is a plain `ModelSerializer` (`fields = '__all__'`, read-only only `school/created_at/updated_at`); nothing updates the linked `User` (no `update()`, no signal).
- `backend/accounts/views.py:357-381` (`create_login`): copies email, phone and name to the `User` once, at creation (`:374`, and `:380` only fills `profile.email` if blank).
- Frontend `Staff.jsx:161`: the table has no Email column, and the form field (`:217`) edits the staff record only, so after saving there is nothing on screen that shows the change or that the login email is a different thing.
- Production evidence: 4 staff are linked to logins; **1 of the 4 has a staff email that differs from the login email** (case-insensitive), i.e. exactly this.

**Proposed fix.**
1. For a staff record linked to a login, editing email (and phone, see bug 3) updates the `User` in the same transaction. A duplicate is a clear 400 (`User.email` is unique across schools: "That email already belongs to another account").
2. **Security guard (needs your decision):** HR can edit staff, so letting HR change a linked user's email means HR could point the Admin's (or a Principal's) account at an address they control and take it over by password reset. Rule proposed: email/phone changes on a linked login are applied only if the actor is the school ADMIN, or HR editing a login whose role is TEACHER/STAFF and that holds no access group; otherwise the staff record saves but the login fields are left alone and the response says so ("Login email not changed: ask an administrator").
3. Every login email/phone change writes an `AuditLog` row (before/after) and sends a notice to the **old** address (once mail works, bug 4).
4. UI: show a **Login** column (email or phone it signs in with, or "No login"), and in the edit form label the field "Login email" when the record is linked.
5. Tests: the 3 above flip to passing, plus duplicate email, cross-school, HR vs ADMIN guard, audit row.

## Bug 2: role selection
**What the UI sends.** The Staff form has `Group` (`group` = a `StaffGroup` name: Teaching Staff, Non-Teaching Staff, Administration, Management, Support Staff, or a school's own) and a free-text `Staff Role` (`staff_role`) (`Staff.jsx:213-225`). Create login shows "Role: Teacher/Staff" as plain text (`:253`), derived from `group`. Both are labels.

**Reproduced** (`Bug2RoleDropdown`, all pass = they document that nothing happens):
- changing `group` changes the label only; the user's Django groups stay empty and `role` stays STAFF;
- sending `groups`, `role` or `permission_groups` to `staff-profiles/` or `users/<id>/` is ignored; `create-login` ignores a `groups` field.

**Root cause.** `backend/accounts/serializers.py:206`: `UserSerializer.read_only_fields` includes `groups` (read via `get_groups`, `:208-213`); no endpoint writes `User.groups`; the groups `Finance, HR, Health` (migrations 0013/0014) and `Principal, Registrar` (0015) exist but are assigned only in Django admin. **Production: 9 active users, none in any group**, so no one has these permissions today except ADMINs.

**What each group really grants in code** (your table vs `accounts/permissions.py`):
| Group | Your description | In code |
|---|---|---|
| Principal | head teacher, see and manage most of the school | manage classes (`can_manage_classes`, `:448`); **read-only** on staff records (slim, no national ID, `:433`) and learner/parent records (`:438`, `:443-445`); cannot create/edit learners or staff. Not "manage most": the label should say "see most records, manage classes" unless you want Principal widened |
| Registrar | admissions/office, manage classes and learner records | matches: classes, learners, parents (`:443`, `:547`) |
| Finance | bursar, fees and payments | matches (`:141-147`) but **requires login role STAFF** |
| HR | HR/admin, staff records | matches: staff records create/edit/import (`:520`) and recruitment (`:150-156`); **requires login role STAFF** |
| Health | school nurse, health records | matches (`:299-307`); any role |

**Proposed fix.**
1. New **Access** control: in the Create login modal and for linked staff rows, a multi-select of the five groups with your descriptions (corrected for Principal as above). API: `create-login` accepts `roles: [...]`, and `PUT staff-profiles/<id>/access-roles/` sets them (adds/removes only these five names; never touches other groups).
2. **Only the school ADMIN (and platform admin) may assign**: HR can edit staff, so letting HR grant roles would let HR make themselves Principal. Others get 403.
3. **Role compatibility:** Finance and HR need login role STAFF. If either is chosen for a Teaching Staff person, the login is created as STAFF (and the modal says so) instead of silently giving a useless group. Principal/Registrar/Health keep TEACHER/STAFF as derived today.
4. `AuditLog` row per grant/revoke; groups are global Django groups but every check also requires `user.school`, so no cross-school effect (test it).
5. The old `Staff Role` free text is renamed "Job title" in the form (it grants nothing), to stop the confusion.
6. Tests: assign/revoke, ADMIN-only, HR refused, Finance forces STAFF, another school's staff 404, audit rows, unknown group name 400.

## Bug 3: phone login
**Checked, all pass or reproduce as noted** (`Bug3PhoneLogin`):
- phone from the staff record works right after Create login (typed `0712 345 678`, `+254...`): passes;
- **fails:** phone edited on the staff record later is not copied to the `User`; the new number gets 401, the old one still works (`serializers.py:64` / no sync, same cause as bug 1);
- **fails:** an existing user linked by email at import (`accounts/staff.py:23-39` `find_linkable_user`, used at `views.py:434`) does not get the staff phone, so that user cannot sign in by phone;
- a number shared by two login users gives the generic 401 by design, email still works (spec rule);
- a staff record with no phone gives a login with no phone (phone login impossible; nothing tells the admin).

**Production data (read-only):** 41 staff records, 4 with logins; for those 4: phone present, equal to the login phone, resolves to the same user by phone and by email, no lockout rows, no shared numbers among login users; 0 staff phones are non-Kenyan-mobile numbers. So **the data does not explain a failure today.** What it does show: 37 of 41 staff have **no login at all**, and **3 of the 4 logins are still on their temporary password** (phone sign-in works, then the app forces a password change; that can read as "login failed"). Also `last_login` is never updated by the API sign-in (`views.py:56-80`), so nobody can tell who has ever signed in (all four show none).

**I need the exact failing case from you:** which staff member, what was typed, and what the screen said (generic error vs "Too many attempts" vs the change-password page). It decides whether this is one of the code gaps below or something else.

**Proposed fix (independent of that answer):**
1. Phone sync with the same rules and guard as email (bug 1), also when a record is linked at import and when a staff record gains a phone.
2. Create login and the Staff row show **"Phone login: yes / no phone / number also used by <n> other login(s)"** so the admin knows beforehand (never shows the other people).
3. API sign-in sets `last_login` (and the Staff row can show "Last sign-in").
4. `check_duplicates` already reports shared phones; add the same count to the Staff page header when above 0.
5. Tests: the two failing tests flip to passing, plus shared-number warning and `last_login`.

## Bug 4: no email, and production cannot send email
**Reproduced** (`Bug4NoEmail`): after Create login `mail.outbox` is empty. **Root cause 1:** `create_login` (`views.py:357-381`) has no send; the temporary password is only returned to the admin on screen.

**Production, read-only (key names/booleans only):**
- The server `.env` has **none** of `EMAIL_BACKEND, EMAIL_HOST, EMAIL_PORT, EMAIL_HOST_USER, EMAIL_HOST_PASSWORD, EMAIL_USE_TLS, DEFAULT_FROM_EMAIL` (0 lines each). `FRONTEND_URL` is set and equals `https://erp.codingclubskenya.com` (the link host would be right).
- The deployed settings therefore resolve to `smtp.EmailBackend` (`settings_production.py:145`), host `localhost`, port 25, no TLS, no user, no password; sender `noreply@codingclubs.co.ke` (a different domain from the site's).
- No mail server is running on the box (`postfix`/`exim4` inactive, nothing listening on 25/465/587). **Every email the system tries to send fails.**
- **Root cause 2:** the reset-email tasks I added call `send_mail(..., fail_silently=True)` (`accounts/tasks.py:42` and `:61`), so the failure is swallowed: `logs/celery.log` is empty (0 bytes), no errors in the `epk-celery` or `gunicorn` journals. **Password reset has therefore never delivered an email since Release 3 went live at 13:04 today** (and probably never worked on this server). I did not test that against a real mailbox; this is inferred from the config and the absence of a mail server, and I will not trigger one without your OK.

**Proposed fix, in order:**
1. **You choose how mail is sent** (decision below), then I give you the exact `.env` lines (SMTP host, port 587, TLS, user, password from a secrets source, `DEFAULT_FROM_EMAIL` on a domain that has SPF/DKIM) and a `manage.py send_test_email you@...` command to prove it before anything depends on it.
2. Stop swallowing errors: `fail_silently=False`, catch, log `event=mail_failed` (no address, no body) to `security.auth`, and retry with backoff in the Celery task (3 tries); the same for the legacy reset task.
3. Production settings: fail fast if `EMAIL_HOST` is still `localhost` with no MTA, like the Redis check, or at least a `check --deploy` warning.
4. **Create login email (recommended design):** send a "set your password" email with a time-limited link (the same uid+token flow as reset, expires per `PASSWORD_RESET_TIMEOUT`), the school name, how to sign in (email or phone), and the login URL, **no password in the email**. A checkbox "Email the invitation" (on by default when the staff record or the entered email is valid). The temporary password stays on screen as a fallback only if the send fails or the box is unticked. Confirming the link clears `must_change_password`. Alternative (weaker, simpler): email the temporary password itself.
5. Tests: invitation queued with the right link host, no password in the body, failure is logged and retried, unticked box sends nothing, cross-school, throttled per address (reuses the 3/hour limit).

## UI: does `feat/ui-refresh` cover the sidebar and layout?
Checked on the branch (code diff, plus the dashboard at desktop, 820 px and 390 px via same-origin frames; the window itself cannot be resized in this browser). Screenshots: `staff-login-bugs-plan/ui-refresh-phone-tablet.jpg`, `staff-login-bugs-plan/ui-refresh-phone-drawer.png`.

**What it covers:** brand colours and fonts (tokens, Space Grotesk/Inter); sidebar colours: navy, orange active pill (works on desktop and in the phone drawer), white hover wash, neutral role pill and icon tiles, section labels 12 px with more contrast, width capped at 288 px; one primary orange action per audited screen; shared Button/StatusBadge; the dashboard header overlap fix **on desktop only**.

**What it does not cover (sidebar `Layout.jsx` changed only 18 lines: colours, width, label size):**
| Area | Gap |
|---|---|
| Grouping | all six groups start **collapsed**, so the sidebar opens as six headings and no pages; the group containing the current page is not auto-expanded and a group header has no "contains the active page" cue |
| Icons | many near-identical (Students, Parents, Teachers, Staff, Enrollments, Teacher Assignments; Course Flow and Academic Setup); the group icon tiles are not shown when a group is open; "Dashboard" is repeated inside Academics |
| Collapse on mobile | the drawer, hamburger and overlay work, but the desktop collapse chevron is also shown inside the phone drawer where it does nothing useful; the drawer has two nested scrollbars (aside and nav) |
| Spacing | brand block uses `text-2xl` and wraps "EduGuide Schools" onto two lines; description text and pill stack tall; group rows and item rows use different paddings |
| Main layout | the "CURRENT SESSION / CBC ready / Multi-tenant" strip is still on every page; no max content width (very wide tables on big screens); every page builds its own header and padding; **at phone and tablet widths the page header band overlaps the first row of cards** (`sticky top-[56px]` still applies below `lg`; seen in the frames above; on the live site the overlap also happens on desktop because the `lg:top-0` fix is only on `feat/ui-refresh`) |
| Pages | `<Button>` adopted on Staff and Parents only; about 550 `status-*` uses and 219 raw palette classes remain unreviewed; 14 literal hex values (school website builder, intentionally) |
| Auth screens | **`feat/ui-refresh` does not contain the login/phone/429 work** (commits `099e2fa`, `745e978`): on that branch the login field is still `type="email"`, which blocks phone numbers in the browser |

**Recommendation:** treat these five as release blockers for the sidebar/layout ("step 3"): auto-expand the active group, distinct group/item icons, hide the collapse chevron in the phone drawer and use one scroll area, brand-block spacing, and the header overlap below `lg` plus remove the session strip. Defer the Button adoption across the other pages and the status-colour review to a later step. If you prefer a smaller release, the minimum is the overlap fix plus auto-expand.

## Plan: one release with `feat/ui-refresh` and the fixes (nothing merged yet)
1. **Prerequisite, yours:** decide how mail is sent (below) and provide credentials; DNS (SPF/DKIM/DMARC) for the sender domain.
2. **Backend** on `feat/school-data-management`: bugs 1 to 4 backend (sync + guard + audit, access roles endpoint, phone warnings, `last_login`, invitation email, mail-failure logging and retries, `send_test_email`). Tests first, full Postgres suite, commit, push.
3. **Frontend, one integration branch:** cut `release/ui-and-staff-login` from `feat/school-data-management` (which has the login work), merge `feat/ui-refresh` into it (expect conflicts in `Login.jsx`, `ChangePassword.jsx`, `ForgotPassword.jsx`, `ResetPassword.jsx`, `api.js`, `AuthContext.jsx` where the class sweep touched files the auth work also touched; auth logic wins, tokens/classes from the refresh win), then add the Staff page changes (Login column, Access control, Login email label, invitation checkbox) and the sidebar/layout items above. Check: `vite build`, esbuild parse of every touched file, browser pass of the login paths (email, phone, student, temp password, forgot, 429, change password) **on the integrated branch**, and before/after screenshots of Dashboard, Staff, Classes, Students, Parents, Fees, Login at desktop and phone width.
4. **Rehearsal:** fresh prod dump into a throwaway Postgres, run the migrations (none expected for the backend; access roles use existing groups), exercise Create login, edit, roles, invitation (to a local mail catcher), then `send_test_email` on the real server only after you approve.
5. **Merge into `feat/school-data-management`** (frontend and root) only after you approve the integrated branch, so the root records one branch (the saved rule: frontend on `feat/school-data-management` before any root bump).
6. **Release order:** `.env` mail settings + `send_test_email` proof, then backend (`deploy-release.sh`), then frontend (`STAGE_ONLY=1`, wait, swap), then checks: Create login with "email the invitation" to a real test mailbox, edit email, assign a role (and sign in as that user to confirm the permission), phone sign-in, sidebar on a phone.
7. Rollback: backend and frontend are separate steps with the printed rollback commands; the invitation email is the only external effect.

## Decisions needed from you
1. **Bug 3:** the exact failing case (staff, what was typed, what the screen said).
2. **Mail:** which service sends it (a transactional SMTP provider such as Brevo/Mailgun/SendGrid/Amazon SES, or SMTP of an existing mailbox such as Google Workspace/Zoho), sender address and domain. Until this is set, password reset and invitations cannot work.
3. **Create login email:** set-password link (recommended) or temporary password in the email?
4. **Guard:** only the school ADMIN changes a linked login's email/phone and assigns access roles (recommended), or HR too for TEACHER/STAFF logins without roles?
5. **Principal:** keep the code as is and relabel it, or widen Principal to edit learners/staff?
6. **UI scope for this release:** the five blockers above, or the smaller minimum?
7. Should Finance/HR always force the login role to STAFF (recommended), or refuse the combination for Teaching Staff?

## Not changed
No code outside the uncommitted repro test file; nothing deployed; no email sent; production touched read-only (counts and booleans only). The local frontend was switched to `feat/ui-refresh` for the layout check and is back on `feat/school-data-management`.
