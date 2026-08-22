# Install Gaugelet 1.0

Gaugelet 1.0 supports Apple-silicon Macs running macOS 14 or newer. It requires the official Codex CLI and an authenticated Codex session.

The community release is ad-hoc code-signed and is not notarized by Apple. Gatekeeper will block the first launch; use the documented macOS **Open Anyway** control after verifying the download.

## 1. Prepare Codex

Install the official [Codex CLI](https://developers.openai.com/codex/cli), then run:

```bash
codex --version
codex
```

Complete sign-in in Codex. A ChatGPT browser session by itself is not enough. Gaugelet looks for Codex in standard locations such as Homebrew, `/usr/local/bin`, `/usr/bin`, and `~/.local/bin`.

## 2. Download and verify

Download both files from the latest release:

- [`Gaugelet.dmg`](https://github.com/lammworks/Gaugelet/releases/latest/download/Gaugelet.dmg)
- [`Gaugelet.dmg.sha256`](https://github.com/lammworks/Gaugelet/releases/latest/download/Gaugelet.dmg.sha256)

Keep both filenames unchanged in the same folder, then run:

```bash
cd ~/Downloads
shasum -a 256 -c Gaugelet.dmg.sha256
```

Continue only if the result is `Gaugelet.dmg: OK`. A mismatch means the bytes are not the published artifact: delete that download and report the release problem. Do not bypass the mismatch.

## 3. Move Gaugelet to Applications

1. Open `Gaugelet.dmg`.
2. Drag **Gaugelet** onto the **Applications** shortcut.
3. Eject the DMG.
4. Open `/Applications` in Finder and confirm Gaugelet is there.

Do not run Gaugelet from the mounted DMG. Launch at Login is disabled for a DMG, a translocated copy, or another unsupported location.

## 4. Use macOS Open Anyway

1. Double-click `/Applications/Gaugelet.app` once. macOS is expected to block this non-notarized build.
2. Open **System Settings → Privacy & Security**.
3. Scroll to the Security section and choose **Open Anyway** for Gaugelet.
4. Authenticate with Touch ID or your Mac password.
5. Confirm **Open** in the final dialog.

If **Open Anyway** is not visible, verify Gaugelet is in `/Applications`, try opening it again, and return immediately to Privacy & Security.

Do not run `xattr` or other commands that remove quarantine. The macOS control preserves the visible security decision and limits the exception to the app you chose.

## 5. Confirm live usage

Gaugelet appears in the menu bar rather than the Dock.

1. Click its menu-bar icon.
2. Confirm the source is live, not demo, stale, unavailable, or signed out.
3. Use manual refresh once.
4. If Codex is missing or signed out, fix that in Terminal and retry.

Gaugelet refreshes automatically every five minutes. Its values can drift materially from ChatGPT's interface, and either display may move faster or slower during heavy use. OpenAI's enforced limits are authoritative.

## Launch at Login

In Gaugelet Settings, turn on **Launch at Login**. If macOS reports that approval is required:

1. Choose **Open Login Items Settings** in Gaugelet.
2. Allow Gaugelet under **System Settings → General → Login Items & Extensions**.
3. Return to Gaugelet so it can refresh the status.

Test the setting by logging out and back in. If you update Gaugelet through Sparkle, confirm the setting remains enabled after replacement.

## Notifications

In Gaugelet Settings, enable usage notifications and approve the macOS permission prompt. To change permission later, open **System Settings → Notifications → Gaugelet**.

Notifications use live readings only. Demo and stale readings do not alert. Focus modes and notification summaries can delay or hide delivery.

Gaugelet does not require Full Disk Access, Accessibility access, Screen Recording, or access to Documents, Desktop, or Downloads. Decline an unexpected broad privacy request and [report it](https://github.com/lammworks/Gaugelet/issues/new/choose).

## Updates

Gaugelet uses Sparkle to check a signed GitHub Releases feed. If you accept automatic checks, they normally run about once per day. You can also choose **Check for Updates**. Every update requires confirmation; silent installation is disabled.

Sparkle authenticates updates but does not change the initial app's non-notarized status.

## Uninstall

1. Quit Gaugelet.
2. Turn off Launch at Login if the app is still installed.
3. Move `/Applications/Gaugelet.app` to Trash.

To remove Gaugelet's preferences too:

```bash
defaults delete com.lammworks.gaugelet
```

This does not remove Codex or change your OpenAI account.

For unresolved problems, follow [SUPPORT.md](SUPPORT.md).

Built by LammWorks.
