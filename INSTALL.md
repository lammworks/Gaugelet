# Install Gaugelet

Gaugelet supports Apple-silicon Macs running macOS 14 or newer. It requires the official Codex CLI and an authenticated Codex session.

Starting with version 1.1.1, Gaugelet is Developer ID signed by **Ondemand Technologies Inc (Lavanda)**, team `K567UPF58F`, and notarized by Apple. The app and DMG are signed, and Apple’s notarization ticket is stapled to the DMG. Open the installed app normally; no **Open Anyway** exception is expected.

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

## 4. Open Gaugelet

1. Double-click `/Applications/Gaugelet.app`.
2. If macOS asks whether to open an app downloaded from the internet, confirm **Open**.
3. Look for Gaugelet in the menu bar.

If macOS says the developer cannot be verified, the app is damaged, or it cannot check for malicious software, do not bypass the warning. Confirm you downloaded version 1.1.1 or newer from the canonical release, recheck the checksum, and follow [SUPPORT.md](SUPPORT.md) with the exact message.

Do not run `xattr` or other commands that remove quarantine.

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

Sparkle authenticates updates with Gaugelet’s update key. Apple Developer ID signing and notarization provide separate checks on the distributed app.

## Historical community releases: 1.0.x and 1.1.0

These older releases were ad-hoc signed and not notarized. Prefer the latest signed release. If you intentionally need a historical community build, first verify its checksum, move it to Applications, and try opening it. Then use **System Settings → Privacy & Security → Open Anyway**, authenticate, and confirm **Open**. This exception applies only to those older community builds; it is not the installation path for 1.1.1 or newer.

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
