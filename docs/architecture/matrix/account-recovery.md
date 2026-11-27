# Account Recovery

Last updated: 2026-06-11

## Scope

Account recovery is an Inter Galactic feature for operator-approved Matrix
accounts on configured recovery domains. It is not a Matrix-wide recovery
service and the app must not imply that Inter Galactic can reset passwords for
arbitrary homeservers.

This feature recovers Matrix account password access. It is separate from
Matrix encrypted history recovery:

- Recovery codes reset the account password.
- Matrix recovery keys restore encrypted message history.
- The forgot-password flow must never ask for a Matrix encryption recovery key.

TOTP/authenticator recovery is an optional password-recovery factor. It is not
login MFA in this slice. The app exposes setup only when the Inter Galactic
recovery backend advertises `status.totp.available == true`.

## App Entry Points

Existing accounts:

- Account Settings -> Security -> Account security. Recovery codes live beside
  password management in the same section so password access and recovery
  access are handled together.
- Users on configured recovery domains can check status, generate recovery
  codes, and regenerate a fresh code batch.
- Authenticator app setup appears only when the server advertises TOTP support
  and recovery codes are already enrolled.
- Other accounts see homeserver-controlled recovery messaging.

New accounts and first local login:

- After successful login or registration on a configured recovery domain, the
  login flow checks account-recovery status.
- If recovery codes are not enrolled and the prompt was not previously
  dismissed for that account, the app shows a setup prompt.
- The app stores only prompt-dismissal metadata in preferences. It never stores
  generated recovery codes.

Forgot password:

- Login page exposes "Forgot password?" below password login.
- For configured recovery domains, the app runs the Inter Galactic recovery
  flow with recovery-code or authenticator factors.
- For other homeservers, the app shows generic homeserver-controlled recovery
  messaging and offers to open the homeserver site.

## API Client

App code lives in:

```text
intergalactic/lib/client/account_recovery/account_recovery_api_client.dart
```

The default endpoint is the Inter Galactic account-recovery API configured for
the build. Source builds can override it with:

```text
INTERGALACTIC_ACCOUNT_RECOVERY_ENDPOINT
INTERGALACTIC_ACCOUNT_RECOVERY_ALLOWED_HOMESERVERS
```

Authenticated enrollment methods request a Matrix OpenID token from the Matrix
SDK and send:

```text
Authorization: Bearer <Matrix OpenID access token>
X-Matrix-Server-Name: <Matrix OpenID matrix_server_name>
```

The app intentionally does not send the full Matrix access token to the
Inter Galactic API for account-recovery enrollment.

Client methods:

- `getStatus`
- `generateRecoveryCodes`
- `regenerateRecoveryCodes`
- `startReset`
- `verifyReset`
- `verifyResetWithTotp`
- `completeReset`
- `startTotp`
- `verifyTotp`
- `disableTotp`

`verifyReset` now sends `factor: recovery_code` plus the existing
`recovery_code` field so older server code can keep reading `recovery_code`.
`verifyResetWithTotp` sends `factor: totp` plus `otp`. Forgot-password factor
verification remains unauthenticated and must preserve no-enumeration behavior.

TOTP setup/disable methods use the same OpenID-proof headers as recovery-code
enrollment. `startTotp` expects:

```json
{
  "setup_session_token": "...",
  "otpauth_uri": "otpauth://...",
  "manual_secret": "...",
  "digits": 6,
  "period": 30,
  "expires_at": "..."
}
```

`verifyTotp` sends `setup_session_token` and `otp`. `disableTotp` sends the
current `otp`. The app still treats `501 totp_not_enabled` as unavailable so
builds paired with a backend that has not enabled TOTP keep the
planned/unavailable UI.

## Enrollment Flow

1. The settings panel checks status for the selected Matrix account.
2. If recovery codes are not enrolled, the user can generate a code batch.
3. Generated codes are shown in a non-dismissible display-once dialog.
4. The user can copy the codes and must confirm they saved them before closing.
5. Regeneration requires confirmation because it invalidates unused old codes.
6. If TOTP is available, users can enable authenticator app recovery only after
   recovery codes are enrolled.
7. TOTP setup shows a QR code from `otpauth_uri`, a selectable/copyable manual
   secret, and verifies the current authenticator code before enabling.
8. TOTP disable is destructive and requires a current authenticator code.

The app does not store recovery codes, passwords, reset-session tokens, TOTP
setup-session tokens, TOTP secrets, OTPs, or Matrix recovery keys.

## Reset Flow

1. User selects homeserver on login page.
2. User opens "Forgot password?".
3. For configured recovery-domain accounts, the app sends `reset/start` with
   the trimmed `username` value entered by the user for the selected recovery
   domain. This is the local account identifier, not a fully-qualified Matrix
   user ID.
4. The UI advances without learning whether the account exists.
5. The user chooses recovery code or authenticator app.
6. `reset/verify` verifies the selected factor and returns a short-lived reset
   session token.
7. The user enters a new password.
8. `reset/complete` submits the reset session token and new password.
9. The completion screen tells the user to sign in again and reminds them that
   encrypted history may still need Matrix recovery after login.

## Redaction

App log redaction covers account-recovery secret shapes before developer-log
copy/save and bug-report export:

- `recovery_code`
- `recovery_codes`
- `reset_token`
- `reset_session_token`
- `totp_secret`
- `totp_code`
- `otpauth_uri`
- `manual_secret`
- `setup_session_token`
- `totp_setup_session_token`
- `otp`
- `one_time_password`
- `authenticator_code`
- `IG-XXXX-XXXX-XXXX` style recovery codes

Do not log request bodies from account-recovery calls. In particular, do not
log OpenID tokens, reset-session tokens, recovery codes, passwords, TOTP
setup-session tokens, otpauth URIs, manual secrets, OTPs, or TOTP material.

## Backend Contract

The app and backend use the OpenID-proof contract required by the account
recovery plan. Authenticated enrollment/status calls send a Matrix OpenID token
and Matrix server name. The backend validates that proof through Synapse OpenID
userinfo and accepts only Matrix subjects that match the configured recovery
domains.

Forgot-password reset endpoints remain unauthenticated until a recovery factor
is verified and a short-lived reset-session token is issued.

The backend must promote `totp.available` in status and implement
`/totp/start`, `/totp/verify`, `/totp/disable`, and `reset/verify` with
`factor: totp` before the app enables authenticator setup. Until then, the app
keeps TOTP setup gated off.

## Limitations

- Configured recovery domains only.
- No email or phone recovery.
- TOTP is recovery-only, not login MFA.
- TOTP setup requires backend endpoint support.
- No local storage for generated recovery codes.
- No generic account-management discovery for remote homeservers.
- Full live validation depends on account-recovery deployment being enabled
  with live secrets.
