# Usage data source

Gaugelet defaults to a read-only integration with the installed Codex CLI's App Server.

The official [Codex App Server documentation](https://learn.chatgpt.com/docs/app-server) documents `account/rateLimits/read`, including `usedPercent`, `windowDurationMins`, and `resetsAt`. Gaugelet derives remaining allowance as `100 - usedPercent` and does not attempt to estimate a number of messages.

Gaugelet automatically asks Codex for a fresh snapshot every five minutes on AC power, ten minutes on battery or UPS, and fifteen minutes in Low Power Mode. Low Power Mode takes precedence over the power source. Routine background refresh allows up to five seconds of scheduling tolerance, and macOS may defer it further. Gaugelet also refreshes on wake, on open when the reading is at least a minute old, and after expected resets; the refresh button can request a reading sooner. Alerts depend on fresh readings and may arrive later at the longer intervals. The prominent gauge is the most constrained returned window; the dashboard also retains and labels the other distinct overall/model windows returned by Codex.

## Privacy boundaries

- Gaugelet starts `codex app-server` over a private stdio pipe for each refresh.
- Codex owns authentication. Gaugelet never reads browser cookies, browser storage, auth files, access tokens, or API keys.
- The app requests only rate-limit data. It does not start threads, consume reset credits, sign users out, or change Codex configuration.
- Percentages and reset timestamps stay in memory in this prototype.
- If Codex or its usage response is unavailable, the UI shows an explicit unavailable state. After a successful live reading, a failed refresh may retain that exact reading only as visibly stale data. Demo values appear only when the user deliberately selects Demo data in Settings.

## Stability

OpenAI currently classifies `codex app-server` as experimental. Its protocol may change without notice. Gaugelet treats fields and buckets defensively and reports stale or unavailable state instead of inventing values.

The OpenAI Platform organization Usage API is intentionally not used: it reports API consumption, not a user's ChatGPT subscription allowance.
