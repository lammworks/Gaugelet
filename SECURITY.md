# Gaugelet security policy

## Supported versions

| Version | Security fixes |
| --- | --- |
| Latest published `1.0.x` | Supported |
| Older releases, development builds, forks, and third-party redistributions | Best effort only |

## Report a vulnerability privately

Use [GitHub Private Vulnerability Reporting](https://github.com/lammworks/Gaugelet/security/advisories/new). Do not place vulnerability details, credentials, tokens, account data, or exploit code in a public issue.

Include the affected version and build, macOS version, impact, reproduction steps, and a minimal proof of concept when safe. Remove unrelated personal or project data.

Gaugelet does not promise a response SLA or bug bounty. Maintainers will prioritize reports by exploitability, affected users, credential or privacy impact, and risk to the canonical release or update channel.

## High-priority categories

- Exposure or logging of Codex or OpenAI credentials.
- Reading data beyond the documented rate-limit request.
- Arbitrary code execution, command injection, or unsafe process invocation.
- Unsafe handling of untrusted Codex App Server output.
- Bypass of response-size, timeout, or defensive-parsing controls.
- Sparkle signing-key, appcast, release-hosting, workflow, tag, or artifact compromise.
- A privacy statement that materially differs from observed behavior.

General UI defects, ordinary parsing failures, and upstream service outages belong in the [support process](SUPPORT.md) unless they create security impact.

## Security model

Gaugelet:

- Starts the locally installed `codex app-server` and communicates over a private standard-input/output pipe.
- Sends a read-only `account/rateLimits/read` request and relies on Codex for authentication.
- Does not intentionally read browser cookies, Codex authentication files, tokens, API keys, prompts, responses, or project source.
- Treats App Server output as untrusted and bounds response size, execution time, and parsed window count.
- Shows stale, unavailable, or signed-out state instead of treating malformed or missing data as a valid live reading.
- Operates no analytics, telemetry, usage-history, account, or LammWorks backend.
- Uses Sparkle to retrieve a signed update feed and user-approved full-DMG updates from GitHub Releases.

The trust boundary includes the user's Mac, installed Codex CLI, OpenAI services, GitHub and its network providers, the public source repository, build workflows, the maintainer's Sparkle Ed25519 key, and the shipped Sparkle framework.

## Distribution model

Gaugelet 1.0 community releases are ad-hoc code-signed and are not Apple Developer ID signed or notarized. Gatekeeper rejection on first launch is expected; users must follow the documented **Privacy & Security → Open Anyway** path. The release must never be described as Apple-verified.

Sparkle's Ed25519 verification authenticates Gaugelet updates after installation. It does not replace Developer ID signing, notarization, or the initial-download checksum. Users should obtain the initial DMG only from `lammworks/Gaugelet` and compare `Gaugelet.dmg` with `Gaugelet.dmg.sha256`.

Every published artifact is tied to a public commit, includes a SHA-256 digest, and is tested before release.

## Update-key and channel incidents

The Sparkle private key and its encrypted recovery material stay in the release owner's macOS Keychain and outside the repository and GitHub. Only the public key is embedded in the app.

If the private key, GitHub release channel, protected tag, or workflow may be compromised:

1. Stop promotion and release publication.
2. Preserve logs, artifacts, and access evidence.
3. Restrict affected credentials and repository access.
4. Assess whether installed clients can still trust the existing update key.
5. Publish recovery instructions only through a verified unaffected channel.
6. Never replace bytes under an existing immutable version; issue a new version after the trust path is restored.

Loss of the Sparkle private key can strand installed clients. Key recovery testing is therefore a release gate, not an optional backup task.

## Disclosure and remediation

Maintainers should privately acknowledge a report, reproduce it, identify affected versions, prepare and verify a fix, and coordinate disclosure with the reporter. Do not publish exploit details before users have a reasonable opportunity to update.

Built by LammWorks.
