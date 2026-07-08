# Security Policy

Ultimate De-Slop runs local commands and agent CLIs against user repositories, so safety reports are welcome.

## Supported Versions

| Version | Supported |
| --- | --- |
| `main` | yes |
| tagged releases | best effort |

## Reporting a Vulnerability

Please open a private security advisory on GitHub if possible. If you cannot, open an issue with a minimal, non-sensitive reproduction and label it `security`.

Do not include private repository contents, API keys, tokens, credentials, raw agent transcripts, or proprietary code in public issues.

## Security Boundaries

- Review, arbitration, and verification roles are intended to be read-only.
- Fixing is intentionally scoped to one accepted finding.
- Expected check commands are filtered before execution.
- Runtime logs under `.deslop/runs/` may contain prompts or local paths and should be reviewed before sharing.
