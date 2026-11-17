# Usage data source

Gaugelet defaults to a read-only integration with the installed Codex CLI's App Server.

The official [Codex App Server documentation](https://learn.chatgpt.com/docs/app-server) documents `account/rateLimits/read`, including `usedPercent`, `windowDurationMins`, and `resetsAt`. Gaugelet derives remaining allowance as `100 - usedPercent` and does not attempt to estimate a number of messages.

Gaugelet automatically asks Codex for a fresh snapshot every five minutes, and the refresh button can request one sooner. The prominent gauge is the most constrained returned window; the dashboard also retains and labels the other distinct overall/model windows returned by Codex.

## Cursor and Grok plan usage

Cursor plan usage is off until you enable it. Gaugelet then reads the saved Cursor access token, and the Grok CLI sign-in when that file is present, and requests the current plan readings. It does not read chat history, composer data, or a tracking database, and it does not write or refresh either token.

- The token is `cursorAuth/accessToken` in `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`, opened read-only. ItemTable is checked first, then `cursorDiskKV`. If that database has no token, Gaugelet also checks the Cursor Nightly and Cursor Insiders copies of the same path.
- Current Cursor builds store that value sealed as `cursor-safe-storage:v1:` plus a base64 `v10` blob. Gaugelet unseals it in memory with the Keychain generic password whose service is `Cursor Safe Storage` and whose account is `Cursor Key` (older builds use the account `Cursor`). The Keychain read does not prompt. A plaintext token in the same key is still accepted. The sealed text is never sent as the bearer.
- The gauge prefers `POST https://cursor.com/api/dashboard/get-current-period-usage`.
- If that call cannot be completed, Gaugelet tries `POST https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage`.
- A token that Cursor rejects is shown as a failed request, with the HTTP status. A missing token is shown as not signed in. A sealed token that cannot be unsealed names the Keychain item. A request that does not answer within 12 seconds is shown as timed out. Gaugelet does not use `GET /api/usage-summary` as the gauge, because that summary can report a monthly window and 0% while the current-period reading has the weekly pool.
- On The X Subscription, a cycle of about seven days is one included weekly pool shared by Grok and Cursor. Third-party model usage is prepaid Additional Usage, not spare included allowance. A missing dollar amount is left blank.
- Older Cursor plans keep the included, Auto, and API percents only when those percents are distinct.
- Grok credits are a separate reading from the Cursor plan. Gaugelet looks for a Grok sign-in in `$GROK_HOME/auth.json` when `GROK_HOME` is set, otherwise `~/.grok/auth.json`. It does not read the macOS keychain for Grok and it does not refresh the token.
- The file written by `grok login` is a map of scope to credential. The bearer is `key` under `https://auth.x.ai::<client id>`. An expired `expires_at` is shown as signed out. A top-level `access_token` is still accepted. An `xai::api_key` entry is not used for this reading.
- When that sign-in is usable, Gaugelet requests `GET https://cli-chat-proxy.grok.com/v1/billing?format=credits` with `Authorization: Bearer` and `X-XAI-Token-Auth: xai-grok-cli`. If the entry has `user_id`, that value is sent as `x-userid` on the same request and is not stored.
- `config.creditUsagePercent` is the percent of the one weekly plan that is used. Gaugelet shows what is left. `config.productUsage` entries, such as Cursor, Grok Bot, Bugbot, Chat, Voice, and Grok Build, are each product’s share of that same used amount. They are not separate allowances. Grok Build is the `grok` coding CLI and draws from this plan. Sign in by running `grok login` in Terminal. Opening grok.com does not update the sign-in file. Prepaid and on-demand amounts use the cent object `val`. An older payload can use `used.val` and `monthlyLimit.val`. A current period with no percent is zero usage for that period. A response with none of those fields stays unavailable and names the JSON keys that were present, not their values.
- When both sign-ins exist, the Cursor rows and the Grok rows are both shown. They are not added together. A rejected Cursor token does not hide a working Grok sign-in.

Manage usage opens [grok.com/dashboard](https://grok.com/dashboard) for a weekly pool and Cursor’s spending dashboard for an older plan. Gaugelet does not buy credit or change the plan.

## Privacy boundaries

- Gaugelet starts `codex app-server` over a private stdio pipe for each refresh.
- Codex owns authentication. Gaugelet never reads browser cookies, browser storage, Codex authentication files, or Codex access tokens or API keys.
- The optional Cursor reading uses only the single key above, holds that token in memory for one request, and does not store it in preferences or logs. A signed-in reading may also keep an in-memory session identifier, never the token, so alerts are not compared across account changes. Reset timestamps outside 2000–2100 are left unavailable.
- The app requests only rate-limit and plan-usage data. It does not start threads, consume reset credits, sign users out, or change Codex or Cursor configuration.
- Percentages and reset timestamps stay in memory in this prototype.
- If Codex, Cursor, or a usage response is unavailable, the UI shows an explicit unavailable state. After a successful live reading, a failed refresh may retain that exact reading only as visibly stale data. Demo values appear only when the user deliberately selects Demo data in Settings. A Cursor failure does not replace a good ChatGPT reading.

## Stability

OpenAI currently classifies `codex app-server` as experimental. Its protocol may change without notice. Gaugelet treats fields and buckets defensively and reports stale or unavailable state instead of inventing values.

The OpenAI Platform organization Usage API is intentionally not used: it reports API consumption, not a user's ChatGPT subscription allowance. Cursor’s monthly usage-summary endpoint is also not used as the gauge.
