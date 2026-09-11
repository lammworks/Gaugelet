# Gaugelet privacy notice

Last updated: September 11, 2026

## Summary

Gaugelet is a local-first menu-bar app. It has no Gaugelet account, advertising, analytics, telemetry, crash-reporting service, usage-history upload, or LammWorks backend.

Gaugelet communicates with two external boundaries:

1. The separately installed Codex CLI may contact OpenAI when Gaugelet asks its local App Server for allowance, reset/credit details, or optional token activity.
2. Sparkle may contact GitHub to check for and download Gaugelet updates.

Gaugelet does not sell personal information.

## Codex usage data

For live mode, Gaugelet starts the locally installed `codex app-server`, initializes a private standard-input/output session, and sends a read-only `account/rateLimits/read` request.

The response may contain:

- Usage-window names or identifiers.
- Percent used or remaining.
- Window duration and reset time, when returned.
- Plan or model labels, when returned.
- Rate-limit, workspace-credit, or spending-control state, when returned.
- Earned reset count and the earliest known future expiry among returned available resets.
- Credit balances and availability, kept separate by returned bucket and never summed.
- An account identifier, used only in memory to avoid alerts across account changes.

When **Token activity** is enabled, Gaugelet also sends the read-only `account/usage/read` request. It displays up to seven reported daily token buckets and lifetime tokens, when returned. Missing days are not filled with zeroes. The optional activity request can fail without hiding allowance data. Gaugelet does not request thread history or task status.

The **Manage usage** action opens OpenAI’s usage page. Gaugelet does not redeem resets, buy credits, change plans, or send messages.

Gaugelet does not ask this integration for conversation content, prompts, responses, message history, project files, or billing transactions.

### Authentication boundary

The Codex CLI owns authentication. Gaugelet does not read or copy browser cookies, browser storage, Codex authentication files, access or refresh tokens, API keys, or passwords.

The Codex CLI may use its existing session to communicate with OpenAI. OpenAI and the Codex CLI process data under their own terms and privacy notices; Gaugelet cannot control that separate relationship. Gaugelet does not proxy Codex traffic through LammWorks.

## Update checks

Gaugelet includes Sparkle 2.9.6. If you accept automatic update checks, Sparkle normally requests this GitHub-hosted appcast about once every 24 hours. A manual **Check for Updates** request uses the same channel:

`https://github.com/lammworks/Gaugelet/releases/latest/download/appcast.xml`

If you approve an update, Sparkle downloads the selected DMG from GitHub Releases. GitHub and its network providers may receive ordinary network metadata such as the source IP address, request time, requested URL, transport details, and user-agent information. Their handling of that data is governed by their own policies.

Gaugelet disables Sparkle system profiling. It does not deliberately attach a hardware or macOS system profile to update requests. Gaugelet also disables silent update installation: download and installation require user confirmation.

Sparkle verifies the signed update feed and enclosure before extraction. Update authentication does not make the initial Gaugelet download Apple-notarized.

## Local storage

Gaugelet stores preferences with the standard macOS preferences system, including settings such as:

- Menu-bar percentage and hover behavior.
- Warning threshold, usage alerts, and optional allowance-restored alerts.
- Pinned menu-bar counter identifier and token-activity preference.
- Launch-at-login intent and status-related state.
- Selected icon theme.
- Selected source mode and demo scenario.
- Sparkle update-check preference, managed by Sparkle.

Live percentages, account identifiers, credit/reset details, and token activity remain in process memory. A last successful reading may remain in memory briefly enough to be shown as explicitly stale after a refresh failure. Gaugelet does not maintain a persistent usage-history database.

When notifications are enabled, Gaugelet asks macOS to deliver a local notification when any live window crosses the selected threshold or reaches its limit. With restoration alerts enabled, it also notifies after a fresh reading confirms a blocked window is available again. Demo and stale readings never trigger an alert. Gaugelet does not send notification content to LammWorks.

macOS and GitHub may independently retain operational records such as system logs, crash logs, quarantine data, access logs, or release-download logs. Gaugelet does not upload macOS logs.

## Demo, stale, unavailable, and signed-out states

Demo data is generated locally and labeled as demo. If a refresh fails after a successful reading, Gaugelet may show the last reading as stale with its original update time and the failure reason. If no successful reading exists, Gaugelet shows unavailable or signed out. It does not replace missing account data with plausible percentages.

## Retention and deletion

Because Gaugelet operates no backend, there is no Gaugelet server account or server-side usage history to delete.

Removing Gaugelet deletes the app but may leave its macOS preferences. To remove those preferences, quit Gaugelet and run:

```bash
defaults delete com.lammworks.gaugelet
```

This affects Gaugelet preferences only. It does not modify Codex CLI credentials or OpenAI account data. Use Codex or OpenAI controls for those separate systems.

## Information you choose to share

GitHub processes information you voluntarily submit in an issue, pull request, security advisory, or other repository interaction. Remove account names, file paths, tokens, cookies, keys, prompts, source code, and other sensitive material before sharing diagnostics.

Use [GitHub Issues](https://github.com/lammworks/Gaugelet/issues/new/choose) for non-sensitive privacy questions. Use [GitHub Private Vulnerability Reporting](https://github.com/lammworks/Gaugelet/security/advisories/new) for a suspected security or privacy vulnerability. No support email is represented by this project.

## Changes

This notice must be reviewed before Gaugelet adds analytics, crash reporting, persistent usage history, another data provider, account functionality, a LammWorks service, or materially different update behavior. Material changes are recorded in [CHANGELOG.md](CHANGELOG.md).

Gaugelet is independent software and is not affiliated with, endorsed by, or sponsored by OpenAI.

Built by LammWorks.
