# Contributing to Gaugelet

Thank you for helping make Gaugelet more reliable. Keep changes focused, local-first, and honest about the upstream data boundary.

## Before starting

- Search [existing issues](https://github.com/lammworks/Gaugelet/issues) before opening a new one.
- Use the appropriate [issue form](https://github.com/lammworks/Gaugelet/issues/new/choose) for a reproducible bug or concrete feature request.
- Discuss large UI, protocol, dependency, privacy, security, or distribution changes before implementation.
- Report vulnerabilities privately as described in [SECURITY.md](SECURITY.md).

## Development requirements

- An Apple-silicon Mac with macOS 14 or newer.
- A Swift 5.10-compatible Apple toolchain and macOS 14 SDK.
- The official Codex CLI, installed and signed in, for live integration testing.
- [`uv`](https://docs.astral.sh/uv/) for the hash-pinned DMG tooling used by packaging checks.

Install dependencies and run the local gates:

```bash
./Scripts/bootstrap-dmg-tools.sh
swift package resolve
swift build
swift test
./Scripts/check.sh
```

`Scripts/check.sh` is the release-oriented local gate. A source-only change should still run the narrowest relevant tests first, followed by the full gate before review.

## Pull-request workflow

1. Fork the public repository and create a focused branch from `main`.
2. Make the smallest coherent change and add regression coverage.
3. Update public documentation when behavior, privacy, dependencies, installation, or support expectations change.
4. Run the complete applicable checks and record the commands and results in the pull request.
5. Open a pull request against `main` and complete the template.
6. Address review findings without force-pushing away useful review history.

Pull requests require passing CI and maintainer review. A submission does not guarantee acceptance or a release timeline.

## Engineering principles

- Preserve the read-only Codex boundary. Do not access browser storage, Codex credentials, prompts, responses, or project files.
- Treat App Server output as untrusted. Keep timeouts, size bounds, parsing limits, and explicit unavailable states.
- Never invent usage values. Missing upstream windows remain unavailable.
- Keep the five-minute refresh and manual refresh semantics clear; OpenAI's enforced limits are authoritative.
- Maintain macOS accessibility, keyboard behavior, light/dark appearance, and Reduce Motion support.
- Keep system-owned app icons on the stable Core identity; themes belong to the menu bar and in-app presentation.
- Do not add analytics, telemetry, crash upload, persistent usage history, a backend, or a new network destination without prior discussion and privacy review.
- Pin release dependencies and preserve required license notices.

## Tests and evidence

Add or update tests for behavior you change. Depending on scope, include:

- Unit or parser regression tests.
- Signed-out, stale, unavailable, blocked, and demo-state checks.
- Appearance, accessibility, notification, or Launch at Login checks.
- Sparkle configuration and packaging verification.
- Screenshot evidence for visible UI changes, with all personal information removed.

Do not commit generated builds, DMGs, signing material, Sparkle private keys, tokens, personal paths, account details, or unsanitized screenshots.

## Documentation and style

Use concise plain language. Distinguish confirmed behavior from assumptions, and do not describe Gaugelet as affiliated with OpenAI or Apple-verified. Swift changes should follow the surrounding code's naming and formatting rather than introducing an unrelated style system.

By participating, you agree to follow [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

Built by LammWorks.
