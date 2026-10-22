# Gaugelet security policy

## Supported versions

| Version | Security fixes |
| --- | --- |
| Latest published `1.x` | Supported |
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

The trust boundary includes the user's Mac, installed Codex CLI, OpenAI services, GitHub and its network providers, Apple’s Developer ID and notarization services, the public source repository, build workflows, the maintainer’s Developer ID and Sparkle Ed25519 keys, and the shipped Sparkle framework.

## Distribution model

Starting with Gaugelet 1.1.1 (build 4), official releases are Developer ID signed by **Ondemand Technologies Inc (Lavanda)**, team `K567UPF58F`, with hardened runtime enabled, and notarized by Apple. The app and DMG are signed. Apple notarizes the DMG and its contained app, and the notarization ticket is stapled to the DMG. Release publication requires accepted notarization results and successful signature, ticket, and Gatekeeper verification of the final artifact. Notarization is an automated security check, not an endorsement or a guarantee that the app is free of vulnerabilities.

**Historical community releases:** versions 1.0.x and 1.1.0 were ad-hoc signed and not notarized. Gatekeeper rejection on their first launch was expected, and the documented **Privacy & Security → Open Anyway** exception applied to those builds. Their status does not change when a newer signed release is published.

Sparkle's Ed25519 verification authenticates Gaugelet updates after installation. It does not replace Developer ID signing, notarization, or the initial-download checksum. Users should obtain the initial DMG only from `lammworks/Gaugelet` and compare `Gaugelet.dmg` with `Gaugelet.dmg.sha256`.

Every published artifact is tied to a public commit and includes a SHA-256 digest. Release evidence records the checks actually performed; signing and notarization do not substitute for runtime testing.

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
