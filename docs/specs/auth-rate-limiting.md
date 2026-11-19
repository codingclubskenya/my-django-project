# 10. Authentication Rate Limiting and Brute-Force Protection

Implement strict authentication rate limiting across the entire school management system.

## A. Login Attempts

- Allow a maximum of 5 failed login attempts.
- Apply the limit to both email and phone-number authentication.
- After 5 consecutive failed attempts, temporarily lock authentication for that account for 15 minutes.
- Reset the failed-attempt counter after successful authentication.
- Do not allow switching between email and phone login to bypass the limit.
- Track attempts using both normalized account identifiers and IP addresses.
- Avoid permanently locking accounts because of repeated failed attempts.

## B. OTP Verification

- Maximum 5 incorrect OTP verification attempts per OTP challenge.
- Invalidate the OTP after 5 failed attempts.
- Require a new OTP request after invalidation.
- Add a 60-second cooldown between OTP resend requests.
- Limit OTP generation to a reasonable number per account and IP, for example 5 requests per hour.

## C. Password Reset

- Apply rate limiting to password reset requests.
- Prevent repeated password-reset attempts from being used to enumerate registered accounts.
- Return consistent responses whether an account exists or not.

## D. API Protection

Apply Django REST Framework throttling or an appropriate custom rate-limiting mechanism to:

- Login endpoints.
- OTP generation endpoints.
- OTP verification endpoints.
- Password reset endpoints.
- Password change endpoints.

Use Redis-backed shared rate-limit storage in production rather than relying on in-memory counters.

## E. Security Requirements

- Use atomic database operations or Redis operations to prevent concurrent requests bypassing limits.
- Normalize phone numbers and email addresses before counting attempts.
- Prevent bypassing restrictions by alternating between email and phone login.
- Do not expose whether an email or phone number belongs to an existing account.
- Log suspicious authentication activity without recording passwords or OTP values.
- Provide administrators with visibility into suspicious login activity.
- Ensure rate limits work across multiple application workers and servers.

## F. Testing

Verify:

1. Five incorrect login attempts trigger a 15-minute lockout.
2. Both email and phone login share the same account-level lockout.
3. Switching IP addresses does not bypass the account-level limit.
4. Switching identifiers does not bypass the account-level limit.
5. Successful login resets the failed-attempt counter.
6. OTP expires after five failed verification attempts.
7. OTP resend cooldown works.
8. Password reset endpoints are protected.
9. Concurrent requests cannot bypass the five-attempt limit.
10. Legitimate users can log in after the lockout expires.

Document the rate-limit configuration so administrators can adjust it safely.
