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
