# Changelog

All notable Gaugelet changes are documented here. Gaugelet follows [Semantic Versioning](https://semver.org/) beginning with 1.0.0; the integer bundle build increments independently.

## [1.2.0-beta.1] - 2026-11-19

Build `5` — Beta release: Grok and Cursor plan usage.

- Optional Grok and Cursor plan usage in the menu-bar popover. ChatGPT stays on the Codex reading. The Cursor tab stays off until you enable it.
- Grok credits are read from the Grok CLI sign-in (`key` under `https://auth.x.ai` in `~/.grok/auth.json` or `$GROK_HOME/auth.json`) and shown as their own rows beside the Cursor plan. An expired or unreadable sign-in names the file and the JSON keys present, without values.
- A Cursor timeout or unsupported payload keeps the last reading when Grok cannot be read. When Grok can be read, that pool stays visible and the Cursor row says whether the Cursor desktop app is not signed in, the saved token is sealed, the usage request failed, or the request timed out. The row tooltip names the source, HTTP status, or timeout, and never the token.
- Current Cursor builds seal `cursorAuth/accessToken` as `cursor-safe-storage:v1`. Gaugelet unseals it in memory with that app’s Keychain item (`Cursor Safe Storage` / `Cursor Key`, or `Cursor Nightly Safe Storage` / `Cursor Nightly Key`, or the Insiders item named the same way) and still accepts a plaintext token in the same database key. The sealed text is not sent as the bearer.
- A background refresh reads that Keychain item without showing the login-keychain Allow dialog. Turning Cursor usage on, or refreshing the Cursor tab, can show that dialog so you can allow the read.
- Allowance alerts stay on the Cursor sign-in when the Grok reading is missing or fails.
- The Grok weekly number is one shared plan. Cursor, Grok Bot, Bugbot, Chat, Voice, and Grok Build are shares of that plan, shown as percent of the plan used. Grok Build is the `grok` coding CLI and is not a second allowance. Older Cursor app plans keep the distinct included meters that account returns.
- The menu bar shows ChatGPT and Grok remaining together when both are available. A stale service is marked, a blocked ChatGPT window stays visible, and the tooltip names loading and signed-out separately from unavailable. A Cursor sign-in with no Grok sign-in says Grok is signed out, not unavailable. Demo data shows the shared weekly pool on the Grok mark. A Cursor app row can still be pinned without replacing the ChatGPT reading when Cursor cannot be reached.
- A rejected Cursor sign-in stays labeled as Cursor. The Grok card names `~/.grok/auth.json` or `$GROK_HOME/auth.json` and keeps the key names when that file cannot be used.
- Privacy, security, and data-source notes name the read-only token key and the Cursor and xAI usage requests.
- Allowance alerts compare Cursor and Grok readings only when both carry the same in-memory session identifier. Reset times outside a supported range stay unavailable.

## [1.1.1] - 2026-09-17

Build `4` — Developer ID signing and Apple notarization.

- First Developer ID signed release, using **Ondemand Technologies Inc (Lavanda)**, team `K567UPF58F`, with hardened runtime enabled.
- Developer ID signed app and DMG, notarized by Apple with the ticket stapled to the DMG; normal first launch replaces the historical community build’s **Open Anyway** exception.
- Retains Gaugelet’s existing Sparkle update key and user-confirmed update flow.
- Installation, support, and security documentation distinguish the signed release from historical ad-hoc builds.

## [1.1.0] - 2026-09-11

Build `3` — allowance and account activity.

- Stable shared, weekly, and special-bucket rows, with a selectable menu-bar counter. Missing pinned counters stay unavailable.
- Independent threshold and cap alerts for every returned window; optional recovery alerts require a fresh successful reading. Account changes do not generate crossing alerts when identifiers are supplied.
- Earned reset count, earliest known expiry, and scoped credit balances. Manage usage opens OpenAI; no redemption or purchase actions.
- Refresh on open when at least a minute old, on wake, and at the first 30-second timer tick after an expected reset; background polling stays five minutes.
- Optional account token activity showing the last seven reported dates and lifetime tokens. Missing data stays unavailable; no local history database.
- Retain up to 128 allowance windows and report overflow explicitly.
- Task-status monitoring remains unsupported: a standalone App Server only sees its own loaded tasks.
- No model/speed guidance or additional inference calls.

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

[1.2.0-beta.1]: https://github.com/lammworks/Gaugelet/releases/tag/v1.2.0-beta.1
[1.1.1]: https://github.com/lammworks/Gaugelet/releases/tag/v1.1.1
[1.1.0]: https://github.com/lammworks/Gaugelet/releases/tag/v1.1.0
[1.0.1]: https://github.com/lammworks/Gaugelet/releases/tag/v1.0.1
[1.0.0]: https://github.com/lammworks/Gaugelet/releases/tag/v1.0.0

Built by LammWorks.
