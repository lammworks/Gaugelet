# Gaugelet support

Support is best effort. Gaugelet has no guaranteed response or resolution time.

## Start here

1. Confirm you are using an Apple-silicon Mac with macOS 14 or newer.
2. Confirm the official Codex CLI is installed, launches in Terminal, and is signed in.
3. Install Gaugelet in `/Applications`; do not run it from the DMG.
4. Quit and reopen Gaugelet, then use the manual refresh button once.
5. Note whether Gaugelet says live, stale, unavailable, demo, blocked, or signed out.
6. Choose **Check for Updates** and install a newer release if one is offered.

Opening ChatGPT in a browser does not sign the Codex CLI in. ChatGPT plan, billing, entitlement, and account-enforcement questions must go to official OpenAI support.

## Installation and Gatekeeper

Gaugelet 1.0 is ad-hoc signed and not notarized. A first launch is expected to be blocked by Gatekeeper.

1. Try to open `/Applications/Gaugelet.app` once.
2. Open **System Settings → Privacy & Security**.
3. In the Security section, choose **Open Anyway** for Gaugelet.
4. Authenticate and confirm **Open**.

Do not remove quarantine with Terminal commands. If **Open Anyway** is absent, confirm the app is in `/Applications`, try opening it again, and return immediately to Privacy & Security. Re-download only from the [canonical release](https://github.com/lammworks/Gaugelet/releases/tag/v1.0.0) if the checksum does not match.

Gaugelet does not require Full Disk Access, Accessibility access, Screen Recording, or access to Documents, Desktop, or Downloads. Decline an unexpected broad privacy request and report it.

See [INSTALL.md](INSTALL.md) for the complete installation path.

## No live usage appears

- Run `codex` in Terminal and complete sign-in.
- Confirm the CLI is installed in a supported standard location.
- Verify that Codex works independently before reopening Gaugelet.
- Make sure Settings is using the live Codex source rather than a demo scenario.
- Refresh once and preserve the exact error message.

Gaugelet displays what the local Codex App Server returns. Missing windows remain unavailable. Values can differ materially from ChatGPT's interface and either display may move faster or slower during heavy use. OpenAI's enforced limits are authoritative.

## Launch at Login

The toggle is disabled while Gaugelet runs from a DMG, a translocated path, or an unsupported location. Move the app to `/Applications`, quit the old copy, and open the installed copy.

If Gaugelet reports **Approval required**, choose **Open Login Items Settings**, allow Gaugelet under **System Settings → General → Login Items & Extensions**, and return to Gaugelet. The app refreshes status when it becomes active.

If registration fails, capture the displayed error and file an issue. Do not install a third-party login helper.

## Notifications

Notifications are optional. Enable them in Gaugelet Settings, then approve the macOS prompt. If alerts do not arrive:

1. Open **System Settings → Notifications → Gaugelet**.
2. Turn on **Allow notifications** and select the desired alert style.
3. Confirm Focus or notification-summary settings are not suppressing the alert.
4. Remember that demo and stale readings never notify; an alert occurs only when a live window crosses the configured threshold or reaches its limit.

## Updates

Gaugelet uses Sparkle and GitHub Releases. Update checks require access to `github.com`. If checking fails, verify normal GitHub access, retry later, and review the [Releases page](https://github.com/lammworks/Gaugelet/releases) in your browser. Do not install an update from an unrelated mirror.

## Report a bug or request a feature

Use the repository's [issue forms](https://github.com/lammworks/Gaugelet/issues/new/choose). Search existing issues first.

Include:

- Gaugelet version and build number from About.
- macOS version and Mac model.
- Codex CLI version and whether it works independently.
- Gaugelet state and exact error text.
- Minimal reproduction steps and whether relaunching changes the result.
- A redacted screenshot if it materially helps.

Do not include passwords, cookies, tokens, API keys, Codex authentication files, prompts, responses, private source code, private paths, unredacted account details, or vulnerability details.

## Security reports

Do not open a public issue for a vulnerability. Follow [SECURITY.md](SECURITY.md) and use [GitHub Private Vulnerability Reporting](https://github.com/lammworks/Gaugelet/security/advisories/new).

Gaugelet is independent software and is not affiliated with, endorsed by, or sponsored by OpenAI.

Built by LammWorks.
