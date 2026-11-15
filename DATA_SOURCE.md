# Usage data source

Gaugelet defaults to a read-only integration with the installed Codex CLI's App Server.

The official [Codex App Server documentation](https://learn.chatgpt.com/docs/app-server) documents `account/rateLimits/read`, including `usedPercent`, `windowDurationMins`, and `resetsAt`. Gaugelet derives remaining allowance as `100 - usedPercent` and does not attempt to estimate a number of messages.

Gaugelet automatically asks Codex for a fresh snapshot every five minutes, and the refresh button can request one sooner. The prominent gauge is the most constrained returned window; the dashboard also retains and labels the other distinct overall/model windows returned by Codex.

## Cursor and Grok plan usage

Cursor plan usage is off until you enable it. Gaugelet then reads one saved access token and requests the current plan reading. It does not read chat history, composer data, or a tracking database, and it does not write or refresh the token.

- The token is `cursorAuth/accessToken` in `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`, opened read-only.
- The gauge prefers `POST https://cursor.com/api/dashboard/get-current-period-usage`.
- If that call cannot be completed, Gaugelet tries `POST https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage`.
- A rejected token is shown as signed out. Gaugelet does not use `GET /api/usage-summary` as the gauge, because that summary can report a monthly window and 0% while the current-period reading has the weekly pool.
- On The X Subscription, a cycle of about seven days is one included weekly pool shared by Grok and Cursor. Third-party model usage is prepaid Additional Usage, not spare included allowance. A missing dollar amount is left blank.
- Older Cursor plans keep the included, Auto, and API percents only when those percents are distinct.
- If Cursor has no saved session and `~/.grok/auth.json` has an access token, Gaugelet requests `GET https://cli-chat-proxy.grok.com/v1/billing?format=credits` and shows that percent as the same included row. When both sign-ins exist, the Cursor current-period reading is the only meter.

Manage usage opens [grok.com/dashboard](https://grok.com/dashboard) for a weekly pool and Cursor’s spending dashboard for an older plan. Gaugelet does not buy credit or change the plan.

## Privacy boundaries

- Gaugelet starts `codex app-server` over a private stdio pipe for each refresh.
- Codex owns authentication. Gaugelet never reads browser cookies, browser storage, Codex authentication files, or Codex access tokens or API keys.
- The optional Cursor reading uses only the single key above, holds it in memory for one request, and does not store it in preferences or logs.
- The app requests only rate-limit and plan-usage data. It does not start threads, consume reset credits, sign users out, or change Codex or Cursor configuration.
- Percentages and reset timestamps stay in memory in this prototype.
- If Codex, Cursor, or a usage response is unavailable, the UI shows an explicit unavailable state. After a successful live reading, a failed refresh may retain that exact reading only as visibly stale data. Demo values appear only when the user deliberately selects Demo data in Settings. A Cursor failure does not replace a good ChatGPT reading.

## Stability

OpenAI currently classifies `codex app-server` as experimental. Its protocol may change without notice. Gaugelet treats fields and buckets defensively and reports stale or unavailable state instead of inventing values.

The OpenAI Platform organization Usage API is intentionally not used: it reports API consumption, not a user's ChatGPT subscription allowance. Cursor’s monthly usage-summary endpoint is also not used as the gauge.
