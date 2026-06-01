# Security Policy

APM44 Bridge is a macOS audio utility with a user-space bridge daemon, a menu
bar app, and a HAL Audio Server Plug-in. Security reports are welcome.

## Supported Versions

The current `master` branch and the latest GitHub release receive security
attention. Older tags may be investigated when the fix is small and clearly
backportable.

## Reporting a Vulnerability

Do not open a public issue for a suspected vulnerability.

Use GitHub's private vulnerability reporting when it is available on the
repository. If it is not available, contact the maintainer privately and include:

- affected version or commit
- macOS version and hardware
- reproduction steps
- expected impact
- any logs with secrets removed

## Secret Handling

Never commit:

- Apple Developer private keys, `.p8`, `.p12`, `.key`, or `.pem` files
- App Store Connect key IDs or issuer IDs as defaults
- notarytool credentials, app-specific passwords, or keychain exports
- GitHub tokens, API keys, or bearer tokens

Run this before publishing changes:

```bash
bash scripts/check-secrets.sh
```

## Audio-Specific Safety

Security fixes must preserve real-time constraints. Do not move untrusted input
parsing, logging, allocation, IPC setup, or device discovery into audio
callbacks.
