# Gaugelet Product Hunt launch kit

Status: **Prepared only. Do not submit, schedule, or publish without explicit approval.**

## Listing

| Field | Final copy |
| --- | --- |
| Product name | Gaugelet |
| Tagline | See ChatGPT and Codex allowance before you hit the limit |
| Pricing | Free |
| Tags | Developer Tools, Productivity, Mac |
| Product URL | `https://gaugelet.wonkytonks.chatgpt.site` — use the direct URL with no shortener or tracking parameters |
| Repository | `https://github.com/lammworks/Gaugelet` |
| Download | `https://github.com/lammworks/Gaugelet/releases/download/v1.0.0/Gaugelet.dmg` |

### Description — 397 characters

Gaugelet is a native Apple-silicon menu-bar app that tracks the ChatGPT and Codex allowance windows exposed through your local Codex App Server, so you can adjust model, reasoning, and pace before a limit blocks your work. It refreshes every five minutes or on demand, supports low-usage alerts, and stays local-first. Free, open source, and independent from OpenAI. macOS 14+; Codex CLI required.

The description must remain at or below 500 characters after any edit.

## Maker first comment

I built Gaugelet because a high-cost ChatGPT plan still requires constant small decisions: which Codex model to use, how much reasoning a task needs, and when to slow down. The expensive mistake is discovering the limit only after work stops.

Gaugelet keeps the ChatGPT and Codex allowance windows returned by the local Codex App Server in the Mac menu bar, refreshes every five minutes or on demand, and can warn when a live window runs low. It is free, open source, and has no analytics or backend.

One important limitation: Gaugelet and ChatGPT can drift materially, especially during heavy use, and either display may move first. OpenAI's enforced limits are authoritative. Version 1.0 is also ad-hoc signed, so the first launch uses macOS Open Anyway.

I would value feedback on whether the counters help you choose models and reasoning levels earlier, and which upstream windows are most useful in your workflow.

Built by LammWorks.

## Gallery assets

Prepare these files before submission:

| Asset | Specification | Content |
| --- | --- | --- |
| Thumbnail | [`website/public/images/product-hunt-thumbnail.jpg`](website/public/images/product-hunt-thumbnail.jpg) · 240×240 px · under 3 MB | Blue Core gauge icon on a clean neutral background, verified at native size |
| Gallery 1 | [`website/public/images/product-hunt-gallery-1.jpg`](website/public/images/product-hunt-gallery-1.jpg) · 1270×760 px | Hero: ChatGPT + Codex allowance positioning, menu-bar icon, and three explicitly illustrative counters |
| Gallery 2 | [`website/public/images/product-hunt-gallery-2.jpg`](website/public/images/product-hunt-gallery-2.jpg) · 1270×760 px | Decision story: choose model, reasoning, and pace before a limit blocks work |
| Gallery 3 | 1270×760 px, optional | Trust story: local Codex App Server, five-minute refresh, privacy, and honest drift boundary |

The prepared assets use only illustrative values and contain no account names, emails, private paths, prompts, or real usage data. Keep key text inside safe margins and verify every image at native resolution before submission. Do not claim that every account returns the same three windows.

## Launch preparation

Complete at least one week before launch:

- Finish the maker profile and participate constructively in the Product Hunt community.
- Verify the configured Sites URL resolves directly to the launch page without redirects or tracking parameters.
- Verify the public repository, privacy, support, security, install, and changelog pages.
- Download the exact public DMG, verify its SHA-256 digest, and repeat clean-machine installation.
- Seed and complete a Sparkle `1.0.0 → 1.0.1` update test before the launch channel is trusted.
- Confirm the thumbnail and at least two gallery images meet dimensions and file-size limits.
- Prepare concise answers for installation, Gatekeeper, privacy, accuracy drift, Codex CLI, and OpenAI non-affiliation.
- Confirm the release owner has authority to publish. Product Hunt submission remains a separate approval.

Recommended launch time: **12:01 a.m. Pacific**, after at least one week of profile and community preparation. Confirm the Pacific time-zone offset on the chosen date before scheduling.

## Launch-day response plan

| Window | Owner | Action |
| --- | --- | --- |
| First 30 minutes | Maker | Verify listing, direct URL, screenshots, download, and top comment; correct factual errors only |
| First 4 hours | Maker | Reply to questions about workflow, limitations, privacy, and installation; log bugs separately |
| Rest of launch day | Support triage | Classify feedback as P0 security/distribution, P1 broken core flow, or P2 enhancement |
| End of day | Release owner | Summarize verified issues, decide whether promotion should continue, and publish corrections if needed |
| Next 72 hours | Maintainer | Respond to reproducible issues, update FAQ/support content, and avoid promising unplanned features |

Stop promotion immediately for a checksum mismatch, compromised link, unsafe update behavior, material privacy discrepancy, or broadly reproducible launch failure.

## Feedback-oriented social copy

### Short

I built Gaugelet, a free macOS menu-bar app that tracks the ChatGPT and Codex allowance windows returned on your Mac. It helps you adjust model, reasoning, and pace before a limit stops the work. I would value feedback on whether the view changes how you manage a heavy AI coding day. https://gaugelet.wonkytonks.chatgpt.site

### Technical

Gaugelet 1.0 is a native Apple-silicon menu-bar app for ChatGPT and Codex allowance windows: local Codex App Server source, five-minute refresh plus on-demand refresh, signed Sparkle updates, and no analytics or backend. The upstream values can drift from ChatGPT, so OpenAI remains authoritative. Feedback welcome: https://gaugelet.wonkytonks.chatgpt.site

### Privacy-focused

Gaugelet displays ChatGPT and Codex allowance data by reading rate-limit windows through a local stdio connection to the Codex App Server. It does not read credentials, prompts, responses, or project files, and it runs no analytics or usage backend. I would appreciate scrutiny of the privacy model and installation guide: https://gaugelet.wonkytonks.chatgpt.site

These messages ask for feedback, not votes. Do not request, trade, reward, or incentivize upvotes. Do not add tracking parameters or shortened URLs.
