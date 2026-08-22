# Changelog

All notable Gaugelet changes are documented here. Gaugelet follows [Semantic Versioning](https://semver.org/) beginning with 1.0.0; the integer bundle build increments independently.

## [1.0.1] - 2026-08-22

Build `2` — focused menu-bar presentation update.

### Changed

- Replaced the themed menu-bar card with a compact, monochrome half-gauge based on the supplied 16-point SVG.
- The new menu-bar glyph uses macOS template rendering so it adapts cleanly to light and dark menu bars.
- Themes remain available for Gaugelet’s in-app presentation; Finder and notifications continue to use the stable blue Core icon.
- Download links now use GitHub’s stable latest-release asset URLs.

## [1.0.0] - 2026-08-21

Build `1` — first public release under the Gaugelet name.

### Added

- Native Apple-silicon macOS 14+ menu-bar app for Codex allowance visibility.
- Read-only usage retrieval from the locally installed Codex App Server.
- Canonical overall, weekly, and model-specific counter positions when available, plus additional windows returned by Codex.
- Explicit unavailable state for an upstream window that is not returned; no fabricated percentages.
- Five-minute automatic refresh and an on-demand refresh control.
- Loading, live, stale, unavailable, blocked, demo, and signed-out states.
- Optional low-allowance and limit-reached macOS notifications for live data.
- Launch at Login through `SMAppService.mainApp`, with install-location and macOS-approval guidance.
- Seven menu-bar and in-app icon themes, while Finder and notification surfaces retain the stable blue Core icon with transparent corners.
- Sparkle 2.9.6 update checks using a signed appcast and Ed25519-authenticated full-DMG updates.
- User confirmation for update download and installation; silent installation and system profiling are disabled.
- Privacy, support, security, contribution, installation, community-release, notarized-release, and launch documentation.

### Changed

- Product identity changed from the pre-release Dipstick name to Gaugelet.
- The app and documentation now distinguish Gaugelet's local Codex App Server reading from ChatGPT's interface. Values can drift materially and either display may move faster or slower during heavy use; OpenAI's enforced limits remain authoritative.
- Finder, notification-permission, and delivered-notification icons use one stable signed Core identity instead of theme-driven bundle mutation.
- The Core theme uses the app icon's blue brand color and consistent icon sizing.
- Menu-bar presentation redraws when macOS appearance changes.

### Security and privacy

- Codex App Server output is treated as untrusted and bounded by timeout, response-size, window-count, and defensive-parsing controls.
- Gaugelet does not read or copy browser cookies, Codex authentication files, tokens, API keys, prompts, responses, or project files.
- Gaugelet has no analytics, telemetry, account service, developer backend, or persistent usage-history upload.
- Sparkle update requests go directly to GitHub Releases with system profiling disabled.

### Distribution

- Gaugelet 1.0 is free and source-available under the MIT License.
- The community DMG is ad-hoc signed and not Apple-notarized. Initial installation requires macOS **Privacy & Security → Open Anyway**.
- Sparkle authenticates updates but does not replace Apple Developer ID signing or notarization.
- The primary executable is arm64; vendor-supplied Sparkle internals retain their shipped architectures.

### Known limitations

- Codex App Server is experimental and may change without notice.
- Gaugelet requires a separately installed, authenticated Codex CLI.
- Returned counters vary by account and upstream response; some windows may be unavailable and additional windows may appear.
- Gaugelet is informational and cannot guarantee billing, entitlement, reset timing, or continued access.

## [0.9.0] - Historical pre-release

The internal 0.9 line established the Gaugelet name, native menu-bar interface, demo states, icon themes, notification threshold, and initial release-hardening checks. It was not the public 1.0 release and did not include the final Sparkle channel.

[1.0.1]: https://github.com/lammworks/Gaugelet/releases/tag/v1.0.1
[1.0.0]: https://github.com/lammworks/Gaugelet/releases/tag/v1.0.0

Built by LammWorks.
