# Gaugelet

**See your Codex and ChatGPT allowance before you hit the limit.**

[![Native for Apple silicon](https://img.shields.io/badge/Apple%20silicon-native-111111?logo=apple)](https://support.apple.com/en-us/116943)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-0A84FF?logo=macos)](INSTALL.md)
[![License: MIT](https://img.shields.io/badge/license-MIT-2F81F7)](LICENSE)

Gaugelet is a free, native macOS menu-bar app for people who adjust Codex model, reasoning, and speed as they work. It shows the ChatGPT-plan allowance windows returned through the local Codex App Server so you can make those tradeoffs before OpenAI enforces a limit.

**[Download Gaugelet 1.0](https://github.com/lammworks/Gaugelet/releases/download/v1.0.0/Gaugelet.dmg)** · [Install guide](INSTALL.md) · [All releases](https://github.com/lammworks/Gaugelet/releases)

> Gaugelet 1.0 is ad-hoc signed and is not notarized by Apple. The first launch requires macOS **Privacy & Security → Open Anyway**. Verify the release checksum before opening it.

<!-- High-resolution Gaugelet product screenshot. -->
![Gaugelet showing Codex and ChatGPT allowance windows in the macOS menu bar](website/public/images/gaugelet-dashboard.png)

## The useful view

An illustrative account might show:

| Counter position | Example reading |
| --- | ---: |
| Overall usage | 78% left |
| Weekly usage | 54% left |
| Model-specific Codex usage | 21% left |

These are example values, not account data. Gaugelet keeps the three canonical positions understandable when those windows are available. A window that is not returned is shown as unavailable rather than filled with an estimate, and additional windows returned by Codex can also appear.

Gaugelet refreshes automatically every five minutes. You can refresh manually at any time. Values come from the local Codex App Server and can drift materially from the ChatGPT interface; during heavy use, either display may move faster or slower than the other. OpenAI's enforced limits remain authoritative.

## Requirements

- An Apple-silicon Mac.
- macOS 14 Sonoma or newer.
- The official [Codex CLI](https://developers.openai.com/codex/cli) installed and signed in with a ChatGPT account that returns rate-limit data.

Gaugelet does not use the OpenAI Platform organization Usage API. That API measures API-platform consumption, not the ChatGPT-plan allowance returned to Codex.

## Install in five steps

1. Install the official Codex CLI, run `codex`, and complete sign-in.
2. Download [`Gaugelet.dmg`](https://github.com/lammworks/Gaugelet/releases/download/v1.0.0/Gaugelet.dmg) and verify it against [`Gaugelet.dmg.sha256`](https://github.com/lammworks/Gaugelet/releases/download/v1.0.0/Gaugelet.dmg.sha256).
3. Open the DMG and drag **Gaugelet** to **Applications**. Launch at Login is unavailable while the app remains on the DMG or in another unsupported location.
4. Open Gaugelet from Applications. If macOS blocks it, open **System Settings → Privacy & Security**, choose **Open Anyway**, authenticate, and confirm **Open**.
5. Click the Gaugelet icon in the menu bar, confirm live data, and optionally enable Launch at Login and usage notifications in Settings.

Do not use Terminal commands that remove quarantine. The complete path and troubleshooting steps are in [INSTALL.md](INSTALL.md).

## How it works

```text
Gaugelet ── private stdio pipe ──> codex app-server ── existing Codex session ──> OpenAI
    │
    └── displays account/rateLimits/read results; stores no usage-history database
```

- Gaugelet starts the locally installed `codex app-server` and makes a read-only `account/rateLimits/read` request.
- Authentication stays with Codex. Gaugelet does not read browser cookies, Codex authentication files, access tokens, API keys, prompts, responses, or project files.
- Live readings stay in memory. Preferences use standard macOS storage.
- Demo, stale, unavailable, blocked, and signed-out states are visibly distinguished. Gaugelet does not substitute plausible values when live data is missing.

See [PRIVACY.md](PRIVACY.md) for the complete data boundary.

## Launch at Login and notifications

Launch at Login uses macOS's supported main-app login-item service. Install Gaugelet in `/Applications` first. If macOS requires approval, Gaugelet offers **Open Login Items Settings**; return to Gaugelet afterward so it can refresh the status.

Usage notifications are opt-in. Gaugelet asks macOS for permission and alerts only for live data crossing your selected threshold or reaching a limit. Demo and stale readings do not trigger alerts. Manage permission in **System Settings → Notifications → Gaugelet**.

Gaugelet does not require Full Disk Access. If macOS displays an unexpected broad privacy-permission request, decline it and [report a bug](https://github.com/lammworks/Gaugelet/issues/new/choose).

## Updates

Gaugelet uses [Sparkle](https://sparkle-project.org/) to check the project's GitHub Releases feed. Automatic checking is offered by the app and, if accepted, runs about once every 24 hours. You can also choose **Check for Updates**. Download and installation always require confirmation; silent installation is disabled.

Sparkle verifies the signed appcast and update enclosure before extraction. That protects the Gaugelet update channel, but it does not make the initial app Apple-notarized. See [PRIVACY.md](PRIVACY.md) for the GitHub request boundary and [SECURITY.md](SECURITY.md) for the trust model.

## Limitations

- Codex App Server is an experimental upstream interface and can change without notice.
- Returned windows, labels, percentages, reset times, and model-specific limits depend on the account and the upstream response.
- A five-minute polling interval, upstream caching, request timing, and different accounting surfaces can produce material differences from ChatGPT's interface.
- Gaugelet is an informational display, not a billing, entitlement, availability, or spending guarantee.
- Gaugelet 1.0 is ad-hoc signed and not notarized. macOS will require the documented Open Anyway flow for the initial installation.

## Build from source

```bash
./Scripts/bootstrap-dmg-tools.sh
swift build
swift test
./Scripts/check.sh
```

The bootstrap step requires [`uv`](https://docs.astral.sh/uv/) and installs hash-pinned DMG tooling into the ignored local build area. The release checks exercise the Swift package, packaging, architecture, icon, DMG, and signature validations available in the repository. See [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.

## Help and project policy

- [Installation](INSTALL.md)
- [Support](SUPPORT.md)
- [Privacy](PRIVACY.md)
- [Security](SECURITY.md)
- [Changelog](CHANGELOG.md)
- [Contributing](CONTRIBUTING.md)
- [Third-party notices](THIRD_PARTY_NOTICES.md)

Gaugelet is independent software. It is not affiliated with, endorsed by, or sponsored by OpenAI. OpenAI, ChatGPT, Codex, and GPT are trademarks or names of their respective owner.

## License

Gaugelet source code is available under the [MIT License](LICENSE). The Gaugelet name, app icon, logo, and brand assets are covered separately by [BRAND.md](BRAND.md).

Built by LammWorks.
