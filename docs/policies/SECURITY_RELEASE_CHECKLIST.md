# Security Release Checklist

Publication status: release-readiness checklist for security-sensitive release
gates. Keep unresolved verification state synchronized with
`PUBLIC_RELEASE_READINESS_TRACKER.md`.

## Blockers

- No secrets, API keys, signing files, or local environment files in public artifacts.
- No direct GIF provider API key embedded in public clients.
- Log redaction covers tokens, URLs with secrets, push endpoints, OAuth codes, Matrix tokens, refresh tokens, and E2EE material.
- Release builds do not enable debug logging, certificate bypasses, cleartext transport, or test endpoints.
- E2EE/session storage has platform verification notes for iOS.

## High-Risk Manual Verification

- Matrix access tokens and refresh tokens are stored as securely as current platform support allows.
- E2EE device keys, cross-signing state, and recovery keys are not exported in logs.
- Push payloads do not reveal encrypted message content unless the user explicitly accepts that behavior.
- URL preview direct fetches block localhost/private-network/internal metadata endpoints.
- WebView or OAuth flows use system browser/external auth where possible.
- File import/export paths have containment and traversal checks.

## Release Evidence

Attach command output, screenshots, or review notes for each checked item. Do not include actual secret values in the evidence.
