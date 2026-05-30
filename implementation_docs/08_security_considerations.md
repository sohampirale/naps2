# Security Considerations

## Credential Storage

### Current Pattern (Follow This)

NAPS2 currently stores sensitive data (OAuth tokens) using the OS keychain:
- **Windows:** `CredentialManager` (P/Invoke to `advapi32.dll`)
- **macOS:** Keychain via `Security.framework`
- **Linux:** `libsecret` (GNOME Keyring / KDE Wallet)

**File to examine:** `NAPS2.Lib/Util/CredentialManager.cs`

For cloud upload:
- OAuth2 refresh tokens → store via `CredentialManager`
- WebDAV passwords → store via `CredentialManager`
- API keys (Custom HTTP) → store via `CredentialManager`
- NEVER store plaintext secrets in config files

### What NOT to Do
- Store credentials in XML config files (NAPS2 config is XML-based)
- Hardcode API keys or client secrets
- Log tokens or upload URLs (check existing NLog config)

## HTTPS Enforcement

- ALL cloud providers must use HTTPS
- The WebDAV provider should warn if URL is HTTP
- Certificate validation should be on by default
- For self-signed certs (enterprise), allow configuration but warn

## OAuth2 Best Practices

Already implemented in the existing `OauthProvider` base class:
- PKCE (Proof Key for Code Exchange) is used by default
- State parameter prevents CSRF attacks
- Local HTTP server on random port for redirect
- Token refresh flow handles expiration

## File Data Security

- Scanned documents may contain sensitive information (contracts, IDs, etc.)
- Upload via HTTPS ensures encryption in transit
- Users should be informed that data is leaving their machine
- For sensitive environments, consider:
  - Client-side encryption option (encrypt PDF before upload)
  - Self-hosted WebDAV option (data stays on own infrastructure)

## Privacy Considerations

- OS keychain prompts appear when tokens are accessed (user visibility)
- Upload progress and status should NOT expose full file paths in logs
- Provider selection and target folder are user-controlled
- No telemetry on what files are uploaded or to where

## Implementation Checklist

- [ ] All provider communication uses HTTPS
- [ ] Secrets stored in OS keychain, not config files
- [ ] OAuth2 uses PKCE + state parameter
- [ ] No secrets logged (check NLog configuration)
- [ ] Certificate validation enabled by default
- [ ] User confirmation before first upload to a new provider
- [ ] Option to disable cloud upload entirely
- [ ] Clear indication when upload is in progress
- [ ] Easy way to deauthorize/revoke access tokens
